import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:diacritic/diacritic.dart';
import 'dart:async';
import '../../../../core/services/notification_service.dart';
import '../../../../providers/user_data_provider.dart';

class SalvarTratamento {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  final String nomeMedicamento;
  final String tipoMedicamento;
  final String concentracaoMedicamento;
  final String qtdMedicamento;              // QTD por dose (unidades)
  final String qtdMedicamentoTotal;         // total de unidades para o período
  final String frequenciaHoras;             // usado no modo intervalo
  final String dataInicial;                 // dd/MM/yyyy
  final String horaInicial;                 // HH:mm (modo intervalo)

  final String observacoes;
  final String? tipoTratamento;
  final List<String> horariosFixos;         // se não vazio => modo fixo
  final String qtdMedicamentoEstoqueCtrl;
  final String qtdEstoqueMinimoCtrl;
  final String dataValidadeCtrl;            // dd/MM/yyyy
  final String tipoFrequencia;
  final UsuarioProvider usuarioProvider;
  final bool isContinuo;
  final int janelaPreGeracaoDias;
  final List<String> refeicoesSelecionadas;

  /// Novo: timeout curto para decidir fallback offline sem travar UI
  final Duration writeTimeout;

  SalvarTratamento({
    required this.nomeMedicamento,
    required this.tipoMedicamento,
    required this.concentracaoMedicamento,
    required this.qtdMedicamento,
    required this.qtdMedicamentoTotal,
    required this.frequenciaHoras,
    required this.dataInicial,
    required this.horaInicial,
    required this.observacoes,
    required this.tipoTratamento,
    required this.qtdMedicamentoEstoqueCtrl,
    required this.qtdEstoqueMinimoCtrl,
    required this.dataValidadeCtrl,
    required this.usuarioProvider,
    required this.horariosFixos,
    required this.tipoFrequencia,
    required this.refeicoesSelecionadas,
    required this.isContinuo,
    this.janelaPreGeracaoDias = 15,
    this.writeTimeout = const Duration(seconds: 2), // << aqui
  });

  // ------------------- Utils & Helpers -------------------

  String get _targetUid {
    final ctx = (usuarioProvider.contextoUsuarioId ?? '').trim();
    return usuarioProvider.isContextoSouEu ? usuarioProvider.userId : ctx;
  }

  void _assertTargetUid() {
    if (!usuarioProvider.isContextoSouEu && (_targetUid.isEmpty)) {
      throw Exception('Contexto de paciente sem UID definido (contextoUsuarioId vazio).');
    }
  }

  Map<String, dynamic> _updatedBy(String role) => {
    'uid': usuarioProvider.userId,
    'role': role, // 'patient' ou 'caregiver'
  };

  int _parseIntSafe(String s, {int fallback = 0}) {
    final v = int.tryParse(s.trim());
    return v == null ? fallback : v;
  }

  DateTime _parseDate(String ddMMyyyy) => DateFormat("dd/MM/yyyy").parse(ddMMyyyy);

  DateTime _parseTimeOnDate(String HHmm, DateTime date) {
    final t = DateFormat("HH:mm").parse(HHmm);
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  Duration? _parseHHmm(String s) {
    final p = s.trim().split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return Duration(hours: h, minutes: m);
  }

  DateTime? _parseDateddMMyyyy(String d) {
    final p = d.split('/');
    if (p.length != 3) return null;
    final dia = int.tryParse(p[0]);
    final mes = int.tryParse(p[1]);
    final ano = int.tryParse(p[2]);
    if (dia == null || mes == null || ano == null) return null;
    return DateTime(ano, mes, dia);
  }

  DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  DateTime _safeStartInterval(DateTime baseDate) {
    try {
      return _parseTimeOnDate(horaInicial, baseDate);
    } catch (_) {
      return DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 0);
    }
  }

