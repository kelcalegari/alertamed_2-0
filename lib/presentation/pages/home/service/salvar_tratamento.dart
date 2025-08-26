import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/notification_service.dart';
import '../../../../providers/user_data_provider.dart';

class SalvarTratamento {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;


  final String nomeMedicamento;
  final String tipoMedicamento;
  final String concentracaoMedicamento;
  final String qtdMedicamento;
  final String qtdMedicamentoTotal;
  final String frequenciaHoras;
  final String dataInicial;
  final String horaInicial;
  final String? idCuidador;
  final String observacoes;
  final String? tipoTratamento;
  final String qtdMedicamentoEstoqueCtrl;
  final String qtdEstoqueMinimoCtrl;
  final String dataValidadeCtrl;
  final String unidadeMedida;
  final UsuarioProvider usuarioProvider;

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
  });

  Future<void> criarTratamentoComLembretes() async {
    final notificationService = NotificationService();
    final idUsuario = usuarioProvider.userId;
    final DateTime data = DateFormat("dd/MM/yyyy").parse(dataInicial);
    final DateTime hora = DateFormat("HH:mm").parse(horaInicial);
    final DateTime dataHoraInicio = DateTime(
      data.year,
      data.month,
      data.day,
      hora.hour,
      hora.minute,
    );

    final int totalDoses = int.parse(qtdMedicamentoTotal);
    final int freqHoras = int.parse(frequenciaHoras);
    final String idTratamento =
        firestore
            .collection('usuarios')
            .doc(idUsuario)
            .collection('tratamentos')
            .doc()
            .id;

    List<Map<String, dynamic>> lembretesArrayTratamento = [];
    List<Future<void>> tarefasLembretes = [];

    for (int i = 0; i < totalDoses; i++) {
      final DateTime dataLembrete = dataHoraInicio.add(
        Duration(hours: i * freqHoras),
      );
      final String idLembrete =
          firestore
              .collection('usuarios')
              .doc(idUsuario)
              .collection('lembretes')
              .doc()
              .id;
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
        'tipo': tipoTratamento ?? '',
        'refeicao': '',
        'momento': '',
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
      // Dispositivo (agendamento de notificação local)
      tarefasLembretes.add(
        notificationService.scheduleNotification(
          id: idNotificacao,
          title: 'Hora do medicamento',
          body: '$nomeMedicamento ${concentracaoMedicamento} (${qtdMedicamento} $tipoTratamento)',
          scheduledDateTime: dataLembrete, idLembrete: idLembrete, idUsuario: idUsuario,
        ),
      );
    }
    final lembreteArray = {
      'tipo': tipoTratamento ?? '',
      'valor': frequenciaHoras,
      'momento': '',
    };

    lembretesArrayTratamento.add(lembreteArray);
    final idMedicamento = gerarIdMedicamento(nomeMedicamento, concentracaoMedicamento, tipoMedicamento);
    final tratamentoDoc = {
      'idMedicamento': idMedicamento,
      'nomeMedicamento': nomeMedicamento,
      'concentracaoMedicamento': concentracaoMedicamento,
      'tipoMedicamento': tipoMedicamento,
      'dosagem': qtdMedicamento,
      'frequencia': '${(24 / freqHoras).round()}x ao dia',
      'dataInicio': Timestamp.fromDate(dataHoraInicio),
      'dataTermino': Timestamp.fromDate(
        dataHoraInicio.add(Duration(hours: (totalDoses - 1) * freqHoras)),
      ),
      'lembretes': lembretesArrayTratamento,
      'idCuidador': idCuidador ?? '',
      'observacoes': observacoes,
      'unidadeMedida':unidadeMedida,
      'status': 'ativo',
    };

    await firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('tratamentos')
        .doc(idTratamento)
        .set(tratamentoDoc);

    await Future.wait(tarefasLembretes);
    final novoEstoque = {
      'qtdAtual': int.parse(qtdMedicamentoEstoqueCtrl),
      'qtdMinima': int.parse(qtdEstoqueMinimoCtrl),
      'dataValidade': DateFormat('dd/MM/yyyy').parse(dataValidadeCtrl),
    };

    final estoqueMap = usuarioProvider.estoqueMap;



    final estoqueRef = firestore
        .collection('usuarios')
        .doc(idUsuario)
        .collection('estoque')
        .doc(idMedicamento);

    if (estoqueMap.containsKey(idMedicamento)) {
      // Atualiza o documento no Firebase
      await estoqueRef.update(novoEstoque);

      // Atualiza no provider
      estoqueMap[idMedicamento] = novoEstoque;
    } else {
      // Cria no Firebase
      await estoqueRef.set(novoEstoque);

      // Adiciona ao provider
      estoqueMap[idMedicamento] = novoEstoque;
    }
  }
  String gerarIdMedicamento(String nome, String conc, String tipo) {
    return '${nome.trim()}|${conc.trim()}|${tipo.trim()}'.toLowerCase().hashCode.toString();
  }
}
