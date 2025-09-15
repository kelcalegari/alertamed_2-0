import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_data_provider.dart';

class TratamentosCard extends StatelessWidget {
  final DateTime dataReferencia;
  final void Function(Map<String, dynamic> medicamento, Map<String, dynamic> tratamento) onTapTratamento;

  const TratamentosCard({
    super.key,
    required this.dataReferencia,
    required this.onTapTratamento,
  });

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<UsuarioProvider>(context);

    final tratamentos = provider.tratamentosMap.values.where((t) {
      if (t['status']?.toLowerCase() == 'cancelado') return false;

      final dataInicio = (t['dataInicio'] as Timestamp).toDate();
      final Timestamp? dataTerminoTs = t['dataTermino'] as Timestamp?;
      final DateTime? dataTermino = dataTerminoTs?.toDate();

      final depoisDoInicio = dataReferencia.isAfter(dataInicio.subtract(const Duration(days: 1)));
      final antesDoTermino = dataTermino == null
          ? true // se não tem término, não limita
          : dataReferencia.isBefore(dataTermino.add(const Duration(days: 1)));

      return depoisDoInicio && antesDoTermino;
    }).toList();


    if (tratamentos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seus Tratamentos',
              style: TextStyle(color: Color(0xFF002600), fontSize: 20),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF002600),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const ListTile(

                  title: Text(
                    'Não há tratamentos ativos nesta data',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  trailing: Icon(Icons.info_outline, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seus Tratamentos',
            style: TextStyle(color: Color(0xFF002600), fontSize: 20),
          ),
          const SizedBox(height: 12),
          ...tratamentos.map((tratamento) {



            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF002600),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () => onTapTratamento(tratamento,tratamento),
                  leading: const Icon(Icons.medication, color: Colors.white),
                  title: Text(
                    tratamento['nomeMedicamento'] ?? 'Medicamento',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tratamento['tipoMedicamento'] ?? '',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        tratamento['frequencia'] ?? '',
                        style: const TextStyle(color: Colors.white),
                      ),
                      if ((tratamento['observacoes'] ?? '').toString().isNotEmpty)
                        Text(
                          tratamento['observacoes'],
                          style: const TextStyle(color: Colors.white),
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white),
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