  String? _inferirMomentoRefeicao(DateTime dt, List<dynamic>? horariosRefeicoesProvider) {
    if (horariosRefeicoesProvider == null || refeicoesSelecionadas.isEmpty) return null;

    final chaveDia = _diaSemanaPTBR(dt);
    final cfgDia = _obterConfigDoDia(horariosRefeicoesProvider, chaveDia);

    final mapaMomento = <String, String>{
      'cafe': ((cfgDia?['horaCafe'] ?? '').toString().trim().isNotEmpty)
          ? (cfgDia?['horaCafe'] ?? '').toString().trim()
          : '07:30',
      'almoco': ((cfgDia?['horaAlmoco'] ?? '').toString().trim().isNotEmpty)
          ? (cfgDia?['horaAlmoco'] ?? '').toString().trim()
          : '12:00',
      'jantar': ((cfgDia?['horaJanta'] ?? '').toString().trim().isNotEmpty)
          ? (cfgDia?['horaJanta'] ?? '').toString().trim()
          : '19:00',
    };

    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final hhmm = '$hh:$mm';
    for (final r in refeicoesSelecionadas) {
      if (mapaMomento[r] == hhmm) return r;
    }
    int toMin(String s) {
      final d = _parseHHmm(s);
      return d == null ? -1 : d.inMinutes;
    }

    final alvo = toMin(hhmm);
    if (alvo >= 0) {
      for (final r in refeicoesSelecionadas) {
        final m = toMin(mapaMomento[r] ?? '');
        if (m >= 0 && ((alvo - m).abs() <= 2)) return r;
      }
    }
    return null;
  }

  String _normDia(String dia) {
    final d = dia.trim().toLowerCase();
    switch (d) {
      case 'seg':
      case 'segunda':
        return 'segunda';
      case 'ter':
      case 'terça':
      case 'terca':
        return 'terça';
      case 'qua':
      case 'quarta':
        return 'quarta';
      case 'qui':
      case 'quinta':
        return 'quinta';
      case 'sex':
      case 'sexta':
        return 'sexta';
      case 'sab':
      case 'sábado':
      case 'sabado':
        return 'sábado';
      case 'dom':
      case 'domingo':
        return 'domingo';
      case 'padrao':
      case 'padrão':
        return 'padrao';
      default:
        return d;
    }
  }

  String _diaSemanaPTBR(DateTime dt) {
    switch (dt.weekday) {
      case DateTime.monday:
        return 'segunda';
      case DateTime.tuesday:
        return 'terça';
      case DateTime.wednesday:
        return 'quarta';
      case DateTime.thursday:
        return 'quinta';
      case DateTime.friday:
        return 'sexta';
      case DateTime.saturday:
        return 'sábado';
      case DateTime.sunday:
        return 'domingo';
      default:
        return 'padrao';
    }
  }

  Map<String, dynamic>? _obterConfigDoDia(List<dynamic>? horariosRefeicoes, String chaveDia) {
    if (horariosRefeicoes == null) return null;
    Map<String, dynamic>? padrao;
    for (final item in horariosRefeicoes) {
      if (item is Map<String, dynamic>) {
        final diaStr = _normDia(item['dia']?.toString() ?? '');
        if (diaStr == 'padrao') padrao = item;
        if (diaStr == chaveDia) return item;
      } else if (item is Map) {
        final diaStr = _normDia(item['dia']?.toString() ?? '');
        if (diaStr == 'padrao') padrao = Map<String, dynamic>.from(item);
        if (diaStr == chaveDia) return Map<String, dynamic>.from(item);
      }
    }
    return padrao;
  }

  List<String> _horariosDasRefeicoesNoDia(Map<String, dynamic>? cfgDia, List<String> refeicoes) {
    final out = <String>[];
    if (cfgDia != null) {
      for (final r in refeicoes) {
        switch (r) {
          case 'cafe':
            if ((cfgDia['horaCafe'] ?? '').toString().trim().isNotEmpty) {
              out.add(cfgDia['horaCafe']);
            }
            break;
          case 'almoco':
            if ((cfgDia['horaAlmoco'] ?? '').toString().trim().isNotEmpty) {
              out.add(cfgDia['horaAlmoco']);
            }
            break;
          case 'jantar':
            if ((cfgDia['horaJanta'] ?? '').toString().trim().isNotEmpty) {
              out.add(cfgDia['horaJanta']);
            }
            break;
        }
      }
    }

    if (out.isEmpty) {
      final defaults = {'cafe': '07:30', 'almoco': '12:00', 'jantar': '19:00'};
      for (final r in refeicoes) {
        final hhmm = defaults[r];
        if (hhmm != null) out.add(hhmm);
      }
    }

    final durs = out.map(_parseHHmm).whereType<Duration>().toList()
      ..sort((a, b) => a.inMinutes.compareTo(b.inMinutes));
    final seen = <int>{};
    final norm = <String>[];
    for (final d in durs) {
      final key = d.inMinutes;
      if (seen.add(key)) {
        final hh = d.inHours.toString().padLeft(2, '0');
        final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
        norm.add('$hh:$mm');
      }
    }
    return norm;
  }

