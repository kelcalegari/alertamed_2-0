import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:diacritic/diacritic.dart';
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
  final String? idCuidador;
  final String observacoes;
  final String? tipoTratamento;
  final List<String> horariosFixos;         // se não vazio => modo fixo
  final String qtdMedicamentoEstoqueCtrl;
  final String qtdEstoqueMinimoCtrl;
  final String dataValidadeCtrl;            // dd/MM/yyyy
  final String unidadeMedida;
  final String tipoFrequencia;
  final UsuarioProvider usuarioProvider;
  final bool isContinuo;
  final int janelaPreGeracaoDias;
  /// Para "Junto com Refeições": ['cafe','almoco','jantar']
  final List<String> refeicoesSelecionadas;

  SalvarTratamento({
    required this.nomeMedicamento,
    required this.tipoMedicamento,
    required this.concentracaoMedicamento,
    required this.qtdMedicamento,
    required this.qtdMedicamentoTotal,
    required this.frequenciaHoras,
    required this.dataInicial,
    required this.horaInicial,
    this.idCuidador,
    required this.observacoes,
    required this.tipoTratamento,
    required this.qtdMedicamentoEstoqueCtrl,
    required this.qtdEstoqueMinimoCtrl,
    required this.dataValidadeCtrl,
    required this.usuarioProvider,
    required this.unidadeMedida,
    required this.horariosFixos,
    required this.tipoFrequencia,
    required this.refeicoesSelecionadas,
    required this.isContinuo,
    this.janelaPreGeracaoDias = 15,
  });

  // ------------------- Utils & Helpers -------------------

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
      return DateTime(baseDate.year, baseDate.month, baseDate.day, 8, 0); // fallback 08:00
    }
  }

  /// Normaliza rótulos de dias para chaves canônicas
  /// ex.: "Seg", "segunda", "SEGUNDA" -> "segunda"; "Padrão" -> "padrao"
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
        return d; // deixa como veio
    }
  }

  /// Retorna a chave canônica do dia da semana para uma data.
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

  /// A partir do provider.horariosRefeicoes (array de maps), retorna
  /// o map do dia atual; se não houver, usa 'padrao'; se ainda assim
  /// não houver, retorna null.
  Map<String, dynamic>? _obterConfigDoDia(
      List<dynamic>? horariosRefeicoes,
      String chaveDia,
      ) {
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

  /// Dado um config de dia e a lista de refeições marcadas,
  /// devolve horários HH:mm válidos (ordenados, sem duplicatas).
  List<String> _horariosDasRefeicoesNoDia(
      Map<String, dynamic>? cfgDia,
      List<String> refeicoes,
      ) {
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

    // Fallbacks se cfgDia for nulo (nada cadastrado)
    if (out.isEmpty) {
      final defaults = {
        'cafe': '07:30',
        'almoco': '12:00',
        'jantar': '19:00',
      };
      for (final r in refeicoes) {
        final hhmm = defaults[r];
        if (hhmm != null) out.add(hhmm);
      }
    }

    // normaliza -> Duration -> ordena -> volta para HH:mm e remove duplicatas
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

  /// Gera lembretes por REFEIÇÃO até uma data-limite (janela).
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

        // se for hoje, respeitar +10 min
        final mesmoDiaHoje = dt.year == agora.year && dt.month == agora.month && dt.day == agora.day;
        if (mesmoDiaHoje && dt.isBefore(limitePrimeiroDia)) continue;

        if (dt.isAfter(endIncl)) return result;
        result.add(dt);
      }

      dia = dia.add(const Duration(days: 1));
    }
    return result;
  }

  /// Gera lembretes de HORÁRIOS FIXOS até uma data-limite.
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

        // se for hoje, respeitar +10 min
        final mesmoDiaHoje = dt.year == agora.year && dt.month == agora.month && dt.day == agora.day;
        if (mesmoDiaHoje && dt.isBefore(limitePrimeiroDia)) continue;

        if (dt.isAfter(endIncl)) return result;
        result.add(dt);
      }
      dia = dia.add(const Duration(days: 1));
    }
    return result;
  }

  /// Gera lembretes por INTERVALO fixo até uma data-limite.
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

  /// Gera a lista de DateTimes (lembretes) em modo Horários Fixos com TOTAL de doses.
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
    final limite = agora.add(const Duration(minutes: 10));

    final baseDia0 = DateTime(dataInicialDate.year, dataInicialDate.month, dataInicialDate.day);
    final isDia0Hoje = baseDia0.year == agora.year &&
        baseDia0.month == agora.month &&
        baseDia0.day == agora.day;

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
      if (result.length < totalDoses) {
        diaOffset++;
      }
    }

    return result;
  }

  /// Gera lembretes por REFEIÇÃO com TOTAL de doses.
  List<DateTime> _gerarLembretesPorRefeicao({
    required DateTime dataInicial,
    required List<String> refeicoes,
    required List<dynamic>? horariosRefeicoesProvider, // array de maps
    required int totalDoses,
  }) {
    if (refeicoes.isEmpty) {
      throw ArgumentError('refeicoesSelecionadas vazio');
    }
    if (totalDoses <= 0) {
      throw ArgumentError('totalDoses deve ser > 0');
    }

    final result = <DateTime>[];
    final agora = DateTime.now();
    final limite = agora.add(const Duration(minutes: 10));

    int diaOffset = 0;
    while (result.length < totalDoses) {
      final diaAtual = DateTime(dataInicial.year, dataInicial.month, dataInicial.day)
          .add(Duration(days: diaOffset));

      final chaveDia = _diaSemanaPTBR(diaAtual);
      final cfgDia = _obterConfigDoDia(horariosRefeicoesProvider, chaveDia);
      final horariosHHmm = _horariosDasRefeicoesNoDia(cfgDia, refeicoes);

      for (final hhmm in horariosHHmm) {
        if (result.length >= totalDoses) break;
        final dt = _parseTimeOnDate(hhmm, diaAtual);

        // Regra do primeiro dia: precisa ser >= (agora + 10min)
        final isMesmoDiaDeHoje = dt.year == agora.year &&
            dt.month == agora.month &&
            dt.day == agora.day;

        if (diaOffset == 0 && isMesmoDiaDeHoje && dt.isBefore(limite)) {
          continue;
        }

        result.add(dt);
      }

      if (result.isEmpty && diaOffset == 0) {
        diaOffset++;
        continue;
      }

      if (result.length < totalDoses) {
        diaOffset++;
      }
    }

    return result;
  }

  // ------------------- Fluxo principal -------------------
  Future<void> criarTratamentoComLembretes() async {
    final idUsuario = usuarioProvider.userId;

    // 1) Calcula o plano pelo Map
    final plano = _calcularPlanoLembretesMap();
    final datas = (plano['datas'] as List<DateTime>);
    final freqStr = plano['freq'] as String;
    final resumo = (plano['resumo'] as List<Map<String, dynamic>>);

    // 2) Gera id do tratamento
    final String idTratamento = firestore
        .collection('usuarios').doc(idUsuario)
        .collection('tratamentos').doc().id;

    // 3) Documento do tratamento
    final idMedicamento = gerarIdMedicamento(
      nomeMedicamento, concentracaoMedicamento, tipoMedicamento,
    );

    final tratamentoDoc = {
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
      'idCuidador': idCuidador ?? '',
      'observacoes': observacoes,
      'tipoTratamento': tipoTratamento ?? '',
      'unidadeMedida': unidadeMedida,
      'status': 'ativo',
      'tipoFrequencia': tipoFrequencia,
      'renovacaoAutomatica': isContinuo,
      'janelaDias': isContinuo ? janelaPreGeracaoDias : null,
    };

    await firestore
        .collection('usuarios').doc(idUsuario)
        .collection('tratamentos').doc(idTratamento)
        .set(tratamentoDoc);

    // 4) Lembretes + notificações
    await _gravarLembretesENotificacoes(
      idUsuario: idUsuario,
      idTratamento: idTratamento,
      datasLembretes: datas,
    );

    // 5) Estoque
    final idMed = idMedicamento;
    await _salvarEstoque(
      firestore: firestore,
      usuarioProvider: usuarioProvider,
      idUsuario: idUsuario,
      idMedicamento: idMed,
      qtdMedicamentoEstoqueCtrl: qtdMedicamentoEstoqueCtrl,
      qtdEstoqueMinimoCtrl: qtdEstoqueMinimoCtrl,
      dataValidadeCtrl: dataValidadeCtrl,
    );
  }

  // ===========================================================
