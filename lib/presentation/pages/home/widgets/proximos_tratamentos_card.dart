import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';
import '../modals/lembrete_detalhe_popup.dart';
import '../service/alterar_lembrete.dart';

class ProximosTratamentosCard extends StatelessWidget {
  final VoidCallback onRegistrarSintoma;
  final VoidCallback onRegistrarTratamento;
  final VoidCallback onCardAssistenteIa;
  final VoidCallback onCardRelatorio;
  final DateTime dia;
  const ProximosTratamentosCard({
    super.key,
    required this.onRegistrarSintoma,
    required this.onRegistrarTratamento,
    required this.onCardAssistenteIa,
    required this.dia, required this.onCardRelatorio,
  });

  @override
  Widget build(BuildContext context) {
    final usuarioProvider = Provider.of<UsuarioProvider>(context);

    final inicioDia = DateTime(dia.year, dia.month, dia.day);
    final fimDia = DateTime(dia.year, dia.month, dia.day, 23, 59);
    final userId = usuarioProvider.userId;
    final lembretesDoDia =
        usuarioProvider.lembretes.where((l) {
            final tomado = l['tomado'] == true;
            final cancelado = l['cancelado'] == true;
            final adiado = l['adiado'] == true;
            final ts = l['dataHoraAgendado'];
            if (tomado || ts == null || adiado || cancelado) return false;
            final d = (ts as Timestamp).toDate();
            return d.isAfter(inicioDia) && d.isBefore(fimDia);
          }).toList()
          ..sort((a, b) {
            final d1 = (a['dataHoraAgendado'] as Timestamp).toDate();
            final d2 = (b['dataHoraAgendado'] as Timestamp).toDate();
            return d1.compareTo(d2);
          });

    Future<void> _handleRefresh() async {
      final usuarioProvider = context.read<UsuarioProvider>();
      usuarioProvider.isLoading = true;
      await usuarioProvider.fetchData();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundBranco,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lembretesDoDia.isNotEmpty) ...[
              const Text(
                "Próximos Tratamentos",
                style: TextStyle(
                  color: AppColors.textVerde,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...lembretesDoDia.map((l) {
                final hora = DateFormat.Hm().format(
                  (l['dataHoraAgendado'] as Timestamp).toDate(),
                );
                final data = (l['dataHoraAgendado'] as Timestamp).toDate();

                final dataStr = DateFormat('dd/MM/yyyy').format(data);
                final idLembrete = l['id'];
                final idTrat = l['idTratamento'];
                final tratamento = usuarioProvider.tratamentosMap[idTrat] ?? {};


                final nome = tratamento['nomeMedicamento'] ?? 'Medicamento';
                final dosagem = tratamento['dosagem'] ?? '';
                final tipoMedicamento = tratamento['tipoMedicamento'] ?? '';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      LembreteDetalhePopup.show(
                        context: context,
                        nome: nome,
                        dose: '$dosagem $tipoMedicamento',
                        data: dataStr,
                        horario: hora,
                        observacao: tratamento['observacao'] ?? '',
                        onTomar: () async {
                          await LembreteService().marcarComoTomado(
                            context: context,
                            idUsuario: userId,
                            idLembrete: idLembrete,
                          );
                          _handleRefresh();
                          Navigator.pop(context);
                        },
                        onAdiar: (novaDataHora) async {
                          await LembreteService().adiarLembrete(
                            context: context,
                            idUsuario: userId,
                            idLembrete: idLembrete,
                            novaDataHora:
                            novaDataHora,
                          );
                          _handleRefresh();
                          Navigator.pop(context);
                        },
                        onPular: () async {
                          await LembreteService().pularLembrete(
                            idUsuario: userId,
                            idLembrete: idLembrete,
                            context: context,
                          );
                          _handleRefresh();
                          Navigator.pop(context);
                        },
                        onVerDetalhe: () {
                          // Ex: abrir nova tela com os detalhes do medicamento
                          Navigator.pop(context);
                        },
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardBackgroundVerde,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Text(
                            hora,
                            style: const TextStyle(color: AppColors.textBranco),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.medication,
                            color: AppColors.textBranco,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "$nome  $dosagem $tipoMedicamento",
                              style: const TextStyle(
                                color: AppColors.textBranco,
                              ),
                            ),
                          ),
                          const Icon(Icons.add, color: AppColors.textBranco),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 16),
            _buildBotao(context, "Adicionar Tratamento", onRegistrarTratamento),
            const SizedBox(height: 8),
            _buildBotao(context, "Registrar Sintoma", onRegistrarSintoma),
            const SizedBox(height: 8),
            _buildBotao(context, "Orientação Inteligente", onCardAssistenteIa),
            const SizedBox(height: 8),
            _buildBotao(context, "Gerar Retórios", onCardRelatorio),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildBotao(BuildContext context, String texto, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackgroundVerde,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(color: AppColors.textBranco),
              ),
            ),
            const Icon(Icons.add, color: AppColors.textBranco),
          ],
        ),
      ),
    );
  }
}