  List<DateTime> _gerarLembretesRefeicaoAte({
    required DateTime dataInicial,
    required List<String> refeicoes,
    required List<dynamic>? horariosRefeicoesProvider,
    required DateTime endIncl,
  }) {
    final result = <DateTime>[];
    final agora = DateTime.now();
    final limitePrimeiroDia = agora.add(const Duration(minutes: 10));
    DateTime dia = DateTime(dataInicial.year, dataInicial.month, dataInicial.day);

    while (!dia.isAfter(endIncl)) {
      final chaveDia = _diaSemanaPTBR(dia);
      final cfgDia = _obterConfigDoDia(horariosRefeicoesProvider, chaveDia);
      final horariosHHmm = _horariosDasRefeicoesNoDia(cfgDia, refeicoes);

      for (final hhmm in horariosHHmm) {
        final dt = _parseTimeOnDate(hhmm, dia);
        final mesmoDiaHoje =
            dt.year == agora.year && dt.month == agora.month && dt.day == agora.day;
        if (mesmoDiaHoje && dt.isBefore(limitePrimeiroDia)) continue;
        if (dt.isAfter(endIncl)) return result;
        result.add(dt);
      }
      dia = dia.add(const Duration(days: 1));
    }
    return result;
  }

  List<DateTime> _gerarLembretesFixosAte({
    required DateTime dataInicialDate,
    required List<String> horariosHHmm,
    required DateTime endIncl,
  }) {
    final horas = horariosHHmm.map(_parseHHmm).whereType<Duration>().toList()
      ..sort((a, b) => a.inMinutes.compareTo(b.inMinutes));
    if (horas.isEmpty) return [];

    final result = <DateTime>[];
    final agora = DateTime.now();
    final limitePrimeiroDia = agora.add(const Duration(minutes: 10));
    DateTime dia = DateTime(dataInicialDate.year, dataInicialDate.month, dataInicialDate.day);

    while (!dia.isAfter(endIncl)) {
      for (final h in horas) {
        final dt = DateTime(dia.year, dia.month, dia.day).add(h);
        final mesmoDiaHoje =
            dt.year == agora.year && dt.month == agora.month && dt.day == agora.day;
        if (mesmoDiaHoje && dt.isBefore(limitePrimeiroDia)) continue;
        if (dt.isAfter(endIncl)) return result;
        result.add(dt);
      }
      dia = dia.add(const Duration(days: 1));
    }
    return result;
  }

  List<DateTime> _gerarLembretesIntervaloAte({
    required DateTime startDateTime,
    required int freqHoras,
    required DateTime endIncl,
  }) {
    if (freqHoras <= 0) return [];
    final out = <DateTime>[];
    final nowPlus10 = DateTime.now().add(const Duration(minutes: 10));
    var t = startDateTime.isBefore(nowPlus10) ? nowPlus10 : startDateTime;
    while (!t.isAfter(endIncl)) {
      out.add(t);
      t = t.add(Duration(hours: freqHoras));
    }
    return out;
  }

  List<DateTime> _gerarLembretesFixos({
    required DateTime dataInicialDate,
    required List<String> horariosHHmm,
    required int totalDoses,
  }) {
    if (horariosHHmm.isEmpty || totalDoses <= 0) {
      throw ArgumentError('Entradas inválidas em _gerarLembretesFixos');
    }
    final horas = horariosHHmm.map(_parseHHmm).whereType<Duration>().toList()
      ..sort((a, b) => a.inMinutes.compareTo(b.inMinutes));
    if (horas.isEmpty) {
      throw ArgumentError('Nenhum horário válido em horariosFixos');
    }

    final agora = DateTime.now();
    final limite = agora.add(const Duration(minutes: 5));
    final baseDia0 = DateTime(dataInicialDate.year, dataInicialDate.month, dataInicialDate.day);
    final isDia0Hoje =
        baseDia0.year == agora.year && baseDia0.month == agora.month && baseDia0.day == agora.day;

    final result = <DateTime>[];
    int diaOffset = 0;

    while (result.length < totalDoses) {
      final baseDia = baseDia0.add(Duration(days: diaOffset));
      for (final h in horas) {
        final dt = baseDia.add(h);
        if (result.length >= totalDoses) break;

        if (isDia0Hoje && diaOffset == 0) {
          if (dt.isBefore(limite)) continue;
        } else {
          if (baseDia.year == agora.year &&
              baseDia.month == agora.month &&
              baseDia.day == agora.day) {
            if (dt.isBefore(limite)) continue;
          }
        }
        result.add(dt);
      }
      if (result.isEmpty && diaOffset == 0) {
        diaOffset++;
        continue;
      }
      if (result.length < totalDoses) diaOffset++;
    }
    return result;
  }

