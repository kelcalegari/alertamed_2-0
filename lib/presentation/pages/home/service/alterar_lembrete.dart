import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/notification_service.dart';
import '../../../../providers/user_data_provider.dart';

class LembreteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
    final Timestamp tsClicado = lembreteClicado['dataHoraAgendado'];
    final DateTime agendadoClicado = tsClicado.toDate();

    // Verifica se há lembretes anteriores ainda não tomados, adiados ou cancelados
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
        lembreteAntigo.isNotEmpty ? lembreteAntigo.first : lembreteClicado;
    final Timestamp tsAgendado = lembrete['dataHoraAgendado'];
    final DateTime agendado = tsAgendado.toDate();
    final DateTime tomado = agora.toDate();
    final Duration diferenca = tomado.difference(agendado);

    if (lembrete['idNotificacao'] != null) {
      await notificationService.cancelNotification(lembrete['idNotificacao']);
    }

    // Atualiza o lembrete como tomado
    await _firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('lembretes')
        .doc(lembrete['id'])
        .update({'tomado': true, 'dataHoraTomado': agora});
    // Atualiza futuros lembretes
    await atualizaFuturosLembretes(provider, idTratamento, agendado, '' , diferenca, maiorDataAtualizada, idUsuario, notificationService);

    final idMedicamento = provider.tratamentosMap[idTratamento]["idMedicamento"];
    // Atualiza estoque
    final estoqueMap = provider.estoqueMap;
    if (estoqueMap.containsKey(idMedicamento)) {
      final estoqueAtual = estoqueMap[idMedicamento]['qtdAtual'] as int;
      final qtdMinima = estoqueMap[idMedicamento]['qtdMinima'] as int;
      final novoEstoqueAtual = estoqueAtual - 1;

      await _firestore
          .collection('usuarios')
          .doc(idUsuario)
          .collection('estoque')
          .doc(idMedicamento)
          .update({'qtdAtual': novoEstoqueAtual});

      estoqueMap[idMedicamento]['qtdAtual'] = novoEstoqueAtual;

      if (novoEstoqueAtual < qtdMinima) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Estoque abaixo do mínimo!',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
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
        .collection('usuarios')
        .doc(idUsuario)
        .collection('lembretes')
        .doc(idLembrete)
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

    final tratamento = provider.tratamentosMap[idTratamento];

    final notificationService = NotificationService();

    // Cancela notificação anterior
    if (lembrete['idNotificacao'] != null) {
      await notificationService.cancelNotification(lembrete['idNotificacao']);
    }

    // Cria novo idNotificacao baseado no novo id do lembrete (ainda não gerado)
    final novoDocRef = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(idUsuario)
        .collection('lembretes')
        .doc(); // Geramos um docRef com id antes do set()

    final novoIdLembrete = novoDocRef.id;
    final int novoIdNotificacao = novoIdLembrete.hashCode.abs();

    final novoLembrete = {
      'idTratamento': idTratamento,
      'dataHoraAgendado': Timestamp.fromDate(novaDataHora),
      'tomado': false,
      'adiado': false,
      'notificado': false,
      'cancelado': false,
      'tipo': lembrete['tipo'],
      'refeicao': lembrete['refeicao'],
      'momento': lembrete['momento'],
      'idNotificacao': novoIdNotificacao,
    };

    // Salva novo lembrete no Firestore
    await novoDocRef.set(novoLembrete);

    // Marca o anterior como adiado
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(idUsuario)
        .collection('lembretes')
        .doc(idLembrete)
        .update({
      'adiado': true,
      'idNovoLembrete': novoIdLembrete,
    });


    // Agenda nova notificação local
    await notificationService.scheduleNotification(
      id: novoIdNotificacao,
      title: 'Hora do medicamento',
      body: "${tratamento['nomeMedicamento']} ${tratamento['concentracaoMedicamento']} (${tratamento['dosagem']} ${tratamento['tipoMedicamento']})",
      scheduledDateTime: novaDataHora, idLembrete: novoIdLembrete, idUsuario: idUsuario,
    );

    // Atualiza futuros lembretes
    await atualizaFuturosLembretes(provider, idTratamento, antigaDataHora, novoIdLembrete, diferenca, maiorDataAtualizada, idUsuario, notificationService);
  }

  Future<void> atualizaFuturosLembretes(UsuarioProvider provider, String idTratamento, DateTime antigaDataHora, String novoIdLembrete, Duration diferenca, Timestamp? maiorDataAtualizada, String idUsuario, NotificationService notificationService) async {
    final futurosLembretes = provider.lembretes.where((l) {
      final data = l['dataHoraAgendado'] as Timestamp;
      return l['idTratamento'] == idTratamento &&
          data.toDate().isAfter(antigaDataHora) &&
          l['tomado'] != true &&
          l['adiado'] != true &&
          l['cancelado'] != true &&
          l['id'] != novoIdLembrete;
    });

    for (final l in futurosLembretes) {
      final String id = l['id'];
      final DateTime dataAntiga = (l['dataHoraAgendado'] as Timestamp).toDate();
      final DateTime novaData = dataAntiga.add(diferenca);
      final int? idNotificacao = l['idNotificacao'];

      if (maiorDataAtualizada == null || novaData.isAfter(maiorDataAtualizada.toDate())) {
        maiorDataAtualizada = Timestamp.fromDate(novaData);
      }

      // Atualiza no Firestore
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(idUsuario)
          .collection('lembretes')
          .doc(id)
          .update({'dataHoraAgendado': Timestamp.fromDate(novaData)});

      // Atualiza notificação local (cancelar + reagendar)
      if (idNotificacao != null) {
        await notificationService.cancelNotification(idNotificacao);
        final tratamento = provider.tratamentosMap[idTratamento];

        await notificationService.scheduleNotification(
          id: idNotificacao,
          title: 'Hora do medicamento',
          body: "${tratamento['nomeMedicamento']} ${tratamento['concentracaoMedicamento']} (${tratamento['dosagem']} ${tratamento['tipoMedicamento']})",
          scheduledDateTime: novaData, idLembrete: id, idUsuario: idUsuario,
        );
      }
    }


    // Atualiza data de término do tratamento
    if (maiorDataAtualizada != null) {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(idUsuario)
          .collection('tratamentos')
          .doc(idTratamento)
          .update({'dataTermino': maiorDataAtualizada});
    }
  }

}