// Função auxiliar para salvar estoque
// ===========================================================
  Future<void> _salvarEstoque({
    required FirebaseFirestore firestore,
    required UsuarioProvider usuarioProvider,
    required String idUsuario,
    required String idMedicamento,
    required String qtdMedicamentoEstoqueCtrl,
    required String qtdEstoqueMinimoCtrl,
    required String dataValidadeCtrl,
  }) async {
    final String sQtdAtual = qtdMedicamentoEstoqueCtrl.trim();
    final String sQtdMin = qtdEstoqueMinimoCtrl.trim();
    final String sValidade = dataValidadeCtrl.trim();

    // Regra 1: se qtdAtual não foi informada, NÃO cria/atualiza estoque
    if (sQtdAtual.isEmpty) return;

    // Monta o mapa somente com campos válidos
    final Map<String, dynamic> novoEstoque = {
      'qtdAtual': int.tryParse(sQtdAtual) ?? 0,
    };

    // Adiciona qtdMinima se veio preenchida
    final int? qtdMinimaParsed =
    sQtdMin.isNotEmpty ? int.tryParse(sQtdMin) : null;
    if (qtdMinimaParsed != null) {
      novoEstoque['qtdMinima'] = qtdMinimaParsed;
    }

    // Adiciona dataValidade se veio preenchida e válida
    if (sValidade.isNotEmpty) {
      try {
        final dt = DateFormat('dd/MM/yyyy').parseStrict(sValidade);
        novoEstoque['dataValidade'] = dt;
      } catch (_) {
        // inválida → ignora
      }
    }

    final estoqueMap = usuarioProvider.estoqueMap;
    final estoqueRef = firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('estoque')
        .doc(idMedicamento);

    if (estoqueMap.containsKey(idMedicamento)) {
      await estoqueRef.update(novoEstoque);

      // mescla no cache
      final atual = Map<String, dynamic>.from(
        estoqueMap[idMedicamento] as Map,
      );
      atual.addAll(novoEstoque);
      estoqueMap[idMedicamento] = atual;
    } else {
      await estoqueRef.set(novoEstoque);
      estoqueMap[idMedicamento] = novoEstoque;
    }
  }
  String gerarIdMedicamento(String nome, String conc, String tipo) {
    final normalized = [nome, conc, tipo]
        .map((s) => removeDiacritics(s)
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' '))
        .join('|');

    return normalized.toString();
  }


  Future<void> atualizarTratamento({required String idTratamento}) async {
    final idUsuario = usuarioProvider.userId;
    final docTrat = firestore
        .collection('usuarios').doc(idUsuario)
        .collection('tratamentos').doc(idTratamento);

    // 1) Recalcula plano com base nos novos inputs
    final plano = _calcularPlanoLembretesMap();
    final datas = (plano['datas'] as List<DateTime>);
    final freqStr = plano['freq'] as String;
    final resumo = (plano['resumo'] as List<Map<String, dynamic>>);

    // 2) Monta payload
    final idMedicamento = gerarIdMedicamento(
      nomeMedicamento, concentracaoMedicamento, tipoMedicamento,
    );

    final payloadTrat = <String, dynamic>{
      'idMedicamento': idMedicamento,
      'nomeMedicamento': nomeMedicamento,
      'tipoMedicamento': tipoMedicamento,
      'concentracaoMedicamento': concentracaoMedicamento,
      'dosagem': qtdMedicamento,
      'qtdMedicamento': qtdMedicamento,
      'qtdMedicamentoTotal': qtdMedicamentoTotal,
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
      'status': 'ativo', // preserve se quiser: leia o doc atual e reaplique
      'unidadeMedida': unidadeMedida,
      'lembretes': resumo,
      'renovacaoAutomatica': isContinuo,
      'janelaDias': isContinuo ? janelaPreGeracaoDias : null,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // 3) Atualiza tratamento
    await docTrat.update(payloadTrat);

    // 4) Regrava lembretes e notificações
    await _gravarLembretesENotificacoes(
      idUsuario: idUsuario,
      idTratamento: idTratamento,
      datasLembretes: datas,
    );

    // 5) Estoque (se informado)
    await _salvarEstoque(
      firestore: firestore,
      usuarioProvider: usuarioProvider,
      idUsuario: idUsuario,
      idMedicamento: idMedicamento,
      qtdMedicamentoEstoqueCtrl: qtdMedicamentoEstoqueCtrl,
      qtdEstoqueMinimoCtrl: qtdEstoqueMinimoCtrl,
      dataValidadeCtrl: dataValidadeCtrl,
    );
  }

  Map<String, dynamic> _calcularPlanoLembretesMap() {
    // Base
    final DateTime data = _parseDate(dataInicial);
    final DateTime dataHoraInicioIntervalo = _safeStartInterval(data);

    // total de doses (modo não-contínuo)
    final qtdPorDose = _parseIntSafe(qtdMedicamento, fallback: 1);
    final totalUnidades = _parseIntSafe(qtdMedicamentoTotal, fallback: 0);
    final int totalDoses = (qtdPorDose <= 0) ? 0 : (totalUnidades / qtdPorDose).floor();

    final bool isFixos = horariosFixos.isNotEmpty;
    final bool isRefeicaoSelecionada = !isFixos &&
        tipoFrequencia == 'Junto com Refeições' &&
        refeicoesSelecionadas.isNotEmpty;

    late final List<DateTime> datasLembretes;
    late final String freqStr;
    final List<Map<String, dynamic>> resumo = [];

    if (isContinuo) {
      // Janela de pré-geração
      final DateTime endDia  = DateTime(data.year, data.month, data.day)
          .add(Duration(days: janelaPreGeracaoDias - 1));
      final DateTime endIncl = _endOfDay(endDia);

      if (isFixos) {
        datasLembretes = _gerarLembretesFixosAte(
          dataInicialDate: data,
          horariosHHmm: horariosFixos,
          endIncl: endIncl,
        );
        final dosesPorDia = horariosFixos.length;
        freqStr = "${dosesPorDia}x ao dia";
        for (final h in horariosFixos) {
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
        freqStr = "${refeicoesSelecionadas.length}x ao dia";
        for (final r in refeicoesSelecionadas) {
          resumo.add({'tipo': tipoTratamento ?? '', 'valor': 'refeicao', 'momento': r});
        }
      } else {
        final int freqHoras = _parseIntSafe(frequenciaHoras, fallback: 8);
        datasLembretes = _gerarLembretesIntervaloAte(
          startDateTime: dataHoraInicioIntervalo,
          freqHoras: freqHoras,
          endIncl: endIncl,
        );
        final porDia = (24 / (freqHoras <= 0 ? 24 : freqHoras)).round();
        freqStr = "${porDia}x ao dia";
        resumo.add({'tipo': tipoTratamento ?? '', 'valor': frequenciaHoras, 'momento': ''});
      }
    } else {
      // Determinado / Dose única (usa TOTAL de doses)
      if (isFixos) {
        datasLembretes = _gerarLembretesFixos(
          dataInicialDate: data,
          horariosHHmm: horariosFixos,
          totalDoses: totalDoses,
        );
        final dosesPorDia = horariosFixos.length;
        freqStr = "${dosesPorDia}x ao dia";
        for (final h in horariosFixos) {
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
        freqStr = "${refeicoesSelecionadas.length}x ao dia (refeições)";
        for (final r in refeicoesSelecionadas) {
          resumo.add({'tipo': tipoTratamento ?? '', 'valor': 'refeicao', 'momento': r});
        }
      } else {
        final int freqHoras = _parseIntSafe(frequenciaHoras, fallback: 8);
        final nowPlus10 = DateTime.now().add(const Duration(minutes: 10));
        final inicio = dataHoraInicioIntervalo.isBefore(nowPlus10) ? nowPlus10 : dataHoraInicioIntervalo;

        datasLembretes = List.generate(
          totalDoses,
              (i) => inicio.add(Duration(hours: i * freqHoras)),
        );
        final porDia = (24 / (freqHoras <= 0 ? 24 : freqHoras)).round();
        freqStr = "${porDia}x ao dia";
        resumo.add({'tipo': tipoTratamento ?? '', 'valor': frequenciaHoras, 'momento': ''});
      }
    }

    return {
      'datas': datasLembretes,                       // List<DateTime>
      'freq': freqStr,                               // String
      'resumo': resumo,                              // List<Map<String,dynamic>>
      'isRefeicao': isRefeicaoSelecionada,           // bool
    };
  }
  Future<void> _gravarLembretesENotificacoes({
    required String idUsuario,
    required String idTratamento,
    required List<DateTime> datasLembretes,
  }) async {
    final notificationService = NotificationService();

    // limpa antigos (útil na edição)
    final antigos = await firestore
        .collection('usuarios').doc(idUsuario)
        .collection('lembretes')
        .where('idTratamento', isEqualTo: idTratamento)
        .get();

    for (final d in antigos.docs) {
      try { await d.reference.delete(); } catch (_) {}
    }

    // cria novos + notifica
    final List<Future<void>> pend = [];
    for (final dataLembrete in datasLembretes) {
      final String idLembrete = firestore
          .collection('usuarios').doc(idUsuario)
          .collection('lembretes').doc().id;

      final int idNotificacao = idLembrete.hashCode.abs();

      final lembreteDoc = {
        'idTratamento': idTratamento,
        'idNotificacao': idNotificacao,
        'dataHoraAgendado': Timestamp.fromDate(dataLembrete),
        'dataHoraTomado': null,
        'tomado': false,
        'adiado': false,
        'notificado': false,
        'idNovoLembrete': '',
        'tipoTratamento': tipoTratamento ?? '',
        'tipoFrequencia': tipoFrequencia,
        'refeicao': '', // se quiser preencher café/almoco/jantar, dá pra inferir aqui
        'momento': '',
        'cancelado': false,
      };

      pend.add(
        firestore
            .collection('usuarios').doc(idUsuario)
            .collection('lembretes').doc(idLembrete)
            .set(lembreteDoc),
      );

      pend.add(
        notificationService.scheduleNotification(
          id: idNotificacao,
          title: 'Hora do medicamento',
          body: '$nomeMedicamento $concentracaoMedicamento '
              '(${qtdMedicamento} $unidadeMedida)',
          scheduledDateTime: dataLembrete,
          idLembrete: idLembrete,
          idUsuario: idUsuario,
        ),
      );
    }

    await Future.wait(pend);
  }

}