  List<DateTime> _gerarLembretesPorRefeicao({
    required DateTime dataInicial,
    required List<String> refeicoes,
    required List<dynamic>? horariosRefeicoesProvider,
    required int totalDoses,
  }) {
    if (refeicoes.isEmpty) throw ArgumentError('refeicoesSelecionadas vazio');
    if (totalDoses <= 0) throw ArgumentError('totalDoses deve ser > 0');

    final result = <DateTime>[];
    final agora = DateTime.now();
    final limite = agora.add(const Duration(minutes: 1));

    int diaOffset = 0;
    while (result.length < totalDoses) {
      final diaAtual =
      DateTime(dataInicial.year, dataInicial.month, dataInicial.day).add(Duration(days: diaOffset));

      final chaveDia = _diaSemanaPTBR(diaAtual);
      final cfgDia = _obterConfigDoDia(horariosRefeicoesProvider, chaveDia);
      final horariosHHmm = _horariosDasRefeicoesNoDia(cfgDia, refeicoes);

      for (final hhmm in horariosHHmm) {
        if (result.length >= totalDoses) break;
        final dt = _parseTimeOnDate(hhmm, diaAtual);

        final isMesmoDiaDeHoje =
            dt.year == agora.year && dt.month == agora.month && dt.day == agora.day;

        if (diaOffset == 0 && isMesmoDiaDeHoje && dt.isBefore(limite)) continue;

        result.add(dt);
      }

      if (result.isEmpty && diaOffset == 0) {
        diaOffset++;
        continue;
      }
      if (result.length < totalDoses) diaOffset++;
    }
    return result;
  }

  // ------------------- Fallback Offline Helpers -------------------

  bool _isNetworkError(Object e) {
    if (e is FirebaseException) {
      return e.code == 'unavailable' ||
          e.code == 'network-request-failed' ||
          e.code == 'deadline-exceeded';
    }
    return false;
  }

  /// Executa um write com timeout curto. Retorna true se gravou online/local-cache sem travar.
  Future<bool> _tryWrite(Future<void> Function() op) async {
    try {
      await op().timeout(writeTimeout);
      return true;
    } on TimeoutException {
      return false; // assume offline/lento -> fallback
    } catch (e) {
      if (_isNetworkError(e)) return false;
      rethrow; // erros lógicos propagam
    }
  }

  /// Aplica o tratamento no estado local do provider (para UI não travar)
  void _upsertProviderTratamentoLocal({
    required String idUsuario,
    required String idTratamento,
    required Map<String, dynamic> tratamentoDoc,
  }) {
    final m = usuarioProvider.tratamentosMap[idUsuario] as Map<String, dynamic>? ?? {};
    m[idTratamento] = tratamentoDoc;
    usuarioProvider.tratamentosMap[idUsuario] = m;
    usuarioProvider.notifyListeners();
  }

  void _upsertProviderLembreteLocal({
    required String idUsuario,
    required String idLembrete,
    required Map<String, dynamic> lembreteDoc,
  }) {
    final list = usuarioProvider.lembretes;
    final idx = list.indexWhere((e) => (e['__localId'] ?? e['id'] ?? '') == idLembrete);
    if (idx >= 0) {
      list[idx] = lembreteDoc;
    } else {
      list.add(lembreteDoc);
    }
    usuarioProvider.notifyListeners();
  }

  void _upsertProviderEstoqueLocal({
    required String idMedicamento,
    required Map<String, dynamic> estoqueDoc,
  }) {
    final est = usuarioProvider.estoqueMap;
    final atual = (est[idMedicamento] as Map<String, dynamic>?) ?? {};
    atual.addAll(estoqueDoc);
    est[idMedicamento] = atual;
    usuarioProvider.notifyListeners();
  }

