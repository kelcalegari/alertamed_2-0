import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
  });

  // ------------------- Utils & Helpers -------------------

  int _parseIntSafe(String s, {int fallback = 0}) {
    final v = int.tryParse(s.trim());
    return v == null ? fallback : v;
  }

  DateTime _parseDate(String ddMMyyyy) =>
      DateFormat("dd/MM/yyyy").parse(ddMMyyyy);

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

  /// Normaliza rótulos de dias para chaves canônicas
  /// ex.: "Seg", "segunda", "SEGUNDA" -> "segunda"; "Padrão" -> "padrao"
  String _normDia(String dia) {
    final d = dia.trim().toLowerCase();
    switch (d) {
      case 'seg': case 'segunda': return 'segunda';
      case 'ter': case 'terça': case 'terca': return 'terça';
      case 'qua': case 'quarta': return 'quarta';
      case 'qui': case 'quinta': return 'quinta';
      case 'sex': case 'sexta': return 'sexta';
      case 'sab': case 'sábado': case 'sabado': return 'sábado';
      case 'dom': case 'domingo': return 'domingo';
      case 'padrao': case 'padrão': return 'padrao';
      default: return d; // deixa como veio
    }
  }

  /// Retorna a chave canônica do dia da semana para uma data.
  String _diaSemanaPTBR(DateTime dt) {
    switch (dt.weekday) {
      case DateTime.monday: return 'segunda';
      case DateTime.tuesday: return 'terça';
      case DateTime.wednesday: return 'quarta';
      case DateTime.thursday: return 'quinta';
      case DateTime.friday: return 'sexta';
      case DateTime.saturday: return 'sábado';
      case DateTime.sunday: return 'domingo';
      default: return 'padrao';
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

  /// Gera lembretes contínuos por dias, usando horários definidos por refeição.
  /// Respeita (agora + 10min) no primeiro dia.
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
      final diaAtual = DateTime(
        dataInicial.year, dataInicial.month, dataInicial.day,
      ).add(Duration(days: diaOffset));

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

      // Se no dia 0 nenhum horário serviu, vai para o dia seguinte
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

  /// Gera a lista de DateTimes (lembretes) em modo Horários Fixos.
  List<DateTime> _gerarLembretesFixos({
    required DateTime dataInicialDate,
    required List<String> horariosHHmm,
    required int totalDoses,
  }) {
    if (horariosHHmm.isEmpty) {
      throw ArgumentError('horariosFixos vazio');
    }
    if (totalDoses <= 0) {
      throw ArgumentError('totalDoses deve ser > 0');
    }

    final horas = horariosHHmm
        .map(_parseHHmm)
        .whereType<Duration>()
        .toList()
      ..sort((a, b) => a.inMinutes.compareTo(b.inMinutes));

    if (horas.isEmpty) {
      throw ArgumentError('Nenhum horário válido em horariosFixos');
    }

    final agora = DateTime.now();
    final limite = agora.add(const Duration(minutes: 10));

    final baseDia0 = DateTime(
      dataInicialDate.year, dataInicialDate.month, dataInicialDate.day,
    );
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

  // ------------------- Fluxo principal -------------------
  Future<void> criarTratamentoComLembretes() async {
    final notificationService = NotificationService();
    final idUsuario = usuarioProvider.userId;

    // Parse data/hora base
    final DateTime data = _parseDate(dataInicial);
    final DateTime hora = DateFormat("HH:mm").parse(horaInicial);
    final DateTime dataHoraInicio = DateTime(
      data.year, data.month, data.day, hora.hour, hora.minute,
    );

    // Cálculo robusto de total de doses
    final qtdPorDose = _parseIntSafe(qtdMedicamento, fallback: 1);
    final totalUnidades = _parseIntSafe(qtdMedicamentoTotal, fallback: 0);
    final int totalDoses = (totalUnidades / (qtdPorDose <= 0 ? 1 : qtdPorDose)).floor();

    final String idTratamento = firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('tratamentos')
        .doc()
        .id;

    final bool isFixos = horariosFixos.isNotEmpty;
    final bool isRefeicao = !isFixos &&
        tipoFrequencia == 'Junto com Refeições' &&
        refeicoesSelecionadas.isNotEmpty;

    // 1) Monta a grade de lembretes
    late final List<DateTime> datasLembretes;
    late final String frequenciaString;

    if (isFixos) {
      datasLembretes = _gerarLembretesFixos(
        dataInicialDate: data,
        horariosHHmm: horariosFixos,
        totalDoses: totalDoses,
      );
      final dosesPorDia = horariosFixos.length;
      frequenciaString = "${dosesPorDia}x ao dia";
    } else if (isRefeicao) {
      final horariosRefeicoesProvider = usuarioProvider.horariosRefeicoes; // array de objetos
      datasLembretes = _gerarLembretesPorRefeicao(
        dataInicial: data,
        refeicoes: refeicoesSelecionadas,
        horariosRefeicoesProvider: horariosRefeicoesProvider,
        totalDoses: totalDoses,
      );
      frequenciaString = "${refeicoesSelecionadas.length}x ao dia (refeições)";
    } else {
      // Intervalo em horas
      final int freqHoras = _parseIntSafe(frequenciaHoras, fallback: 8);
      final nowPlus10 = DateTime.now().add(const Duration(minutes: 10));
      final inicio = dataHoraInicio.isBefore(nowPlus10) ? nowPlus10 : dataHoraInicio;

      datasLembretes = List.generate(
        totalDoses,
            (i) => inicio.add(Duration(hours: i * freqHoras)),
      );
      frequenciaString = "${(24 / freqHoras).round()}x ao dia";
    }

    // 2) Escreve lembretes e agenda notificações
    final List<Map<String, dynamic>> lembretesArrayTratamento = [];
    final List<Future<void>> tarefasLembretes = [];

    for (final dataLembrete in datasLembretes) {
      final String idLembrete = firestore
          .collection('usuarios')
          .doc(idUsuario)
          .collection('lembretes')
          .doc()
          .id;
      final int idNotificacao = idLembrete.hashCode.abs();

      // se for refeição, tentar inferir qual momento foi usado neste dia
      String momento = '';
      if (isRefeicao) {
        final chaveDia = _diaSemanaPTBR(dataLembrete);
        final cfgDia = _obterConfigDoDia(usuarioProvider.horariosRefeicoes, chaveDia);
        final mapaMomento = <String, String>{
          'cafe':   (cfgDia?['horaCafe']   ?? '').toString(),
          'almoco': (cfgDia?['horaAlmoco'] ?? '').toString(),
          'jantar': (cfgDia?['horaJanta']  ?? '').toString(),
        };
        // encontra qual refeição bate com o horário HH:mm
        final hh = dataLembrete.hour.toString().padLeft(2, '0');
        final mm = dataLembrete.minute.toString().padLeft(2, '0');
        final hhmm = '$hh:$mm';
        for (final r in refeicoesSelecionadas) {
          if (mapaMomento[r]?.trim() == hhmm) {
            momento = r; // 'cafe' | 'almoco' | 'jantar'
            break;
          }
        }
      }

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
        'refeicao': momento,  // se refeição, guarda o momento
        'momento': '',        // (pode ser usado no futuro para outras semânticas)
        'cancelado': false,
      };

      tarefasLembretes.add(
        firestore
            .collection('usuarios')
            .doc(idUsuario)
            .collection('lembretes')
            .doc(idLembrete)
            .set(lembreteDoc),
      );

      tarefasLembretes.add(
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

    // metadado resumido para o tratamento (como você já usava)
    if (isFixos) {
      for (final h in horariosFixos) {
        lembretesArrayTratamento.add({
          'tipo': tipoTratamento ?? '',
          'valor': h,        // "HH:mm"
          'momento': '',
        });
      }
    } else if (isRefeicao) {
      for (final r in refeicoesSelecionadas) {
        lembretesArrayTratamento.add({
          'tipo': tipoTratamento ?? '',
          'valor': 'refeicao', // marcador genérico
          'momento': r,        // 'cafe' | 'almoco' | 'jantar'
        });
      }
    } else {
      lembretesArrayTratamento.add({
        'tipo': tipoTratamento ?? '',
        'valor': frequenciaHoras,
        'momento': '',
      });
    }

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
      'frequencia': frequenciaString,
      'dataInicio': Timestamp.fromDate(datasLembretes.first),
      'dataTermino': Timestamp.fromDate(datasLembretes.last),
      'lembretes': lembretesArrayTratamento,
      'idCuidador': idCuidador ?? '',
      'observacoes': observacoes,
      'unidadeMedida': unidadeMedida,
      'status': 'ativo',
      'tipoFrequencia': tipoFrequencia,
    };

    await firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('tratamentos')
        .doc(idTratamento)
        .set(tratamentoDoc);

    await Future.wait(tarefasLembretes);

    // 4) Estoque
    final novoEstoque = {
      'qtdAtual': _parseIntSafe(qtdMedicamentoEstoqueCtrl),
      'qtdMinima': _parseIntSafe(qtdEstoqueMinimoCtrl, fallback: 0),
      'dataValidade': DateFormat('dd/MM/yyyy').parse(dataValidadeCtrl),
    };

    final estoqueMap = usuarioProvider.estoqueMap;
    final estoqueRef = firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('estoque')
        .doc(idMedicamento);

    if (estoqueMap.containsKey(idMedicamento)) {
      await estoqueRef.update(novoEstoque);
      estoqueMap[idMedicamento] = novoEstoque;
    } else {
      await estoqueRef.set(novoEstoque);
      estoqueMap[idMedicamento] = novoEstoque;
    }
  }

  String gerarIdMedicamento(String nome, String conc, String tipo) {
    return '${nome.trim()}|${conc.trim()}|${tipo.trim()}'
        .toLowerCase()
        .hashCode
        .toString();
  }
}
