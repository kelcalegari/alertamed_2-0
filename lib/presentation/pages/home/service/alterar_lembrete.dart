import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/notification_service.dart';
import '../../../../providers/user_data_provider.dart';

class LembreteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSelf(BuildContext context) =>
      Provider.of<UsuarioProvider>(context, listen: false).isContextoSouEu;
  // ===================== HELPERS P/ REFEIÇÕES =====================
  String _weekdayKeyPTBR(DateTime dt) {
    switch (dt.weekday) {
      case DateTime.monday:
        return 'Seg';
      case DateTime.tuesday:
        return 'Ter';
      case DateTime.wednesday:
        return 'Qua';
      case DateTime.thursday:
        return 'Qui';
      case DateTime.friday:
        return 'Sex';
      case DateTime.saturday:
        return 'Sáb';
      case DateTime.sunday:
        return 'Dom';
      default:
        return 'Padrão';
    }
  }

  Map<String, dynamic> _updatedBy(String role, String userId) => {
    'uid': userId,
    'role': role, // 'patient' ou 'caregiver'
  };
  String? _horaRefeicaoParaDia(
    UsuarioProvider provider,
    DateTime dia,
    String refeicao,
  ) {
    final cfg = provider.horarioRefeicaoParaDia(_weekdayKeyPTBR(dia));
    switch (refeicao) {
      case 'cafe':
        return cfg['horaCafe'];
      case 'almoco':
        return cfg['horaAlmoco'];
      case 'jantar':
        return cfg['horaJanta'];
      default:
        return null;
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
    final tm = (t['tipoMedicamento'] ?? '').toString();
    if (nome.isNotEmpty &&
        conc.isNotEmpty &&
        dose.isNotEmpty &&
        tm.isNotEmpty) {
      return '$nome $conc ($dose $tm)';
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
    final snap =
        await _firestore
            .collection('usuarios')
            .doc(idUsuario)
            .collection('lembretes')
            .where('cancelado', isEqualTo: false)
            .where('adiado', isEqualTo: false)
            .where('tipoFrequencia', isEqualTo: 'Junto com Refeições')
            .get();

    final batch = _firestore.batch();
    final toCancel = <int>[]; // idNotificacao a cancelar
    final toResched =
        <Map<String, dynamic>>[]; // {idNotif,idLembrete,novoDt,body}

    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['dataHoraAgendado'] as Timestamp?;
      if (ts == null) continue;

      final agendado = ts.toDate();
      if (agendado.isBefore(agora)) continue; // só futuros

      final refeicao =
          (data['refeicao'] ?? '').toString(); // cafe|almoco|jantar
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
      try {
        await notif.cancelNotification(id);
      } catch (_) {}
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
      provider.lembretes =
          snapshot.docs.map((d) {
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

    final lembreteAntigo =
        provider.lembretes.where((l) {
            final data = (l['dataHoraAgendado'] as Timestamp).toDate();
            return l['idTratamento'] == idTratamento &&
                data.isBefore(agendadoClicado) &&
                l['tomado'] != true &&
                l['adiado'] != true &&
                l['cancelado'] != true;
          }).toList()
          ..sort(
            (a, b) => (a['dataHoraAgendado'] as Timestamp).compareTo(
              b['dataHoraAgendado'] as Timestamp,
            ),
          );

    final lembrete =
        (tipoFrequencia == 'Intervalos Fixos' && lembreteAntigo.isNotEmpty)
            ? lembreteAntigo
                .first // pega o mais antigo pendente
            : lembreteClicado;
    final Timestamp tsAgendado = lembrete['dataHoraAgendado'];
    final DateTime agendado = tsAgendado.toDate();
    final DateTime tomado = agora.toDate();
    final Duration diferenca = tomado.difference(agendado);

    if (lembrete['idNotificacao'] != null) {
      await notificationService.cancelNotification(lembrete['idNotificacao']);
    }

    await _firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('lembretes')
        .doc(lembrete['id'])
        .update({'tomado': true, 'dataHoraTomado': agora});

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
    await _consumirEstoqueEAvisar(
      context: context,
      idUsuario: idUsuario,
      idTratamento: idTratamento,
      decremento: _parseDosagemSeguro(
        provider.tratamentosMap,
        idTratamento,
      ),
    );

    try {
      final tratamento = provider.tratamentosMap[idTratamento] ?? {};
      final tipo =
          (tratamento['tipoTratamento'] ?? '').toString().toLowerCase();
      final status = (tratamento['status'] ?? '').toString().toLowerCase();

      if (tipo.contains('contínuo') || tipo.contains('continuo')) {
        if (status == 'ativo' || status == 'ativa' || status == 'active') {
          await _autoEstenderSeContinuo(
            context: context,
            idUsuario: idUsuario,
            idTratamento: idTratamento,
            referencia:
                agendado,
          );
        }
      }
    } catch (_) {}
    await _firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('lembretes')
        .doc(lembrete['id'])
        .update({
          'pendingSync': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _updatedBy('paciente', idUsuario),
        });

    await _finalizarSeUltimo(
      context: context,
      idUsuario: idUsuario,
      idTratamento: idTratamento,
      // usa a data agendada como dataTermino preferida (ou hoje, no helper)
      dataTerminoPreferida:
          (lembrete['dataHoraAgendado'] as Timestamp?)?.toDate(),
    );
  }

  // Consome unidades do estoque do medicamento do tratamento e exibe avisos:
  // - decrementa qtdAtual (default: 1)
  // - avisa estoque baixo (qtdAtual < qtdMinima)
  // - avisa validade (<=10 dias) e vencido
  Future<void> _consumirEstoqueEAvisar({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    int decremento = 1, // caso queira consumir >1 unidade por dose
  }) async {
    if (decremento <= 0) return;

    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final tratamento = provider.tratamentosMap[idTratamento] ?? {};
    final String idMedicamento = (tratamento['idMedicamento'] ?? '').toString();
    if (idMedicamento.isEmpty) return;

    // helper local p/ converter validade
    DateTime? _asDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return DateTime(v.year, v.month, v.day);
      if (v is Timestamp) {
        final d = v.toDate();
        return DateTime(d.year, d.month, d.day);
      }
      if (v is String && v.trim().isNotEmpty) {
        try {
          // precisa de intl: DateFormat('dd/MM/yyyy')
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

    // decrementa (sem deixar negativo)
    final int novoEstoqueAtual = (estoqueAtual - decremento).clamp(0, 1 << 31);

    // persiste no Firestore
    await _firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('estoque')
        .doc(idMedicamento)
        .update({'qtdAtual': novoEstoqueAtual});

    // espelha no cache
    e['qtdAtual'] = novoEstoqueAtual;
    estoqueMap[idMedicamento] = e;

    // 1) aviso de estoque baixo
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

    // 2) aviso de validade (10 dias antes / vencido)
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

  int _parseDosagemSeguro(
    Map<String, dynamic> tratamentosMap,
    String idTratamento,
  ) {
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

  Future<void> pularLembrete({
    required String idLembrete,
    required BuildContext context,
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final idUsuario = provider.contextoUsuarioId;
    final isContextoSouEu = provider.isContextoSouEu;
    final lembrete = provider.lembretes.firstWhere(
      (l) => l['id'] == idLembrete,
      orElse: () => throw Exception('Lembrete não encontrado'),
    );

    if (lembrete['idNotificacao'] != null) {
      final notificationService = NotificationService();
      await notificationService.cancelNotification(lembrete['idNotificacao']);
    }

    await _firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('lembretes')
        .doc(idLembrete)
        .update({
          'cancelado': true,
          'scheduleVersion': 1,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _updatedBy(
            isContextoSouEu ? 'paciente' : 'cuidador',
            provider.userId,
          ),
          'pendingSync': isContextoSouEu ? false : true,
        });

    final String idTratamento = lembrete['idTratamento'];
    await _finalizarSeUltimo(
      context: context,
      idUsuario: idUsuario,
      idTratamento: idTratamento,
      // usa a data agendada como dataTermino preferida (ou hoje, no helper)
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
    final isContextoSouEu = provider.isContextoSouEu;
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
    if (isContextoSouEu) {
      if (lembrete['idNotificacao'] != null && isContextoSouEu) {
        await notificationService.cancelNotification(lembrete['idNotificacao']);
      }

      final novoDocRef =
          _firestore
              .collection('usuarios')
              .doc(idUsuario)
              .collection('lembretes')
              .doc();

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
        'scheduleVersion': 1,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _updatedBy(
          isContextoSouEu ? 'paciente' : 'cuidador',
          provider.userId,
        ),
        'pendingSync': isContextoSouEu ? false : true,
      };

      await novoDocRef.set(novoLembrete);

      await _firestore
          .collection('usuarios')
          .doc(idUsuario)
          .collection('lembretes')
          .doc(idLembrete)
          .update({
            'adiado': true,
            'idNovoLembrete': novoIdLembrete,
            'scheduleVersion': 1,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': _updatedBy(
              isContextoSouEu ? 'paciente' : 'cuidador',
              provider.userId,
            ),
            'pendingSync': isContextoSouEu ? false : true,
          });
      if (isContextoSouEu) {
        await notificationService.scheduleNotification(
          id: novoIdNotificacao,
          title: 'Hora do medicamento',
          body:
              "${tratamento['nomeMedicamento']} ${tratamento['concentracaoMedicamento']} "
              "(${tratamento['dosagem']} ${tratamento['tipoMedicamento']})",
          scheduledDateTime: novaDataHora,
          idLembrete: novoIdLembrete,
          idUsuario: idUsuario,
        );
      }

      if (tipoFrequencia == 'Intervalos Fixos') {
        await atualizaFuturosLembretes(
          provider,
          idTratamento,
          antigaDataHora,
          novoIdLembrete,
          diferenca,
          maiorDataAtualizada,
          idUsuario,
          notificationService,
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
    // Filtra do cache os lembretes futuros (mesma lógica que você usa)
    final futuros = provider.lembretes.where((l) {
      final data = l['dataHoraAgendado'] as Timestamp;
      return l['idTratamento'] == idTratamento &&
          data.toDate().isAfter(antigaDataHora) &&
          l['tomado'] != true &&
          l['adiado'] != true &&
          l['cancelado'] != true &&
          l['id'] != novoIdLembrete;
    });

    // Vamos reagendar localmente e marcar cada doc como sincronizado
    for (final l in futuros) {
      final String id = l['id'];
      final DateTime dataAntiga = (l['dataHoraAgendado'] as Timestamp).toDate();
      final DateTime novaData = dataAntiga.add(diferenca);
      final int? idNotificacao = l['idNotificacao'];

      if (maiorDataAtualizada == null ||
          novaData.isAfter(maiorDataAtualizada.toDate())) {
        maiorDataAtualizada = Timestamp.fromDate(novaData);
      }

      // Atualiza o Firestore com metadata do "paciente alterou"
      await _firestore
          .collection('usuarios')
          .doc(idUsuario)
          .collection('lembretes')
          .doc(id)
          .update({
            'scheduleVersion': 1,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': _updatedBy(
              provider.isContextoSouEu ? 'paciente' : 'cuidador',
              provider.userId,
            ),
            'pendingSync': provider.isContextoSouEu ? false : true,
          });

      // Reagendamento local (idempotente)
      if (idNotificacao != null && provider.isContextoSouEu) {
        try {
          await notificationService.cancelNotification(idNotificacao);
        } catch (_) {}
        final tratamento = provider.tratamentosMap[idTratamento];
        final body =
            "${tratamento['nomeMedicamento']} ${tratamento['concentracaoMedicamento']} "
            "(${tratamento['dosagem']} ${tratamento['tipoMedicamento']})";
        try {
          await notificationService.scheduleNotification(
            id: idNotificacao,
            title: 'Hora do medicamento',
            body: body,
            scheduledDateTime: novaData,
            idLembrete: id,
            idUsuario: idUsuario,
          );
        } catch (_) {}
      }
    }

    // (opcional, como você já fazia) se o último lembrete foi empurrado, mova o término
    if (maiorDataAtualizada != null) {
      await _firestore
          .collection('usuarios')
          .doc(idUsuario)
          .collection('tratamentos')
          .doc(idTratamento)
          .update({'dataTermino': maiorDataAtualizada});
    }
  }

  // === dentro da classe LembreteService ===
  // Cria mais 10 dias de lembretes se horizonte < 5 dias (âncora = `referencia`)
  Future<void> _autoEstenderSeContinuo({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    required DateTime referencia, // data agendada do lembrete processado
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final t = provider.tratamentosMap[idTratamento] ?? {};
    final tipo = (t['tipoTratamento'] ?? '').toString().toLowerCase();
    final status = (t['status'] ?? '').toString().toLowerCase();

    // Só para tratamento contínuo e ativo
    if (!(tipo.contains('contínuo') || tipo.contains('continuo'))) return;
    if (!(status == 'ativo' || status == 'ativa' || status == 'active')) return;

    // Último lembrete vivo do tratamento
    final ult =
        await _firestore
            .collection('usuarios')
            .doc(idUsuario)
            .collection('lembretes')
            .where('idTratamento', isEqualTo: idTratamento)
            .where('cancelado', isEqualTo: false)
            .orderBy('dataHoraAgendado', descending: true)
            .limit(1)
            .get();
    if (ult.docs.isEmpty) return;

    final ultimoDt =
        (ult.docs.first.data()['dataHoraAgendado'] as Timestamp).toDate();

    // Critério: último < referencia + 5 dias
    if (!ultimoDt.isBefore(referencia.add(const Duration(days: 5)))) return;

    // Despacha por tipo de frequência
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
        .collection('usuarios')
        .doc(idUsuario)
        .collection('tratamentos')
        .doc(idTratamento)
        .update({
          'scheduleVersion': 1,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _updatedBy(
            provider.isContextoSouEu ? 'paciente' : 'cuidador',
            provider.userId,
          ),
          'pendingSync': provider.isContextoSouEu ? false : true,
        });
  }

  /// --------- 1) Intervalos Fixos ----------
  Future<void> _estenderPorIntervalo({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    required DateTime ultimoDt,
    required Map<String, dynamic> tratamento,
    required DateTime
    referencia, // disponível se quiser regras relativas ao dia de referência
  }) async {
    final notif = NotificationService();
    final provider = Provider.of<UsuarioProvider>(context, listen: false);

    // Tenta obter o intervalo em horas
    int? intervaloHoras;
    final fH = tratamento['lembretes'][0]['valor'];
    if (fH is int) intervaloHoras = fH;
    if (intervaloHoras == null && fH is String) {
      intervaloHoras = int.tryParse(fH);
    }
    if (intervaloHoras == null || intervaloHoras <= 0) {
      // fallback: tenta extrair de 'frequencia' (ex.: "a cada 8h", "8h")
      final freqStr = (tratamento['frequencia'] ?? '').toString().toLowerCase();
      final match = RegExp(r'(\d{1,2})\s*h').firstMatch(freqStr);
      if (match != null) intervaloHoras = int.tryParse(match.group(1)!);
    }
    if (intervaloHoras == null || intervaloHoras <= 0) return;

    final body = _notifBodyFromTratamento(tratamento);
    final limite = ultimoDt.add(
      const Duration(days: 10),
    ); // estender por +10 dias
    DateTime cursor = ultimoDt;

    while (cursor.isBefore(limite)) {
      cursor = cursor.add(Duration(hours: intervaloHoras));

      // Evita duplicatas: mesmo tratamento + mesmo timestamp
      final exists =
          await _firestore
              .collection('usuarios')
              .doc(idUsuario)
              .collection('lembretes')
              .where('idTratamento', isEqualTo: idTratamento)
              .where('dataHoraAgendado', isEqualTo: Timestamp.fromDate(cursor))
              .limit(1)
              .get();
      if (exists.docs.isNotEmpty) continue;

      final doc =
          _firestore
              .collection('usuarios')
              .doc(idUsuario)
              .collection('lembretes')
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
        'scheduleVersion': 1,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': _updatedBy(
          provider.isContextoSouEu ? 'paciente' : 'cuidador',
          provider.userId,
        ),
        'pendingSync': provider.isContextoSouEu ? false : true,
        'status': 'ativo',
      });

      try {
        await notif.scheduleNotification(
          id: idNotif,
          title: 'Hora do medicamento',
          body: body,
          scheduledDateTime: cursor,
          idLembrete: doc.id,
          idUsuario: idUsuario,
        );
      } catch (_) {}
    }

    // refresh cache local
    try {
      final snapshot =
          await _firestore
              .collection('usuarios')
              .doc(idUsuario)
              .collection('lembretes')
              .get();
      provider.lembretes =
          snapshot.docs.map((d) {
            final m = d.data();
            m['id'] = d.id;
            return m;
          }).toList();
      provider.fetchData();
    } catch (_) {}
  }

  /// --------- 2) Horários Fixos ----------
  Future<void> _estenderPorHorariosFixos({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    required DateTime ultimoDt,
    required Map<String, dynamic> tratamento,
    required DateTime
    referencia, // disponível se quiser alguma validação temporal
  }) async {
    final notif = NotificationService();
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final body = _notifBodyFromTratamento(tratamento);

    // Descobre o "padrão de horários" do último dia existente
    final diaBase = DateTime(ultimoDt.year, ultimoDt.month, ultimoDt.day);
    final slotsSnap =
        await _firestore
            .collection('usuarios')
            .doc(idUsuario)
            .collection('lembretes')
            .where('idTratamento', isEqualTo: idTratamento)
            .where('cancelado', isEqualTo: false)
            .where(
              'dataHoraAgendado',
              isGreaterThanOrEqualTo: Timestamp.fromDate(diaBase),
            )
            .where(
              'dataHoraAgendado',
              isLessThan: Timestamp.fromDate(
                diaBase.add(const Duration(days: 1)),
              ),
            )
            .get();
    if (slotsSnap.docs.isEmpty) return;

    // Horas/min e momento (se você usar esse campo)
    final slots =
        slotsSnap.docs.map((d) {
          final m = d.data();
          final dt = (m['dataHoraAgendado'] as Timestamp).toDate();
          return {'h': dt.hour, 'm': dt.minute, 'momento': m['momento']};
        }).toList();

    // Replicar por +10 dias a partir do dia seguinte ao último dia
    DateTime cursorDia = diaBase.add(const Duration(days: 1));
    final fimProximoBloco = diaBase.add(const Duration(days: 10));

    while (cursorDia.isBefore(fimProximoBloco)) {
      for (final s in slots) {
        final ts = DateTime(
          cursorDia.year,
          cursorDia.month,
          cursorDia.day,
          (s['h'] as int?) ?? 0,
          (s['m'] as int?) ?? 0,
        );

        // Evita duplicar
        final exists =
            await _firestore
                .collection('usuarios')
                .doc(idUsuario)
                .collection('lembretes')
                .where('idTratamento', isEqualTo: idTratamento)
                .where('dataHoraAgendado', isEqualTo: Timestamp.fromDate(ts))
                .limit(1)
                .get();
        if (exists.docs.isNotEmpty) continue;

        final doc =
            _firestore
                .collection('usuarios')
                .doc(idUsuario)
                .collection('lembretes')
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
          'scheduleVersion': 1,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _updatedBy(
            provider.isContextoSouEu ? 'paciente' : 'cuidador',
            provider.userId,
          ),
          'pendingSync': provider.isContextoSouEu ? false : true,
          'status': 'ativo',
        });

        try {
          if (provider.isContextoSouEu) {
            await notif.scheduleNotification(
              id: idNotif,
              title: 'Hora do medicamento',
              body: body,
              scheduledDateTime: ts,
              idLembrete: doc.id,
              idUsuario: idUsuario,
            );
          }
        } catch (_) {}
      }
      cursorDia = cursorDia.add(const Duration(days: 1));
    }

    // refresh cache local
    try {
      final snapshot =
          await _firestore
              .collection('usuarios')
              .doc(idUsuario)
              .collection('lembretes')
              .get();
      provider.lembretes =
          snapshot.docs.map((d) {
            final m = d.data();
            m['id'] = d.id;
            return m;
          }).toList();
      provider.fetchData();
    } catch (_) {}
  }

  /// --------- 3) Junto com Refeições ----------
  Future<void> _estenderPorRefeicoes({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    required DateTime ultimoDt,
    required Map<String, dynamic> tratamento,
    required DateTime
    referencia, // usar na regra de "dia de referência + 10min"
  }) async {
    final notif = NotificationService();
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final body = _notifBodyFromTratamento(tratamento);

    // Quais refeições foram usadas no último dia (cafe/almoco/jantar)
    final diaBase = DateTime(ultimoDt.year, ultimoDt.month, ultimoDt.day);
    final padraoSnap =
        await _firestore
            .collection('usuarios')
            .doc(idUsuario)
            .collection('lembretes')
            .where('idTratamento', isEqualTo: idTratamento)
            .where('cancelado', isEqualTo: false)
            .where(
              'dataHoraAgendado',
              isGreaterThanOrEqualTo: Timestamp.fromDate(diaBase),
            )
            .where(
              'dataHoraAgendado',
              isLessThan: Timestamp.fromDate(
                diaBase.add(const Duration(days: 1)),
              ),
            )
            .get();
    if (padraoSnap.docs.isEmpty) return;

    final refeicoesUsadas = <String>{};
    for (final d in padraoSnap.docs) {
      final r = (d.data()['refeicao'] ?? '').toString();
      if (r.isNotEmpty) refeicoesUsadas.add(r); // 'cafe' | 'almoco' | 'jantar'
    }
    if (refeicoesUsadas.isEmpty) return;

    // Gerar próximos 10 dias
    DateTime cursorDia = diaBase.add(const Duration(days: 1));
    final fim = diaBase.add(const Duration(days: 10));

    while (cursorDia.isBefore(fim)) {
      for (final r in refeicoesUsadas) {
        final hhmm = _horaRefeicaoParaDia(
          provider,
          cursorDia,
          r,
        ); // busca no provider horário do dia/semana
        final ts = _composeDateTime(cursorDia, hhmm);
        if (ts == null) continue;

        // Regra do "dia de referência": se for o mesmo dia da referência, só cria se ts >= referencia + 10min
        if (_isSameCalendarDay(ts, referencia) &&
            ts.isBefore(referencia.add(const Duration(minutes: 10)))) {
          continue;
        }

        // Evita duplicar
        final exists =
            await _firestore
                .collection('usuarios')
                .doc(idUsuario)
                .collection('lembretes')
                .where('idTratamento', isEqualTo: idTratamento)
                .where('dataHoraAgendado', isEqualTo: Timestamp.fromDate(ts))
                .limit(1)
                .get();
        if (exists.docs.isNotEmpty) continue;

        final doc =
            _firestore
                .collection('usuarios')
                .doc(idUsuario)
                .collection('lembretes')
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
          'refeicao': r, // 'cafe' | 'almoco' | 'jantar'
          'momento': null,
          'idNotificacao': idNotif,
          'tipoTratamento': tratamento['tipoTratamento'],
          'tipoFrequencia': 'Junto com Refeições',
          'scheduleVersion': 1,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': _updatedBy(
            provider.isContextoSouEu ? 'paciente' : 'cuidador',
            provider.userId,
          ),
          'pendingSync': provider.isContextoSouEu ? false : true,
          'status': 'ativo',
        });

        try {
          await notif.scheduleNotification(
            id: idNotif,
            title: 'Hora do medicamento',
            body: body,
            scheduledDateTime: ts,
            idLembrete: doc.id,
            idUsuario: idUsuario,
          );
        } catch (_) {}
      }
      cursorDia = cursorDia.add(const Duration(days: 1));
    }

    // refresh cache local
    try {
      final snapshot =
          await _firestore
              .collection('usuarios')
              .doc(idUsuario)
              .collection('lembretes')
              .get();
      provider.lembretes =
          snapshot.docs.map((d) {
            final m = d.data();
            m['id'] = d.id;
            return m;
          }).toList();
      provider.fetchData();
    } catch (_) {}
  }

  /// Finaliza um tratamento:
  /// - status := "finalizado"
  /// - dataTermino := agora (ou valor informado)
  /// - cancela todos os lembretes FUTUROS do tratamento e suas notificações
  Future<void> finalizarTratamento({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    DateTime? dataTermino, // opcional: sobrescreve a data de término
  }) async {
    final provider = Provider.of<UsuarioProvider>(context, listen: false);
    final notif = NotificationService();
    final agora = DateTime.now();

    // 1) Confere se o tratamento existe no cache
    final Map<String, dynamic> tratamento =
        provider.tratamentosMap[idTratamento] ?? {};
    if (tratamento.isEmpty) {
      throw Exception('Tratamento não encontrado');
    }

    // 2) Atualiza o documento do tratamento: status + dataTermino
    final usuariosRef = _firestore.collection('usuarios').doc(idUsuario);
    final tratRef = usuariosRef.collection('tratamentos').doc(idTratamento);

    await tratRef.update({
      'status': 'finalizado',
      'dataTermino': Timestamp.fromDate(dataTermino ?? agora),
    });

    // 3) Busca lembretes FUTUROS (>= agora) vivos (não cancelados) e do tratamento
    final futurosSnap =
        await usuariosRef
            .collection('lembretes')
            .where('idTratamento', isEqualTo: idTratamento)
            .where('cancelado', isEqualTo: false)
            .where(
              'dataHoraAgendado',
              isGreaterThanOrEqualTo: Timestamp.fromDate(agora),
            )
            .get();

    // 4) Marca como cancelado em batch e coleta ids de notificação p/ cancelar
    final batch = _firestore.batch();
    final notifIdsToCancel = <int>[];

    for (final doc in futurosSnap.docs) {
      final data = doc.data();
      final int? idNotif = data['idNotificacao'] as int?;
      if (idNotif != null) notifIdsToCancel.add(idNotif);

      batch.update(doc.reference, {'cancelado': true});
    }

    await batch.commit();

    // 5) Cancela notificações agendadas (fora do batch)
    for (final id in notifIdsToCancel) {
      try {
        await notif.cancelNotification(id);
      } catch (_) {}
    }

    // 6) Recarrega cache local (lembretes e tratamentos) e notifica UI
    try {
      final lembretesSnap = await usuariosRef.collection('lembretes').get();
      provider.lembretes =
          lembretesSnap.docs.map((d) {
            final m = d.data();
            m['id'] = d.id;
            return m;
          }).toList();

      // Atualiza o mapa de tratamentos no provider (pequeno refresh)
      final tratsSnap = await usuariosRef.collection('tratamentos').get();
      provider.tratamentosMap = {
        for (final d in tratsSnap.docs) d.id: d.data(),
      };

      provider.fetchData();
    } catch (_) {}

    // Pronto: tratamento finalizado e lembretes futuros cancelados.
  }

  // --- Helper: finaliza se não restarem lembretes vivos do tratamento ---
  Future<void> _finalizarSeUltimo({
    required BuildContext context,
    required String idUsuario,
    required String idTratamento,
    DateTime? dataTerminoPreferida,
  }) async {
    final usuariosRef = _firestore.collection('usuarios').doc(idUsuario);

    // existe algum lembrete VIVO (não tomado/adiado/cancelado) ainda?
    final vivosSnap =
        await usuariosRef
            .collection('lembretes')
            .where('idTratamento', isEqualTo: idTratamento)
            .where('tomado', isEqualTo: false)
            .where('adiado', isEqualTo: false)
            .where('cancelado', isEqualTo: false)
            .limit(1)
            .get();

    if (vivosSnap.docs.isEmpty) {
      // Finaliza tratamento
      await usuariosRef.collection('tratamentos').doc(idTratamento).update({
        'status': 'finalizado',
        'dataTermino': Timestamp.fromDate(
          dataTerminoPreferida ?? DateTime.now(),
        ),
      });

      // opcional: refresh básico no provider
      try {
        final provider = Provider.of<UsuarioProvider>(context, listen: false);
        final tratsSnap = await usuariosRef.collection('tratamentos').get();
        provider.tratamentosMap = {
          for (final d in tratsSnap.docs) d.id: d.data(),
        };
        provider.fetchData();
      } catch (_) {}
    }
  }
}