  // ------------------- Fluxo principal -------------------
  Future<void> criarTratamentoComLembretes() async {
    _assertTargetUid();
    final idUsuario = _targetUid;

    final plano = _calcularPlanoLembretesMap();
    final datas = (plano['datas'] as List<DateTime>);
    final freqStr = plano['freq'] as String;
    final resumo = (plano['resumo'] as List<Map<String, dynamic>>);

    // IDs (se offline, usamos IDs locais determinísticos)
    final String idTratamentoOnline = firestore
        .collection('usuarios').doc(idUsuario)
        .collection('tratamentos').doc().id;
    final String idTratamentoLocal = 'local_${DateTime.now().microsecondsSinceEpoch}';

    final idMedicamento = gerarIdMedicamento(
      nomeMedicamento, concentracaoMedicamento, tipoMedicamento,
    );

    final tratamentoBase = {
      'idMedicamento': idMedicamento,
      'nomeMedicamento': nomeMedicamento,
      'concentracaoMedicamento': concentracaoMedicamento,
      'tipoMedicamento': tipoMedicamento,
      'dosagem': qtdMedicamento,
      'frequencia': freqStr,
      'dataInicio': datas.isNotEmpty
          ? Timestamp.fromDate(datas.first)
          : Timestamp.fromDate(_parseDate(dataInicial)),
      'dataTermino': isContinuo
          ? null
          : (datas.isNotEmpty ? Timestamp.fromDate(datas.last) : null),
      'lembretes': resumo,
      'observacoes': observacoes,
      'tipoTratamento': tipoTratamento ?? '',
      'status': 'ativo',
      'tipoFrequencia': tipoFrequencia,
      'renovacaoAutomatica': isContinuo,
      'janelaDias': isContinuo ? janelaPreGeracaoDias : null,
      'scheduleVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _updatedBy(usuarioProvider.isContextoSouEu ? 'patient' : 'caregiver'),
      'pendingSync': usuarioProvider.isContextoSouEu ? false : true,
    };

    // Tenta gravar online com timeout curto
    final wroteOnline = await _tryWrite(() async {
      await firestore
          .collection('usuarios').doc(idUsuario)
          .collection('tratamentos').doc(idTratamentoOnline)
          .set(tratamentoBase);
    });

    final idTratamento = wroteOnline ? idTratamentoOnline : idTratamentoLocal;

    if (!wroteOnline) {
      // aplica no provider (para UI reagir) com flag de pendingSync
      final localDoc = Map<String, dynamic>.from(tratamentoBase)
        ..['__localId'] = idTratamento
        ..['pendingSync'] = true;
      _upsertProviderTratamentoLocal(
        idUsuario: idUsuario,
        idTratamento: idTratamento,
        tratamentoDoc: localDoc,
      );

      // também escreve no cache do Firestore para já constar no "source:cache"
      unawaited(
        firestore
            .collection('usuarios').doc(idUsuario)
            .collection('tratamentos').doc(idTratamento)
            .set(localDoc, SetOptions(merge: true)),
      );
    }

    // Lembretes + notificações (não bloquear, sem travar se offline)
    await _gravarLembretesENotificacoes(
      idUsuario: idUsuario,
      idTratamento: idTratamento,
      datasLembretes: datas,
      isOffline: !wroteOnline,
    );

    // Estoque (não bloquear UI se offline)
    await _salvarEstoque(
      firestore: firestore,
      usuarioProvider: usuarioProvider,
      idUsuario: idUsuario,
      idMedicamento: idMedicamento,
      qtdMedicamentoEstoqueCtrl: qtdMedicamentoEstoqueCtrl,
      qtdEstoqueMinimoCtrl: qtdEstoqueMinimoCtrl,
      dataValidadeCtrl: dataValidadeCtrl,
      isOffline: !wroteOnline,
    );
  }

