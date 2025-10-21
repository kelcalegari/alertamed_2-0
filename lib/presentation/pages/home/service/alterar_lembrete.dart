import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/notification_service.dart';
import '../../../../providers/user_data_provider.dart';

/// Serviço para gestão de lembretes de tratamentos.
/// Pontos de atenção da refatoração:
/// - Helpers reutilizáveis (_commitInChunks, _refreshCaches, _safeCancelNotif, _safeScheduleNotif, _markMeta)
/// - Padronização de metadados (scheduleVersion/updatedAt/updatedBy/pendingSync)
/// - Redução de repetição em consultas/loops
/// - Regras claras para reagendamentos por refeições e extensões automáticas
class LembreteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --------------------------- Constantes ---------------------------
  static const _kColUsuarios = 'usuarios';
  static const _kColLembretes = 'lembretes';
  static const _kColTratamentos = 'tratamentos';
  static const _kColEstoque = 'estoque';
  static const _kScheduleVersion = 1;
  static const _kBatchMaxOps = 500; // limite Firestore

  // --------------------------- Utils de contexto ---------------------------
  bool _isSelf(BuildContext context) =>
      Provider.of<UsuarioProvider>(context, listen: false).isContextoSouEu;

  Map<String, dynamic> _updatedBy(String role, String userId) => {
    'uid': userId,
    'role': role, // 'paciente' | 'cuidador'
  };

  // --------------------------- Utils de data/hora ---------------------------
  static const List<String> _diasPT = [
    'Dom',
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
  ];

  String _weekdayKeyPTBR(DateTime dt) => _diasPT[dt.weekday % 7];

  DateTime? _composeDateTime(DateTime dia, String? hhmm) {
    if (hhmm == null || hhmm.trim().isEmpty) return null;
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return DateTime(dia.year, dia.month, dia.day, h, m);
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // --------------------------- Utils de refeições ---------------------------
  String? _horaRefeicaoParaDia(
      UsuarioProvider provider,
      DateTime dia,
      String refeicao, // cafe | almoco | jantar
      ) {
    final cfg = provider.horarioRefeicaoParaDia(_weekdayKeyPTBR(dia));
    switch (refeicao) {
      case 'cafe':
        return (cfg['horaCafe'] ?? '').toString();
      case 'almoco':
        return (cfg['horaAlmoco'] ?? '').toString();
      case 'jantar':
        return (cfg['horaJanta'] ?? '').toString();
      default:
        return null;
    }
  }

  // --------------------------- Utils de notificação ---------------------------
  Future<void> _safeCancelNotif(NotificationService notif, int id) async {
    try {
      await notif.cancelNotification(id);
    } catch (_) {}
  }

  Future<void> _safeScheduleNotif(
      NotificationService notif, {
        required int id,
        required String title,
        required String body,
        required DateTime when,
        required String idLembrete,
        required String idUsuario,
      }) async {
    try {
      await notif.scheduleNotification(
        id: id,
        title: title,
        body: body,
        scheduledDateTime: when,
        idLembrete: idLembrete,
        idUsuario: idUsuario,
      );
    } catch (_) {}
  }

  String _notifBodyFromTratamento(Map<String, dynamic> t) {
    final nome = (t['nomeMedicamento'] ?? '').toString();
    final conc = (t['concentracaoMedicamento'] ?? '').toString();
    final dose = (t['dosagem'] ?? '').toString();
    final tm = (t['tipoMedicamento'] ?? '').toString();
    if (nome.isNotEmpty && conc.isNotEmpty && dose.isNotEmpty && tm.isNotEmpty) {
      return '$nome $conc ($dose $tm)';
    }
    return 'Lembrete de medicamento';
  }

  // --------------------------- Utils Firestore ---------------------------
  Future<void> _commitInChunks<T>(
      List<T> items, {
        required void Function(WriteBatch batch, T item) op,
      }) async {
    for (var i = 0; i < items.length; i += _kBatchMaxOps) {
      final slice = items.sublist(i, (i + _kBatchMaxOps).clamp(0, items.length));
      final batch = _firestore.batch();
      for (final item in slice) {
        op(batch, item);
      }
      await batch.commit();
    }
  }

  Map<String, dynamic> _markMeta({
    required bool isSelf,
    required String userId,
  }) {
    return {
      'scheduleVersion': _kScheduleVersion,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _updatedBy(isSelf ? 'paciente' : 'cuidador', userId),
      'pendingSync': isSelf ? false : true,
    };
  }



  // --------------------------- API: reagendar por refeições ---------------------------
  /// Reagende lembretes do tipo "Junto com Refeições" após alterar os `horariosRefeicoes` do usuário.
  Future<void> reagendarLembretesPorRefeicaoViaLembretes({
    required BuildContext context,
    required String idUsuario,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final agora = DateTime.now();
    final limiteHoje = agora.add(const Duration(minutes: 10));
    final notif = NotificationService();

    final snap = await _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColLembretes)
        .where('cancelado', isEqualTo: false)
        .where('adiado', isEqualTo: false)
        .where('tipoFrequencia', isEqualTo: 'Junto com Refeições')
        .get();

    final batch = _firestore.batch();
    final toCancel = <int>[];
    final toResched = <Map<String, dynamic>>[];

    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['dataHoraAgendado'] as Timestamp?;
      if (ts == null) continue;

      final agendado = ts.toDate();
      if (agendado.isBefore(agora)) continue; // só futuros

      final refeicao = (data['refeicao'] ?? '').toString();
      if (refeicao.isEmpty) continue;

      final hhmm = _horaRefeicaoParaDia(provider, agendado, refeicao);
      final novoDt = _composeDateTime(agendado, hhmm);

      // Se não há horário para essa refeição -> cancela/deleta
      if (novoDt == null) {
        final int? idNotif = data['idNotificacao'] as int?;
        if (idNotif != null) toCancel.add(idNotif);
        batch.delete(doc.reference);
        continue;
      }

      // Regra do "hoje": >= agora + 10min
      if (_isSameCalendarDay(agendado, agora) && novoDt.isBefore(limiteHoje)) {
        final int? idNotif = data['idNotificacao'] as int?;
        if (idNotif != null) toCancel.add(idNotif);
        batch.delete(doc.reference);
        continue;
      }

      // Mudou o horário?
      if (agendado.millisecondsSinceEpoch != novoDt.millisecondsSinceEpoch) {
        final int? idNotif = data['idNotificacao'] as int?;
        if (idNotif != null) {
          final String idTrat = (data['idTratamento'] ?? '').toString();
          final t = provider.tratamentosMap[idTrat] ?? {};
          final body = _notifBodyFromTratamento(t);

          toCancel.add(idNotif);
          toResched.add({
            'idNotif': idNotif,
            'idLembrete': doc.id,
            'novoDt': novoDt,
            'body': body,
          });
        }
        batch.update(doc.reference, {
          'dataHoraAgendado': Timestamp.fromDate(novoDt),
        });
      }
    }

    await batch.commit();

    // Notificações fora do batch
    for (final id in toCancel) {
      await _safeCancelNotif(notif, id);
    }
    for (final item in toResched) {
      await _safeScheduleNotif(
        notif,
        id: item['idNotif'] as int,
        title: 'Hora do medicamento',
        body: item['body'] as String,
        when: item['novoDt'] as DateTime,
        idLembrete: item['idLembrete'] as String,
        idUsuario: idUsuario,
      );
    }

    await provider.fetchData();
  }

  // --------------------------- Ações Tomar/Pular/Adiar ---------------------------
  Future<void> marcarComoTomado({
    required BuildContext context,
    required String idUsuario,
    required String idLembrete,
  }) async {
    final notificationService = NotificationService();
    final agora = Timestamp.now();
    Timestamp? maiorDataAtualizada;

    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final lembreteClicado = provider.lembretes.firstWhere(
          (l) => l['id'] == idLembrete,
      orElse: () => throw Exception('Lembrete não encontrado'),
    );

    final String idTratamento = lembreteClicado['idTratamento'];
    final String tipoFrequencia = lembreteClicado['tipoFrequencia'] ?? "";
    final DateTime agendadoClicado =
    (lembreteClicado['dataHoraAgendado'] as Timestamp).toDate();

    // se for Intervalos Fixos e houver pendentes antigos, quita o mais antigo
    final pendentesAntigos = provider.lembretes
        .where((l) {
      final data = (l['dataHoraAgendado'] as Timestamp).toDate();
      return l['idTratamento'] == idTratamento &&
          data.isBefore(agendadoClicado) &&
          l['tomado'] != true &&
          l['adiado'] != true &&
          l['cancelado'] != true;
    })
        .toList()
      ..sort((a, b) => (a['dataHoraAgendado'] as Timestamp)
          .compareTo(b['dataHoraAgendado'] as Timestamp));

    final alvo = (tipoFrequencia == 'Intervalos Fixos' && pendentesAntigos.isNotEmpty)
        ? pendentesAntigos.first
        : lembreteClicado;

    final DateTime agendado = (alvo['dataHoraAgendado'] as Timestamp).toDate();
    final DateTime tomado = agora.toDate();
    final Duration diferenca = tomado.difference(agendado);

    // cancela notificação pendente
    final int? idNotif = alvo['idNotificacao'] as int?;
    if (idNotif != null) {
      await _safeCancelNotif(notificationService, idNotif);
    }

    // marca tomado
    await _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColLembretes)
        .doc(alvo['id'])
        .update({
      'tomado': true,
      'dataHoraTomado': agora,
      ..._markMeta(isSelf: _isSelf(context), userId: provider.userId),
    });

    // para Intervalos Fixos, desloca futuros
    if (tipoFrequencia == 'Intervalos Fixos') {
      await atualizaFuturosLembretes(
        provider,
        idTratamento,
        agendado,
        '',
        diferenca,
        maiorDataAtualizada,
        idUsuario,
        notificationService,
      );
    }

    // consome estoque
    await _consumirEstoqueEAvisar(
      context: context,
      idUsuario: idUsuario,
      idTratamento: idTratamento,
      decremento: _parseDosagemSeguro(provider.tratamentosMap, idTratamento),
    );

    // se contínuo/ativo, auto-estende
    try {
      final t = provider.tratamentosMap[idTratamento] ?? {};
      final tipo = (t['tipoTratamento'] ?? '').toString().toLowerCase();
      final status = (t['status'] ?? '').toString().toLowerCase();
      if ((tipo.contains('contínuo') || tipo.contains('continuo')) &&
          (status == 'ativo' || status == 'ativa' || status == 'active')) {
    await _autoEstenderSeContinuo(
    context: context,
    idUsuario: idUsuario,
    idTratamento: idTratamento,
    referencia: agendado,
    );
    }
    } catch (_) {}

    // finalize se não restaram vivos
    await _finalizarSeUltimo(
    context: context,
    idUsuario: idUsuario,
    idTratamento: idTratamento,
    dataTerminoPreferida: agendado,
    );
  }

  Future<void> pularLembrete({
    required String idLembrete,
    required BuildContext context,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final idUsuario = provider.contextoUsuarioId;
    final isSelf = provider.isContextoSouEu;

    final lembrete = provider.lembretes.firstWhere(
          (l) => l['id'] == idLembrete,
      orElse: () => throw Exception('Lembrete não encontrado'),
    );

    final int? idNotif = lembrete['idNotificacao'] as int?;
    if (idNotif != null) {
      await _safeCancelNotif(NotificationService(), idNotif);
    }

    await _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColLembretes)
        .doc(idLembrete)
        .update({
      'cancelado': true,
      ..._markMeta(isSelf: isSelf, userId: provider.userId),
    });

    await _finalizarSeUltimo(
      context: context,
      idUsuario: idUsuario,
      idTratamento: lembrete['idTratamento'],
      dataTerminoPreferida:
      (lembrete['dataHoraAgendado'] as Timestamp?)?.toDate(),
    );
  }

  Future<void> adiarLembrete({
    required BuildContext context,
    required String idLembrete,
    required DateTime novaDataHora,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final idUsuario = provider.contextoUsuarioId;
    final isSelf = provider.isContextoSouEu;

    final lembrete = provider.lembretes.firstWhere(
          (l) => l['id'] == idLembrete,
      orElse: () => throw Exception('Lembrete não encontrado'),
    );

    final antigaDataHora = (lembrete['dataHoraAgendado'] as Timestamp).toDate();
    final diferenca = novaDataHora.difference(antigaDataHora);
    final String idTratamento = lembrete['idTratamento'];
    final String tipoFrequencia = lembrete['tipoFrequencia'] ?? '';
    final tratamento = provider.tratamentosMap[idTratamento];

    final notif = NotificationService();

    if (isSelf) {
      // cancela antiga notificação
      final int? oldId = lembrete['idNotificacao'] as int?;
      if (oldId != null) await _safeCancelNotif(notif, oldId);

      // cria novo lembrete
      final novoDocRef = _firestore
          .collection(_kColUsuarios)
          .doc(idUsuario)
          .collection(_kColLembretes)
          .doc();
      final novoIdLembrete = novoDocRef.id;
      final int novoIdNotif = novoIdLembrete.hashCode.abs();

      await novoDocRef.set({
        'idTratamento': idTratamento,
        'dataHoraAgendado': Timestamp.fromDate(novaDataHora),
        'dataHoraTomado': null,
        'tomado': false,
        'adiado': false,
        'notificado': false,
        'idNovoLembrete': '',
        'cancelado': false,
        'refeicao': lembrete['refeicao'],
        'momento': lembrete['momento'],
        'idNotificacao': novoIdNotif,
        'tipoTratamento': lembrete['tipoTratamento'],
        'tipoFrequencia': lembrete['tipoFrequencia'],
        'status': 'ativo',
        ..._markMeta(isSelf: isSelf, userId: provider.userId),
      });

      // marca o antigo como adiado -> aponta para novo
      await _firestore
          .collection(_kColUsuarios)
          .doc(idUsuario)
          .collection(_kColLembretes)
          .doc(idLembrete)
          .update({
        'adiado': true,
        'idNovoLembrete': novoIdLembrete,
        ..._markMeta(isSelf: isSelf, userId: provider.userId),
      });

      // agenda notificação do novo
      final body =
          "${tratamento['nomeMedicamento']} ${tratamento['concentracaoMedicamento']} "
          "(${tratamento['dosagem']} ${tratamento['tipoMedicamento']})";
      await _safeScheduleNotif(
        notif,
        id: novoIdNotif,
        title: 'Hora do medicamento',
        body: body,
        when: novaDataHora,
        idLembrete: novoIdLembrete,
        idUsuario: idUsuario,
      );

      // desloca futuros se for Intervalos Fixos
      if (tipoFrequencia == 'Intervalos Fixos') {
        await atualizaFuturosLembretes(
          provider,
          idTratamento,
          antigaDataHora,
          novoIdLembrete,
          diferenca,
          null,
          idUsuario,
          notif,
        );
      }
    }
  }

  Future<void> atualizaFuturosLembretes(
      UsuarioProvider provider,
      String idTratamento,
      DateTime antigaDataHora,
      String novoIdLembrete,
      Duration diferenca,
      Timestamp? maiorDataAtualizada,
      String idUsuario,
      NotificationService notificationService,
      ) async {
    final isSelf = provider.isContextoSouEu;

    // Filtra em memória (mantendo sua lógica atual).
    final futuros = provider.lembretes.where((l) {
      final data = l['dataHoraAgendado'] as Timestamp;
      // Se quiser incluir exatamente em 'antigaDataHora', troque por: !data.toDate().isBefore(antigaDataHora)
      return l['idTratamento'] == idTratamento &&
          data.toDate().isAfter(antigaDataHora) &&
          l['tomado'] != true &&
          l['adiado'] != true &&
          l['cancelado'] != true &&
          l['id'] != novoIdLembrete;
    }).toList();

    if (futuros.isEmpty) {
      return;
    }

    final usuariosRef = _firestore.collection(_kColUsuarios).doc(idUsuario);
    final lembretesRef = usuariosRef.collection(_kColLembretes);

    // Vamos fazer updates em batch e reagendar notificações após o commit
    final batch = _firestore.batch();
    final notifsParaReagendar = <({
    int idNotificacao,
    String idLembrete,
    DateTime novaData
    })>[];

    for (final l in futuros) {
      final String id = l['id'];
      final DateTime dataAntiga = (l['dataHoraAgendado'] as Timestamp).toDate();
      final DateTime novaData = dataAntiga.add(diferenca);
      final int? idNotificacao = l['idNotificacao'];

      // Mantém a maior data para atualizar o dataTermino do tratamento
      if (maiorDataAtualizada == null || novaData.isAfter(maiorDataAtualizada.toDate())) {
        maiorDataAtualizada = Timestamp.fromDate(novaData);
      }

      // >>> AQUI ATUALIZA A DATA NO FIRESTORE <<<
      final docRef = lembretesRef.doc(id);
      batch.update(docRef, {
        'dataHoraAgendado': Timestamp.fromDate(novaData),
        ..._markMeta(isSelf: isSelf, userId: provider.userId),
      });

      // Prepara reagendamento de notificação (somente se for o próprio usuário)
      if (idNotificacao != null && isSelf) {
        notifsParaReagendar.add((
        idNotificacao: idNotificacao,
        idLembrete: id,
        novaData: novaData,
        ));
      }
    }

    // Aplica todas as atualizações nos lembretes
    await batch.commit();

    // Reagenda notificações depois do commit
    if (isSelf && notifsParaReagendar.isNotEmpty) {
      final tratamento = provider.tratamentosMap[idTratamento] ?? {};
      final body =
      "${tratamento['nomeMedicamento'] ?? ''} ${tratamento['concentracaoMedicamento'] ?? ''} "
          "(${tratamento['dosagem'] ?? ''} ${tratamento['tipoMedicamento'] ?? ''})".trim();

      for (final n in notifsParaReagendar) {
        await _safeCancelNotif(notificationService, n.idNotificacao);
        await _safeScheduleNotif(
          notificationService,
          id: n.idNotificacao,
          title: 'Hora do medicamento',
          body: body,
          when: n.novaData,
          idLembrete: n.idLembrete,
          idUsuario: idUsuario,
        );
      }
    }

    // Atualiza dataTermino do tratamento, se necessário
    if (maiorDataAtualizada != null) {
      await usuariosRef
          .collection(_kColTratamentos)
          .doc(idTratamento)
          .update({'dataTermino': maiorDataAtualizada});
    }


     for (final l in futuros) {
      l['dataHoraAgendado'] = Timestamp.fromDate(
         (l['dataHoraAgendado'] as Timestamp).toDate().add(diferenca),
       );
     }
  }


  // --------------------------- Estoque ---------------------------
  Future<void> _consumirEstoqueEAvisar({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    int decremento = 1,
  }) async {
    if (decremento <= 0) return;

    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final tratamento = provider.tratamentosMap[idTratamento] ?? {};
    final String idMedicamento = (tratamento['idMedicamento'] ?? '').toString();
    if (idMedicamento.isEmpty) return;

    DateTime? _asDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return DateTime(v.year, v.month, v.day);
      if (v is Timestamp) {
        final d = v.toDate();
        return DateTime(d.year, d.month, d.day);
      }
      if (v is String && v.trim().isNotEmpty) {
        try {
          return DateFormat('dd/MM/yyyy').parseStrict(v.trim());
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final estoqueMap = provider.estoqueMap;
    if (!estoqueMap.containsKey(idMedicamento)) return;

    final Map<String, dynamic> e = Map<String, dynamic>.from(
      estoqueMap[idMedicamento] as Map,
    );

    final int estoqueAtual = (e['qtdAtual'] as int?) ?? 0;
    final int qtdMinima = (e['qtdMinima'] as int?) ?? 0;
    final DateTime? validade = _asDate(e['dataValidade']);

    final int novoEstoqueAtual = (estoqueAtual - decremento).clamp(0, 1 << 31);

    await _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColEstoque)
        .doc(idMedicamento)
        .update({'qtdAtual': novoEstoqueAtual});

    e['qtdAtual'] = novoEstoqueAtual;
    estoqueMap[idMedicamento] = e;

    if (novoEstoqueAtual < qtdMinima) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Estoque baixo! Verifique a quantidade disponível.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (validade != null) {
      final DateTime hoje = DateTime.now();
      final DateTime dHoje = DateTime(hoje.year, hoje.month, hoje.day);
      final int diasRestantes = validade.difference(dHoje).inDays;

      if (diasRestantes < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⛔ Medicamento vencido! Atualize o estoque/validade.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (diasRestantes <= 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              diasRestantes == 0
                  ? '⚠️ Vence hoje! Verifique a validade do medicamento.'
                  : '⚠️ Validade em $diasRestantes dia(s). Programe a reposição.',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  int _parseDosagemSeguro(Map<String, dynamic> tratamentosMap, String idTratamento) {
    try {
      final raw = tratamentosMap[idTratamento]?['dosagem'];
      if (raw == null) return 1;
      if (raw is int) return raw > 0 ? raw : 1;
      if (raw is String && raw.trim().isNotEmpty) {
        final parsed = int.tryParse(raw.trim());
        return (parsed != null && parsed > 0) ? parsed : 1;
      }
      return 1;
    } catch (_) {
      return 1;
    }
  }

  // --------------------------- Extensão automática (contínuo) ---------------------------
  Future<void> _autoEstenderSeContinuo({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    required DateTime referencia,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final t = provider.tratamentosMap[idTratamento] ?? {};
    final tipo = (t['tipoTratamento'] ?? '').toString().toLowerCase();
    final status = (t['status'] ?? '').toString().toLowerCase();

    if (!(tipo.contains('contínuo') || tipo.contains('continuo'))) return;
    if (!(status == 'ativo' || status == 'ativa' || status == 'active')) return;

    final ult = await _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColLembretes)
        .where('idTratamento', isEqualTo: idTratamento)
        .where('cancelado', isEqualTo: false)
        .orderBy('dataHoraAgendado', descending: true)
        .limit(1)
        .get();
    if (ult.docs.isEmpty) return;

    final ultimoDt =
    (ult.docs.first.data()['dataHoraAgendado'] as Timestamp).toDate();

    // critério: se horizonte < 5 dias, cria +10 dias
    if (!ultimoDt.isBefore(referencia.add(const Duration(days: 5)))) return;

    final tipoFreq = (t['tipoFrequencia'] ?? '').toString();
    if (tipoFreq == 'Intervalos Fixos') {
      await _estenderPorIntervalo(
        context: context,
        idUsuario: idUsuario,
        idTratamento: idTratamento,
        ultimoDt: ultimoDt,
        tratamento: t,
        referencia: referencia,
      );
    } else if (tipoFreq == 'Horários Fixos') {
      await _estenderPorHorariosFixos(
        context: context,
        idUsuario: idUsuario,
        idTratamento: idTratamento,
        ultimoDt: ultimoDt,
        tratamento: t,
        referencia: referencia,
      );
    } else if (tipoFreq == 'Junto com Refeições') {
      await _estenderPorRefeicoes(
        context: context,
        idUsuario: idUsuario,
        idTratamento: idTratamento,
        ultimoDt: ultimoDt,
        tratamento: t,
        referencia: referencia,
      );
    }

    await _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColTratamentos)
        .doc(idTratamento)
        .update(_markMeta(isSelf: _isSelf(context), userId: provider.userId));
  }

  Future<void> _estenderPorIntervalo({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    required DateTime ultimoDt,
    required Map<String, dynamic> tratamento,
    required DateTime referencia,
  }) async {
    final notif = NotificationService();
    final provider = Provider.of<UsuarioProvider>(context, listen: false);

    int? intervaloHoras;
    final fH = tratamento['lembretes']?[0]?['valor'];
    if (fH is int) intervaloHoras = fH;
    if (intervaloHoras == null && fH is String) {
      intervaloHoras = int.tryParse(fH);
    }
    if (intervaloHoras == null || intervaloHoras <= 0) {
      final freqStr = (tratamento['frequencia'] ?? '').toString().toLowerCase();
      final match = RegExp(r'(\d{1,2})\s*h').firstMatch(freqStr);
      if (match != null) intervaloHoras = int.tryParse(match.group(1)!);
    }
    if (intervaloHoras == null || intervaloHoras <= 0) return;

    final body = _notifBodyFromTratamento(tratamento);
    final limite = ultimoDt.add(const Duration(days: 10));
    DateTime cursor = ultimoDt;

    while (cursor.isBefore(limite)) {
      cursor = cursor.add(Duration(hours: intervaloHoras));

      final exists = await _firestore
          .collection(_kColUsuarios)
          .doc(idUsuario)
          .collection(_kColLembretes)
          .where('idTratamento', isEqualTo: idTratamento)
          .where('dataHoraAgendado', isEqualTo: Timestamp.fromDate(cursor))
          .limit(1)
          .get();
      if (exists.docs.isNotEmpty) continue;

      final doc = _firestore
          .collection(_kColUsuarios)
          .doc(idUsuario)
          .collection(_kColLembretes)
          .doc();
      final idNotif = doc.id.hashCode.abs();

      await doc.set({
        'idTratamento': idTratamento,
        'dataHoraAgendado': Timestamp.fromDate(cursor),
        'dataHoraTomado': null,
        'tomado': false,
        'adiado': false,
        'notificado': false,
        'idNovoLembrete': '',
        'cancelado': false,
        'refeicao': null,
        'momento': null,
        'idNotificacao': idNotif,
        'tipoTratamento': tratamento['tipoTratamento'],
        'tipoFrequencia': 'Intervalos Fixos',
        'status': 'ativo',
        ..._markMeta(isSelf: _isSelf(context), userId: provider.userId),
      });

      await _safeScheduleNotif(
        notif,
        id: idNotif,
        title: 'Hora do medicamento',
        body: body,
        when: cursor,
        idLembrete: doc.id,
        idUsuario: idUsuario,
      );
    }

    provider.fetchData();
  }

  Future<void> _estenderPorHorariosFixos({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    required DateTime ultimoDt,
    required Map<String, dynamic> tratamento,
    required DateTime referencia,
  }) async {
    final notif = NotificationService();
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final body = _notifBodyFromTratamento(tratamento);

    final diaBase = DateTime(ultimoDt.year, ultimoDt.month, ultimoDt.day);
    final slotsSnap = await _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColLembretes)
        .where('idTratamento', isEqualTo: idTratamento)
        .where('cancelado', isEqualTo: false)
        .where('dataHoraAgendado', isGreaterThanOrEqualTo: Timestamp.fromDate(diaBase))
        .where(
      'dataHoraAgendado',
      isLessThan: Timestamp.fromDate(diaBase.add(const Duration(days: 1))),
    )
        .get();
    if (slotsSnap.docs.isEmpty) return;

    final slots = [
      for (final d in slotsSnap.docs)
        {
          'h': ((d.data()['dataHoraAgendado'] as Timestamp).toDate()).hour,
          'm': ((d.data()['dataHoraAgendado'] as Timestamp).toDate()).minute,
          'momento': d.data()['momento'],
        }
    ];

    DateTime cursorDia = diaBase.add(const Duration(days: 1));
    final fim = diaBase.add(const Duration(days: 10));

    while (cursorDia.isBefore(fim)) {
      for (final s in slots) {
        final ts = DateTime(
          cursorDia.year,
          cursorDia.month,
          cursorDia.day,
          (s['h'] as int?) ?? 0,
          (s['m'] as int?) ?? 0,
        );

        final exists = await _firestore
            .collection(_kColUsuarios)
            .doc(idUsuario)
            .collection(_kColLembretes)
            .where('idTratamento', isEqualTo: idTratamento)
            .where('dataHoraAgendado', isEqualTo: Timestamp.fromDate(ts))
            .limit(1)
            .get();
        if (exists.docs.isNotEmpty) continue;

        final doc = _firestore
            .collection(_kColUsuarios)
            .doc(idUsuario)
            .collection(_kColLembretes)
            .doc();
        final idNotif = doc.id.hashCode.abs();

        await doc.set({
          'idTratamento': idTratamento,
          'dataHoraAgendado': Timestamp.fromDate(ts),
          'dataHoraTomado': null,
          'tomado': false,
          'adiado': false,
          'notificado': false,
          'idNovoLembrete': '',
          'cancelado': false,
          'refeicao': null,
          'momento': s['momento'],
          'idNotificacao': idNotif,
          'tipoTratamento': tratamento['tipoTratamento'],
          'tipoFrequencia': 'Horários Fixos',
          'status': 'ativo',
          ..._markMeta(isSelf: _isSelf(context), userId: provider.userId),
        });

        if (_isSelf(context)) {
          await _safeScheduleNotif(
            notif,
            id: idNotif,
            title: 'Hora do medicamento',
            body: body,
            when: ts,
            idLembrete: doc.id,
            idUsuario: idUsuario,
          );
        }
      }
      cursorDia = cursorDia.add(const Duration(days: 1));
    }

    provider.fetchData();
  }

  Future<void> _estenderPorRefeicoes({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    required DateTime ultimoDt,
    required Map<String, dynamic> tratamento,
    required DateTime referencia,
  }) async {
    final notif = NotificationService();
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final body = _notifBodyFromTratamento(tratamento);

    final diaBase = DateTime(ultimoDt.year, ultimoDt.month, ultimoDt.day);
    final padraoSnap = await _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColLembretes)
        .where('idTratamento', isEqualTo: idTratamento)
        .where('cancelado', isEqualTo: false)
        .where('dataHoraAgendado', isGreaterThanOrEqualTo: Timestamp.fromDate(diaBase))
        .where(
      'dataHoraAgendado',
      isLessThan: Timestamp.fromDate(diaBase.add(const Duration(days: 1))),
    )
        .get();
    if (padraoSnap.docs.isEmpty) return;

    final refeicoesUsadas = <String>{
      for (final d in padraoSnap.docs)
        if ((d.data()['refeicao'] ?? '').toString().isNotEmpty)
          (d.data()['refeicao'] as String)
    };
    if (refeicoesUsadas.isEmpty) return;

    DateTime cursorDia = diaBase.add(const Duration(days: 1));
    final fim = diaBase.add(const Duration(days: 10));

    while (cursorDia.isBefore(fim)) {
      for (final r in refeicoesUsadas) {
        final hhmm = _horaRefeicaoParaDia(provider, cursorDia, r);
        final ts = _composeDateTime(cursorDia, hhmm);
        if (ts == null) continue;

        // regra do dia de referência: >= referencia + 10min
        if (_isSameCalendarDay(ts, referencia) &&
            ts.isBefore(referencia.add(const Duration(minutes: 10)))) {
          continue;
        }

        final exists = await _firestore
            .collection(_kColUsuarios)
            .doc(idUsuario)
            .collection(_kColLembretes)
            .where('idTratamento', isEqualTo: idTratamento)
            .where('dataHoraAgendado', isEqualTo: Timestamp.fromDate(ts))
            .limit(1)
            .get();
        if (exists.docs.isNotEmpty) continue;

        final doc = _firestore
            .collection(_kColUsuarios)
            .doc(idUsuario)
            .collection(_kColLembretes)
            .doc();
        final idNotif = doc.id.hashCode.abs();

        await doc.set({
          'idTratamento': idTratamento,
          'dataHoraAgendado': Timestamp.fromDate(ts),
          'dataHoraTomado': null,
          'tomado': false,
          'adiado': false,
          'notificado': false,
          'idNovoLembrete': '',
          'cancelado': false,
          'refeicao': r,
          'momento': null,
          'idNotificacao': idNotif,
          'tipoTratamento': tratamento['tipoTratamento'],
          'tipoFrequencia': 'Junto com Refeições',
          'status': 'ativo',
          ..._markMeta(isSelf: _isSelf(context), userId: provider.userId),
        });

        await _safeScheduleNotif(
          notif,
          id: idNotif,
          title: 'Hora do medicamento',
          body: body,
          when: ts,
          idLembrete: doc.id,
          idUsuario: idUsuario,
        );
      }
      cursorDia = cursorDia.add(const Duration(days: 1));
    }

    provider.fetchData();
  }

  // --------------------------- Finalização de tratamento ---------------------------

  Future<void> finalizarTratamento({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    DateTime? dataTermino,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final notif = NotificationService();
    final agora = DateTime.now();

    final usuariosRef = _firestore.collection(_kColUsuarios).doc(idUsuario);
    final tratRef = usuariosRef.collection(_kColTratamentos).doc(idTratamento);

    final Map<String, dynamic> tratamento =
        provider.tratamentosMap[idTratamento] ?? {};
    if (tratamento.isEmpty) throw Exception('Tratamento não encontrado');

    await tratRef.update({
      'status': 'finalizado',
      'dataTermino': Timestamp.fromDate(dataTermino ?? agora),
    });

    final lembretesCol = usuariosRef.collection(_kColLembretes);

    final passadosSnap = await lembretesCol
        .where('idTratamento', isEqualTo: idTratamento)
        .where('cancelado', isEqualTo: false)
        .where('dataHoraAgendado', isLessThan: Timestamp.fromDate(agora))
        .get();

    final futurosSnap = await lembretesCol
        .where('idTratamento', isEqualTo: idTratamento)
        .where('cancelado', isEqualTo: false)
        .where('dataHoraAgendado', isGreaterThanOrEqualTo: Timestamp.fromDate(agora))
        .get();

    final notifIds = <int>[
      for (final d in passadosSnap.docs)
        if ((d.data()['idNotificacao'] as int?) != null)
          (d.data()['idNotificacao'] as int)
    ];
    for (final d in futurosSnap.docs) {
      final id = d.data()['idNotificacao'] as int?;
      if (id != null) notifIds.add(id);
    }

    // marca passados como cancelado
    await _commitInChunks<QueryDocumentSnapshot<Map<String, dynamic>>>(
      passadosSnap.docs,
      op: (batch, doc) => batch.update(doc.reference, {'cancelado': true}),
    );

    // remove futuros
    await _commitInChunks<QueryDocumentSnapshot<Map<String, dynamic>>>(
      futurosSnap.docs,
      op: (batch, doc) => batch.delete(doc.reference),
    );

    // cancela notifs
    for (final id in notifIds) {
      await _safeCancelNotif(notif, id);
    }

    provider.fetchData();
  }

  // --------------------------- Finalização condicional ---------------------------
  Future<void> _finalizarSeUltimo({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    DateTime? dataTerminoPreferida,
  }) async {
    final usuariosRef = _firestore.collection(_kColUsuarios).doc(idUsuario);

    final vivosSnap = await usuariosRef
        .collection(_kColLembretes)
        .where('idTratamento', isEqualTo: idTratamento)
        .where('tomado', isEqualTo: false)
        .where('adiado', isEqualTo: false)
        .where('cancelado', isEqualTo: false)
        .limit(1)
        .get();

    if (vivosSnap.docs.isEmpty) {
      await usuariosRef.collection(_kColTratamentos).doc(idTratamento).update({
        'status': 'finalizado',
        'dataTermino':
        Timestamp.fromDate(dataTerminoPreferida ?? DateTime.now()),
      });

      try {
        final provider = Provider.of<UsuarioProvider>(context, listen: false);
        final tratsSnap =
        await usuariosRef.collection(_kColTratamentos).get();
        provider.tratamentosMap = {
          for (final d in tratsSnap.docs) d.id: d.data(),
        };
        provider.fetchData();
      } catch (_) {}
    }
  }

  //Cria/ressincroniza as notificações locais ao realizar login.

  Future<void> criarNotificacoesPosLogin({
    required BuildContext context,
    required String idUsuario,
    Duration janela = const Duration(days: 30),
    bool resetarAntes = true,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    if (!provider.isContextoSouEu) {
      // Evita agendar no dispositivo do cuidador para contas de terceiros.
      return;
    }

    final agora = DateTime.now();
    final limite = agora.add(janela);
    final notif = NotificationService();

    // 1) Opcionalmente, limpa agendamentos antigos (se o service permitir).
    if (resetarAntes) {
      try {
        // Se seu NotificationService tiver cancelAll(); se não, ignora sem erro.
        await notif.cancelAll();
      } catch (_) {}
    }

    // 2) Busca lembretes futuros "vivos" do usuário na janela definida
    final lembretesRef = _firestore
        .collection(_kColUsuarios)
        .doc(idUsuario)
        .collection(_kColLembretes);

    final querySnap = await lembretesRef
        .where('cancelado', isEqualTo: false)
        .where('adiado', isEqualTo: false)
        .where('tomado', isEqualTo: false)
        .where('dataHoraAgendado', isGreaterThanOrEqualTo: Timestamp.fromDate(agora))
        .where('dataHoraAgendado', isLessThan: Timestamp.fromDate(limite))
        .get();

    if (querySnap.docs.isEmpty) {
      return;
    }

    // 3) Prepara batch para preencher idNotificacao ausente e padronizar metadados
    final batch = _firestore.batch();
    final toSchedule = <({
    int idNotif,
    String idLembrete,
    String idTratamento,
    DateTime when,
    })>[];

    for (final d in querySnap.docs) {
      final data = d.data();
      final ts = data['dataHoraAgendado'] as Timestamp?;
      if (ts == null) continue; // dado inconsistente

      final when = ts.toDate();
      if (when.isBefore(agora)) continue; // por garantia

      final idTratamento = (data['idTratamento'] ?? '').toString();
      if (idTratamento.isEmpty) continue;

      int? idNotif = data['idNotificacao'] as int?;
      if (idNotif == null) {
        idNotif = d.id.hashCode.abs();
        batch.update(d.reference, {
          'idNotificacao': idNotif,
          ..._markMeta(isSelf: true, userId: provider.userId),
        });
      }

      toSchedule.add((
      idNotif: idNotif,
      idLembrete: d.id,
      idTratamento: idTratamento,
      when: when,
      ));
    }

    // 4) Aplica atualizações (se houver)
    if (toSchedule.isEmpty) return;
    await batch.commit();

    // 5) Agenda localmente (com corpo bonito da notif por tratamento)
    for (final item in toSchedule) {
      final t = provider.tratamentosMap[item.idTratamento] ?? {};
      final body = _notifBodyFromTratamento(t);

      // Cancel-and-replace defensivo: evita duplicidade se já existia pendente
      try {
        await _safeCancelNotif(notif, item.idNotif);
      } catch (_) {}

      await _safeScheduleNotif(
        notif,
        id: item.idNotif,
        title: 'Hora do medicamento',
        body: body,
        when: item.when,
        idLembrete: item.idLembrete,
        idUsuario: idUsuario,
      );
    }

    // 6) Atualiza caches em memória (opcional)
    try {
      await provider.fetchData();
    } catch (_) {}
  }


  static Future<void> realertOverdue(String pacienteUid) async {
    // -------------------- Configs --------------------
    const int kAtrasoMinutos = 15;
    const int kAntiSpamMinutos = 15;
    const int kOffsetQuandoExiste = 500000;
    const int kOffsetQuandoNaoExiste = 990000;

    // Campos
    const String fCancelado = 'cancelado';
    const String fAdiado = 'adiado';
    const String fTomado = 'tomado';
    const String fStatus = 'status';
    const String fAdiadoPara = 'adiadoPara';
    const String fAgendadoPara = 'dataHoraAgendado';
    const String fIdNotificacao = 'idNotificacao';
    const String fLastRealertedAt = 'lastRealertedAt';
    const String fRealertCount = 'realertCount';
    const String fIdTratamento = 'idTratamento';

    int? _toIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      return null;
    }

    String _notifBodyFromTratamento(Map<String, dynamic> t) {
      final nome = (t['nomeMedicamento'] ?? '').toString();
      final conc = (t['concentracaoMedicamento'] ?? '').toString();
      final dose = (t['dosagem'] ?? '').toString();
      final tm   = (t['tipoMedicamento'] ?? '').toString();
      if (nome.isNotEmpty && conc.isNotEmpty && dose.isNotEmpty && tm.isNotEmpty) {
        return '$nome $conc ($dose $tm)';
      }
      return 'Lembrete de medicamento';
    }

    String _montarCorpoFallback(Map<String, dynamic> m) {
      final s = (m[fStatus] ?? '').toString().trim();
      return s.isNotEmpty ? s : 'Lembrete de medicamento';
    }

    DateTime? _dataEfetiva(Map<String, dynamic> m) {
      final Timestamp? adiadoTs = m[fAdiadoPara] as Timestamp?;
      final Timestamp? agendadoTs = m[fAgendadoPara] as Timestamp?;
      return (adiadoTs ?? agendadoTs)?.toDate();
    }

    bool _estaAtrasado(DateTime efetivo, DateTime cutoff) =>
        !efetivo.isAfter(cutoff);

    bool _passouAntiSpam(DateTime agora, Map<String, dynamic> m) {
      final Timestamp? lastTs = m[fLastRealertedAt] as Timestamp?;
      if (lastTs == null) return true;
      return agora.difference(lastTs.toDate()).inMinutes >= kAntiSpamMinutos;
    }

    int _idNotifInstant(int? idOriginal, String docId) {
      if (idOriginal != null) return idOriginal + kOffsetQuandoExiste;
      return kOffsetQuandoNaoExiste + (docId.hashCode & 0x3FFFF);
    }

    // -------------------- Execução --------------------
    final agora = DateTime.now();
    final cutoff = agora.subtract(const Duration(minutes: kAtrasoMinutos));
    final cutoffTs = Timestamp.fromDate(cutoff);

    final db = FirebaseFirestore.instance;
    final col = db.collection('usuarios').doc(pacienteUid).collection('lembretes');

    // ⚠️ Requer índice composto: cancelado ASC, adiado ASC, tomado ASC, dataHoraAgendado ASC
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await col
          .where(fCancelado, isEqualTo: false)
          .where(fAdiado,    isEqualTo: false)
          .where(fTomado,    isEqualTo: false)
          .where(fAgendadoPara, isLessThanOrEqualTo: cutoffTs)
          .orderBy(fAgendadoPara)
          .limit(50)
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        // Logar e criar índice via link do e.message (opcional).
      }
      snap = await col.where(FieldPath.documentId, isEqualTo: '__none__').get();
    } catch (_) {
      snap = await col.where(FieldPath.documentId, isEqualTo: '__none__').get();
    }

    if (snap.docs.isEmpty) return;

    final notif = NotificationService();

    // Cache de tratamentos por ID para reduzir leituras
    final Map<String, Map<String, dynamic>> tratamentoCache = {};

    // Para reduzir I/O de escrita, acumule refs para auditoria
    final List<DocumentReference<Map<String, dynamic>>> toUpdate = [];
    int enviados = 0;

    for (final d in snap.docs) {
      final m = d.data();

      if (m[fCancelado] == true) continue;

      final efetivo = _dataEfetiva(m);
      if (efetivo == null) continue;
      if (!_estaAtrasado(efetivo, cutoff)) continue;

      if (!_passouAntiSpam(agora, m)) continue;

      // ===== Body bonito a partir do TRATAMENTO =====
      String body;
      final String idTrat = (m[fIdTratamento] ?? '').toString();
      if (idTrat.isNotEmpty) {
        Map<String, dynamic>? t = tratamentoCache[idTrat];
        if (t == null) {
          try {
            final tDoc = await db
                .collection('usuarios')
                .doc(pacienteUid)
                .collection('tratamentos')
                .doc(idTrat)
                .get(const GetOptions(source: Source.server));
            t = tDoc.data() ?? const {};
          } catch (_) {
            t = const {};
          }
          tratamentoCache[idTrat] = t!;
        }
        final b = _notifBodyFromTratamento(t);
        body = b.isNotEmpty ? b : _montarCorpoFallback(m);
      } else {
        body = _montarCorpoFallback(m);
      }

      final int? idOriginal = _toIntOrNull(m[fIdNotificacao]);
      final int idInstant = _idNotifInstant(idOriginal, d.id);

      // 🔔 Título agora inclui o horário original
      final String horarioFormatado =
      DateFormat('dd/MM HH:mm').format(efetivo); // exemplo: 21/10 08:30
      final String titulo =
          'Medicamento não tomado ($horarioFormatado)'; // ex: "Medicamento não tomado (21/10 08:30)"

      try {
        await LembreteService()._safeScheduleNotif(
          notif,
          id: idInstant,
          title: titulo,
          body: body,
          when: DateTime.now().add(const Duration(seconds: 1)),
          idLembrete: d.id,
          idUsuario: pacienteUid,
        );
        toUpdate.add(d.reference);
      } catch (_) {
        continue; // falhou notificação local; segue
      }
    }


    // Auditoria em lotes (max 500)
    for (var i = 0; i < toUpdate.length; i += 500) {
      final slice = toUpdate.sublist(i, (i + 500).clamp(0, toUpdate.length));
      final batch = db.batch();
      for (final ref in slice) {
        batch.update(ref, {
          fLastRealertedAt: FieldValue.serverTimestamp(),
          fRealertCount: FieldValue.increment(1),
        });
      }
      try {
        await batch.commit();
      } catch (_) {
        // best-effort
      }
    }


  }



}
