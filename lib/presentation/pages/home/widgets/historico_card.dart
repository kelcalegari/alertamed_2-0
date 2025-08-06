import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';

import 'package:provider/provider.dart';

class HistoricoCard extends StatelessWidget {
  final DateTime dia;

  const HistoricoCard({super.key, required this.dia});

  @override
  Widget build(BuildContext context) {
    final usuarioProvider = Provider.of<UsuarioProvider>(context);

    final eventos = <Map<String, dynamic>>[];

    for (var sintoma in usuarioProvider.sintomas) {
      final timestamp = sintoma['dataHora'];
      if (timestamp == null) continue;

      final dataHora = timestamp is DateTime ? timestamp : timestamp.toDate();

      if (_mesmoDia(dataHora, dia)) {
        eventos.add({
          'tipo': 'sintoma',
          'hora': dataHora,
          'nome': sintoma['nome'] ?? '',
        });
      }
    }

    for (var lembrete in usuarioProvider.lembretes) {
      if (lembrete['tomado'] == true && lembrete['dataHoraTomado'] != null) {
        final dataHora =
            lembrete['dataHoraTomado'] is DateTime
                ? lembrete['dataHoraTomado']
                : lembrete['dataHoraTomado'].toDate();

        if (_mesmoDia(dataHora, dia)) {
          final idTratamento = lembrete['idTratamento'];

          final nomeMedicamento = usuarioProvider.tratamentosMap[idTratamento]?['nomeMedicamento'] ?? 'Remédio';

          eventos.add({
            'tipo': 'medicamento',
            'hora': dataHora,
            'nome': nomeMedicamento,
          });
        }
      }
    }

    eventos.sort((a, b) => a['hora'].compareTo(b['hora']));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Histórico",
            style: TextStyle(color: AppColors.textBranco, fontSize: 18),
          ),
          const SizedBox(height: 8),
          if (eventos.isEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.cardBackgroundBranco,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "Nenhum evento nesse dia.",
                style: TextStyle(color: AppColors.textVerde),
              ),
            )
          else
            ...eventos.map((evento) {
              final hora = DateFormat('HH:mm').format(evento['hora']);
              final nome = evento['nome'] ?? '';
              final isSintoma = evento['tipo'] == 'sintoma';

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      hora,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textVerde,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isSintoma ? Icons.healing : Icons.medication,
                            color: AppColors.textVerde,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _capitalize(nome),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textVerde,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              );
            }).toList(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  String _capitalize(String? s) {
    if (s == null || s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }

  bool _mesmoDia(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