  Future<void> atualizarTratamento({required String idTratamento}) async {
    _assertTargetUid();
    final idUsuario = _targetUid;

    final plano = _calcularPlanoLembretesMap();
    final datas = (plano['datas'] as List<DateTime>);
    final freqStr = plano['freq'] as String;
    final resumo = (plano['resumo'] as List<Map<String, dynamic>>);

    final idMedicamento = gerarIdMedicamento(
      nomeMedicamento, concentracaoMedicamento, tipoMedicamento,
    );

    final payloadTrat = <String, dynamic>{
      'idMedicamento': idMedicamento,
      'nomeMedicamento': nomeMedicamento,
      'tipoMedicamento': tipoMedicamento,
      'concentracaoMedicamento': concentracaoMedicamento,
      'dosagem': qtdMedicamento,
      'tipoTratamento': tipoTratamento,
      'frequenciaHoras': frequenciaHoras,
      'frequencia': freqStr,
      'dataInicio': datas.isNotEmpty
          ? Timestamp.fromDate(datas.first)
          : Timestamp.fromDate(_parseDate(dataInicial)),
      'dataTermino': isContinuo
          ? null
          : (datas.isNotEmpty ? Timestamp.fromDate(datas.last) : null),
      'observacoes': observacoes,
      'tipoFrequencia': tipoFrequencia,
      'status': 'ativo',
      'lembretes': resumo,
      'renovacaoAutomatica': isContinuo,
      'janelaDias': isContinuo ? janelaPreGeracaoDias : null,
      'scheduleVersion': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _updatedBy(usuarioProvider.isContextoSouEu ? 'patient' : 'caregiver'),
      'pendingSync': usuarioProvider.isContextoSouEu ? false : true,
    };

    final docTrat = firestore
        .collection('usuarios').doc(idUsuario)
        .collection('tratamentos').doc(idTratamento);

    final wroteOnline = await _tryWrite(() async {
      await docTrat.update(payloadTrat);
    });

    if (!wroteOnline) {
      final localDoc = Map<String, dynamic>.from(payloadTrat)
        ..['__localId'] = idTratamento
        ..['pendingSync'] = true;
      _upsertProviderTratamentoLocal(
        idUsuario: idUsuario,
        idTratamento: idTratamento,
        tratamentoDoc: localDoc,
      );
      unawaited(docTrat.set(localDoc, SetOptions(merge: true)));
    }

    await _gravarLembretesENotificacoes(
      idUsuario: idUsuario,
      idTratamento: idTratamento,
      datasLembretes: datas,
      isOffline: !wroteOnline,
    );

    await _salvarEstoque(
      firestore: firestore,
      usuarioProvider: usuarioProvider,
      idUsuario: idUsuario,
      idMedicamento: idMedicamento,
      qtdMedicamentoEstoqueCtrl: qtdMedicamentoEstoqueCtrl,
      qtdEstoqueMinimoCtrl: qtdEstoqueMinimoCtrl,
      dataValidadeCtrl: dataValidadeCtrl,
      isOffline: !wroteOnline,
    );
  }

