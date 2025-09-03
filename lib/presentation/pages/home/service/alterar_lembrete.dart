import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/notification_service.dart';
import '../../../../providers/user_data_provider.dart';

class LembreteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===================== HELPERS P/ REFEIÇÕES =====================
  String _weekdayKeyPTBR(DateTime dt) {
    switch (dt.weekday) {
      case DateTime.monday:    return 'Seg';
      case DateTime.tuesday:   return 'Ter';
      case DateTime.wednesday: return 'Qua';
      case DateTime.thursday:  return 'Qui';
      case DateTime.friday:    return 'Sex';
      case DateTime.saturday:  return 'Sáb';
      case DateTime.sunday:    return 'Dom';
      default: return 'Padrão';
    }
  }

  String? _horaRefeicaoParaDia(
      UsuarioProvider provider,
      DateTime dia,
      String refeicao,
      ) {
    final cfg = provider.horarioRefeicaoParaDia(_weekdayKeyPTBR(dia));
    switch (refeicao) {
      case 'cafe':   return cfg['horaCafe'];
      case 'almoco': return cfg['horaAlmoco'];
      case 'jantar': return cfg['horaJanta'];
      default:       return null;
    }
  }

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

  String _notifBodyFromTratamento(Map<String, dynamic> t) {
    final nome = (t['nomeMedicamento'] ?? '').toString();
    final conc = (t['concentracaoMedicamento'] ?? '').toString();
    final dose = (t['dosagem'] ?? '').toString();
    final un   = (t['unidadeMedida'] ?? '').toString();
    if (nome.isNotEmpty && conc.isNotEmpty && dose.isNotEmpty && un.isNotEmpty) {
      return '$nome $conc ($dose $un)';
    }
    // fallback enxuto
    return 'Lembrete de medicamento';
  }

  // ===================== API: REAGENDAR POR LEMBRETES =====================
  /// Chame este método após salvar `horariosRefeicoes` do usuário.
  Future<void> reagendarLembretesPorRefeicaoViaLembretes({
    required BuildContext context,
    required String idUsuario,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final agora = DateTime.now();
    final limiteHoje = agora.add(const Duration(minutes: 10));
    final notif = NotificationService();

    // Busca APENAS lembretes futuros do tipo "Junto com Refeições"
    final snap = await _firestore
        .collection('usuarios').doc(idUsuario)
        .collection('lembretes')
        .where('cancelado', isEqualTo: false)
        .where('adiado', isEqualTo: false)
        .where('tipoFrequencia', isEqualTo: 'Junto com Refeições')
        .get();

    final batch = _firestore.batch();
    final toCancel = <int>[]; // idNotificacao a cancelar
    final toResched = <Map<String, dynamic>>[]; // {idNotif,idLembrete,novoDt,body}

    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['dataHoraAgendado'] as Timestamp?;
      if (ts == null) continue;

      final agendado = ts.toDate();
      if (agendado.isBefore(agora)) continue; // só futuros

      final refeicao = (data['refeicao'] ?? '').toString(); // cafe|almoco|jantar
      if (refeicao.isEmpty) continue;

      final hhmm = _horaRefeicaoParaDia(provider, agendado, refeicao);
      final novoDt = _composeDateTime(agendado, hhmm);

      // se não há horário para essa refeição -> remove
      if (novoDt == null) {
        final int? idNotif = data['idNotificacao'] as int?;
        if (idNotif != null) toCancel.add(idNotif);
        batch.delete(doc.reference);
        continue;
      }

      // regra do hoje: >= agora + 10min
      if (_isSameCalendarDay(agendado, agora) && novoDt.isBefore(limiteHoje)) {
        final int? idNotif = data['idNotificacao'] as int?;
        if (idNotif != null) toCancel.add(idNotif);
        batch.delete(doc.reference);
        continue;
      }

      // se mudou o horário -> atualiza + reagenda
      if (agendado.millisecondsSinceEpoch != novoDt.millisecondsSinceEpoch) {
        final int? idNotif = data['idNotificacao'] as int?;
        if (idNotif != null) {
          // monta body usando o tratamento
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

    // notifs fora do batch
    for (final id in toCancel) {
      try { await notif.cancelNotification(id); } catch (_) {}
    }
    for (final item in toResched) {
      try {
        await notif.scheduleNotification(
          id: item['idNotif'] as int,
          title: 'Hora do medicamento',
          body: item['body'] as String,
          scheduledDateTime: item['novoDt'] as DateTime,
          idLembrete: item['idLembrete'] as String,
          idUsuario: idUsuario,
        );
      } catch (_) {}
    }

    // recarrega cache local (opcional)
    try {
      final usuarioRef = _firestore.collection('usuarios').doc(idUsuario);
      final snapshot = await usuarioRef.collection('lembretes').get();
      provider.lembretes = snapshot.docs.map((d) {
        final m = d.data();
        m['id'] = d.id;
        return m;
      }).toList();
      provider.fetchData();
    } catch (_) {}
  }

  // ===================== MÉTODOS EXISTENTES (mantidos) =====================
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
    final Timestamp tsClicado = lembreteClicado['dataHoraAgendado'];
    final DateTime agendadoClicado = tsClicado.toDate();

    final lembreteAntigo = provider.lembretes
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

    final lembrete = lembreteAntigo.isNotEmpty ? lembreteAntigo.first : lembreteClicado;
    final Timestamp tsAgendado = lembrete['dataHoraAgendado'];
    final DateTime agendado = tsAgendado.toDate();
    final DateTime tomado = agora.toDate();
    final Duration diferenca = tomado.difference(agendado);

    if (lembrete['idNotificacao'] != null) {
      await notificationService.cancelNotification(lembrete['idNotificacao']);
    }

    await _firestore
        .collection('usuarios').doc(idUsuario)
        .collection('lembretes').doc(lembrete['id'])
        .update({'tomado': true, 'dataHoraTomado': agora});

    if (tipoFrequencia == 'Intervalos Fixos') {
      await atualizaFuturosLembretes(
        provider, idTratamento, agendado, '', diferenca,
        maiorDataAtualizada, idUsuario, notificationService,
      );
    }

    final idMedicamento = provider.tratamentosMap[idTratamento]["idMedicamento"];
    final estoqueMap = provider.estoqueMap;
    if (estoqueMap.containsKey(idMedicamento)) {
      final estoqueAtual = estoqueMap[idMedicamento]['qtdAtual'] as int;
      final qtdMinima = estoqueMap[idMedicamento]['qtdMinima'] as int;
      final novoEstoqueAtual = estoqueAtual - 1;

      await _firestore
          .collection('usuarios').doc(idUsuario)
          .collection('estoque').doc(idMedicamento)
          .update({'qtdAtual': novoEstoqueAtual});

      estoqueMap[idMedicamento]['qtdAtual'] = novoEstoqueAtual;

      if (novoEstoqueAtual < qtdMinima) {
        // ... snackbar igual ao seu código
      }
    }
  }

  Future<void> pularLembrete({
    required String idUsuario,
    required String idLembrete,
    required BuildContext context,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final lembrete = provider.lembretes.firstWhere(
          (l) => l['id'] == idLembrete,
      orElse: () => throw Exception('Lembrete não encontrado'),
    );

    if (lembrete['idNotificacao'] != null) {
      final notificationService = NotificationService();
      await notificationService.cancelNotification(lembrete['idNotificacao']);
    }
    await _firestore
        .collection('usuarios').doc(idUsuario)
        .collection('lembretes').doc(idLembrete)
        .update({'cancelado': true});
  }

  Future<void> adiarLembrete({
    required BuildContext context,
    required String idUsuario,
    required String idLembrete,
    required DateTime novaDataHora,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    Timestamp? maiorDataAtualizada;

    final lembrete = provider.lembretes.firstWhere(
          (l) => l['id'] == idLembrete,
      orElse: () => throw Exception('Lembrete não encontrado'),
    );

    final antigaDataHora = (lembrete['dataHoraAgendado'] as Timestamp).toDate();
    final diferenca = novaDataHora.difference(antigaDataHora);
    final String idTratamento = lembrete['idTratamento'];
    final String tipoFrequencia = lembrete['tipoFrequencia'] ?? "";
    final tratamento = provider.tratamentosMap[idTratamento];

    final notificationService = NotificationService();

    if (lembrete['idNotificacao'] != null) {
      await notificationService.cancelNotification(lembrete['idNotificacao']);
    }

    final novoDocRef = _firestore
        .collection('usuarios').doc(idUsuario)
        .collection('lembretes').doc();

    final novoIdLembrete = novoDocRef.id;
    final int novoIdNotificacao = novoIdLembrete.hashCode.abs();

    final novoLembrete = {
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
      'idNotificacao': novoIdNotificacao,
      'tipoTratamento': lembrete['tipoTratamento'],
      'tipoFrequencia': lembrete['tipoFrequencia'],
    };

    await novoDocRef.set(novoLembrete);

    await _firestore
        .collection('usuarios').doc(idUsuario)
        .collection('lembretes').doc(idLembrete)
        .update({'adiado': true, 'idNovoLembrete': novoIdLembrete});

    await notificationService.scheduleNotification(
      id: novoIdNotificacao,
      title: 'Hora do medicamento',
      body: "${tratamento['nomeMedicamento']} ${tratamento['concentracaoMedicamento']} "
          "(${tratamento['dosagem']} ${tratamento['tipoMedicamento']})",
      scheduledDateTime: novaDataHora,
      idLembrete: novoIdLembrete,
      idUsuario: idUsuario,
    );

    if (tipoFrequencia == 'Intervalos Fixos') {
      await atualizaFuturosLembretes(
        provider, idTratamento, antigaDataHora, novoIdLembrete, diferenca,
        maiorDataAtualizada, idUsuario, notificationService,
      );
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
    final futuros = provider.lembretes.where((l) {
      final data = l['dataHoraAgendado'] as Timestamp;
      return l['idTratamento'] == idTratamento &&
          data.toDate().isAfter(antigaDataHora) &&
          l['tomado'] != true &&
          l['adiado'] != true &&
          l['cancelado'] != true &&
          l['id'] != novoIdLembrete;
    });

    for (final l in futuros) {
      final String id = l['id'];
      final DateTime dataAntiga = (l['dataHoraAgendado'] as Timestamp).toDate();
      final DateTime novaData = dataAntiga.add(diferenca);
      final int? idNotificacao = l['idNotificacao'];

      if (maiorDataAtualizada == null || novaData.isAfter(maiorDataAtualizada.toDate())) {
        maiorDataAtualizada = Timestamp.fromDate(novaData);
      }

      await _firestore
          .collection('usuarios').doc(idUsuario)
          .collection('lembretes').doc(id)
          .update({'dataHoraAgendado': Timestamp.fromDate(novaData)});

      if (idNotificacao != null) {
        await notificationService.cancelNotification(idNotificacao);
        final tratamento = provider.tratamentosMap[idTratamento];
        await notificationService.scheduleNotification(
          id: idNotificacao,
          title: 'Hora do medicamento',
          body: "${tratamento['nomeMedicamento']} ${tratamento['concentracaoMedicamento']} "
              "(${tratamento['dosagem']} ${tratamento['tipoMedicamento']})",
          scheduledDateTime: novaData,
          idLembrete: id,
          idUsuario: idUsuario,
        );
      }
    }

    if (maiorDataAtualizada != null) {
      await _firestore
          .collection('usuarios').doc(idUsuario)
          .collection('tratamentos').doc(idTratamento)
          .update({'dataTermino': maiorDataAtualizada});
    }
  }
}