  Map<String, dynamic> _calcularPlanoLembretesMap() {
    final DateTime data = _parseDate(dataInicial);
    final DateTime dataHoraInicioIntervalo = _safeStartInterval(data);

    final qtdPorDose = _parseIntSafe(qtdMedicamento, fallback: 1);
    final totalUnidades = _parseIntSafe(qtdMedicamentoTotal, fallback: 0);
    final int totalDoses = (qtdPorDose <= 0) ? 0 : (totalUnidades / qtdPorDose).floor();

    final bool isFixos = horariosFixos.isNotEmpty;
    final bool isRefeicaoSelecionada = !isFixos &&
        tipoFrequencia == 'Junto com Refeições' &&
        refeicoesSelecionadas.isNotEmpty;

    // ===== Helpers p/ ordem e formatação =====
    List<String> _ordenaHorarios(List<String> hhmm) =>
        [...hhmm]..sort((a, b) => a.compareTo(b));

    const _ordemRefeicoes = ['cafe', 'almoco', 'jantar'];
    const _labelRefeicoes = {
      'cafe': 'Café da manhã',
      'almoco': 'Almoço',
      'jantar': 'Jantar',
    };
    List<String> _ordenaRefeicoes(List<String> ids) =>
        [...ids]..sort((a, b) => _ordemRefeicoes.indexOf(a).compareTo(_ordemRefeicoes.indexOf(b)));

    String _freqIntervaloStr(int h) =>
        h == 1 ? "A cada 1 hora" : "A cada ${h} horas";

    String _freqFixosStr(List<String> hhmmOrd) =>
        "${hhmmOrd.length}x ao dia: ${hhmmOrd.join(', ')}";

    String _freqRefeicoesStr(List<String> idsOrd) =>
        "${idsOrd.length}x ao dia: ${idsOrd.map((r) => _labelRefeicoes[r] ?? r).join(', ')}";

    // =========================================

    late final List<DateTime> datasLembretes;
    late final String freqStr;
    final List<Map<String, dynamic>> resumo = [];
    if (isContinuo) {
      final DateTime endDia = DateTime(data.year, data.month, data.day)
          .add(Duration(days: janelaPreGeracaoDias - 1));
      final DateTime endIncl = _endOfDay(endDia);

      if (isFixos) {
        datasLembretes = _gerarLembretesFixosAte(
          dataInicialDate: data,
          horariosHHmm: horariosFixos,
          endIncl: endIncl,
        );

        final ord = _ordenaHorarios(horariosFixos);
        freqStr = _freqFixosStr(ord);

        for (final h in ord) {
          resumo.add({'tipo': tipoTratamento ?? '', 'valor': h, 'momento': ''});
        }
      } else if (isRefeicaoSelecionada) {
        final horariosRefeicoesProvider = usuarioProvider.horariosRefeicoes;
        datasLembretes = _gerarLembretesRefeicaoAte(
          dataInicial: data,
          refeicoes: refeicoesSelecionadas,
          horariosRefeicoesProvider: horariosRefeicoesProvider,
          endIncl: endIncl,
        );

        final ord = _ordenaRefeicoes(refeicoesSelecionadas);
        freqStr = _freqRefeicoesStr(ord);

        for (final r in ord) {
          resumo.add({'tipo': tipoTratamento ?? '', 'valor': 'refeicao', 'momento': r});
        }
      } else {
        final int freqHoras = _parseIntSafe(frequenciaHoras, fallback: 8);
        datasLembretes = _gerarLembretesIntervaloAte(
          startDateTime: dataHoraInicioIntervalo,
          freqHoras: freqHoras,
          endIncl: endIncl,
        );

        freqStr = _freqIntervaloStr(freqHoras);
        resumo.add({'tipo': tipoTratamento ?? '', 'valor': freqHoras.toString(), 'momento': ''});
      }
    } else {
      if (isFixos) {
        datasLembretes = _gerarLembretesFixos(
          dataInicialDate: data,
          horariosHHmm: horariosFixos,
          totalDoses: totalDoses,
        );

        final ord = _ordenaHorarios(horariosFixos);
        freqStr = _freqFixosStr(ord);

        for (final h in ord) {
          resumo.add({'tipo': tipoTratamento ?? '', 'valor': h, 'momento': ''});
        }
      } else if (isRefeicaoSelecionada) {
        final horariosRefeicoesProvider = usuarioProvider.horariosRefeicoes;
        datasLembretes = _gerarLembretesPorRefeicao(
          dataInicial: data,
          refeicoes: refeicoesSelecionadas,
          horariosRefeicoesProvider: horariosRefeicoesProvider,
          totalDoses: totalDoses,
        );

        final ord = _ordenaRefeicoes(refeicoesSelecionadas);
        freqStr = _freqRefeicoesStr(ord);

        for (final r in ord) {
          resumo.add({'tipo': tipoTratamento ?? '', 'valor': 'refeicao', 'momento': r});
        }
      } else {
        final int freqHoras = _parseIntSafe(frequenciaHoras, fallback: 8);
        final nowPlus1 = DateTime.now().add(const Duration(minutes: 1));
        final inicio = dataHoraInicioIntervalo.isBefore(nowPlus1) ? nowPlus1 : dataHoraInicioIntervalo;

        datasLembretes = List.generate(
          totalDoses,
              (i) => inicio.add(Duration(hours: i * freqHoras)),
        );

        // mantém coerência textual com contínuo (evita "Xx ao dia" divergente)
        freqStr = _freqIntervaloStr(freqHoras);
        resumo.add({'tipo': tipoTratamento ?? '', 'valor': freqHoras.toString(), 'momento': ''});
      }
    }


    return {
      'datas': datasLembretes,
      'freq': freqStr,
      'resumo': resumo,
      'isRefeicao': isRefeicaoSelecionada,
    };
  }

  Future<void> _gravarLembretesENotificacoes({
    required String idUsuario,
    required String idTratamento,
    required List<DateTime> datasLembretes,
    bool isOffline = false,
  }) async {
    // limpa antigos (sem travar offline)
    try {
      final antigos = await firestore
          .collection('usuarios').doc(idUsuario)
          .collection('lembretes')
          .where('idTratamento', isEqualTo: idTratamento)
          .get(const GetOptions(source: Source.serverAndCache));
      for (final d in antigos.docs) {
        try { await d.reference.delete().timeout(writeTimeout); } catch (_) {}
      }
    } catch (_) {
      // offline sem cache prévio -> ignora
    }

    for (final dt in datasLembretes) {
      final doc = firestore
          .collection('usuarios').doc(idUsuario)
          .collection('lembretes').doc();

      final idNotif = doc.id.hashCode.abs();

      final String? momentoInferido = (tipoFrequencia == 'Junto com Refeições' &&
          refeicoesSelecionadas.isNotEmpty)
          ? _inferirMomentoRefeicao(dt, usuarioProvider.horariosRefeicoes)
          : null;

      final lembrete = {
        'idTratamento': idTratamento,
        'dataHoraAgendado': Timestamp.fromDate(dt),
        'dataHoraTomado': null,
        'tomado': false,
        'adiado': false,
        'cancelado': false,
        'notificado': false,
        'idNovoLembrete': '',
        'refeicao': momentoInferido,
        'momento': null,
        'idNotificacao': idNotif,
        'tipoTratamento': tipoTratamento,
        'tipoFrequencia': tipoFrequencia,
        'scheduleVersion': 1,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _updatedBy(usuarioProvider.isContextoSouEu ? 'patient' : 'caregiver'),
        'pendingSync': usuarioProvider.isContextoSouEu ? false : true,
        'status': 'ativo',
      };

      final wroteOnline = await _tryWrite(() async {
        await doc.set(lembrete);
      });

      if (!wroteOnline) {
        final localId = 'local_${doc.id}';
        final local = Map<String, dynamic>.from(lembrete)
          ..['__localId'] = localId
          ..['pendingSync'] = true;
        _upsertProviderLembreteLocal(
          idUsuario: idUsuario,
          idLembrete: localId,
          lembreteDoc: local,
        );
        unawaited(doc.set(local, SetOptions(merge: true)));
      }

      if (usuarioProvider.isContextoSouEu) {
        await NotificationService().scheduleNotification(
          id: idNotif,
          title: 'Hora do medicamento',
          body:
          '${nomeMedicamento} ${concentracaoMedicamento} ($qtdMedicamento $tipoMedicamento)',
          scheduledDateTime: dt,
          idLembrete: doc.id,
          idUsuario: idUsuario,
        );
      }
    }
  }

  Future<void> _salvarEstoque({
    required FirebaseFirestore firestore,
    required UsuarioProvider usuarioProvider,
    required String idUsuario,
    required String idMedicamento,
    required String qtdMedicamentoEstoqueCtrl,
    required String qtdEstoqueMinimoCtrl,
    required String dataValidadeCtrl,
    bool isOffline = false,
  }) async {
    final String sQtdAtual = qtdMedicamentoEstoqueCtrl.trim();
    final String sQtdMin = qtdEstoqueMinimoCtrl.trim();
    final String sValidade = dataValidadeCtrl.trim();

    if (sQtdAtual.isEmpty) return;

    final Map<String, dynamic> novoEstoque = {
      'qtdAtual': int.tryParse(sQtdAtual) ?? 0,
    };

    final int? qtdMinimaParsed = sQtdMin.isNotEmpty ? int.tryParse(sQtdMin) : null;
    if (qtdMinimaParsed != null) {
      novoEstoque['qtdMinima'] = qtdMinimaParsed;
    }

    if (sValidade.isNotEmpty) {
      try {
        final dt = DateFormat('dd/MM/yyyy').parseStrict(sValidade);
        novoEstoque['dataValidade'] = dt;
      } catch (_) {}
    }

    final estoqueRef = firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('estoque')
        .doc(idMedicamento);

    final wroteOnline = await _tryWrite(() async {
      await estoqueRef.set(novoEstoque, SetOptions(merge: true));
    });

    if (!wroteOnline) {
      // Aplica no provider e tenta cache
      _upsertProviderEstoqueLocal(idMedicamento: idMedicamento, estoqueDoc: novoEstoque);
      unawaited(estoqueRef.set(novoEstoque, SetOptions(merge: true)));
    }
  }

  String gerarIdMedicamento(String nome, String conc, String tipo) {
    final normalized = [nome, conc, tipo]
        .map((s) => removeDiacritics(s).toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' '))
        .join('|');
    return normalized.toString();
  }
}
