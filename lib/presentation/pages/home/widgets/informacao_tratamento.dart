import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';

class InformacaoTratamento extends StatelessWidget {
  final VoidCallback onCancel;
  final Map<String, dynamic> tratamento;

  const InformacaoTratamento({
    super.key,
    required this.onCancel,
    required this.tratamento
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final String nomeMedicamento = tratamento['nomeMedicamento'] ?? '';
    final String concentracaoMedicamento = tratamento['concentracaoMedicamento'] ?? '';
    final String tipoMedicamento = tratamento['tipoMedicamento'] ?? '';
    final String dosagem = tratamento['dosagem'] ?? '';
    final String unidadeMedida = tratamento['unidadeMedida'] ?? '';
    final String frequencia = tratamento['frequencia'] ?? '';





    final usuarioProvider = Provider.of<UsuarioProvider>(context);
    final String idMedicamento = tratamento['idMedicamento'] ?? '';
    final Map<String, dynamic>? estoque =
        usuarioProvider.estoqueMap[idMedicamento];



    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! > 10) {
          onCancel();
        }
      },
      child: Container(
        height: mediaQuery.size.height,
        decoration: const BoxDecoration(
          color: AppColors.cardBackgroundBranco,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card superior (resumo)
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),

                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeMedicamento,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textVerde,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        label: 'Tipo',
                        value: tipoMedicamento,
                        color: AppColors.textVerde,
                      ),
                      _InfoRow(
                        label: 'Concentração',
                        value: concentracaoMedicamento,
                        color: AppColors.textVerde,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Card do tratamento atual
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackgroundVerde,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tratamento Atual',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textBranco,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          label: 'Dosagem',
                          value: '$dosagem $tipoMedicamento',
                          color: AppColors.textBranco,
                        ),
                        _InfoRow(
                          label: 'Frequência',
                          value: tratamento['frequencia'] ?? 'Não informada',
                          color: AppColors.textBranco,
                        ),
                        _InfoRow(
                          label: 'Início',
                          value:
                              tratamento['dataInicio'] != null
                                  ? DateFormat('dd/MM/yyyy').format(
                                    (tratamento['dataInicio'] as Timestamp)
                                        .toDate(),
                                  )
                                  : 'Não informado',
                          color: AppColors.textBranco,
                        ),
                        _InfoRow(
                          label: 'Término',
                          value:
                              tratamento['dataTermino'] != null
                                  ? DateFormat('dd/MM/yyyy').format(
                                    (tratamento['dataTermino'] as Timestamp)
                                        .toDate(),
                                  )
                                  : 'Não informado',
                          color: AppColors.textBranco,
                        ),
                        _InfoRow(
                          label: 'Status',
                          value: tratamento['status'] ?? 'Não informado',
                          color: AppColors.textBranco,
                        ),
                        if ((tratamento['observacoes'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Observações',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textBranco,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tratamento['observacoes'],
                            style: const TextStyle(color: AppColors.textBranco),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundVerde,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackgroundBranco,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estoque',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textVerde,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          label: 'Quantidade',
                          value:
                              estoque != null
                                  ? '${estoque['qtdAtual'].toString()} ${tipoMedicamento}'
                                  : '',
                          color: AppColors.textVerde,
                        ),
                        _InfoRow(
                          label: 'Avisar em',
                          value:
                              estoque != null
                                  ? '${estoque['qtdMinima'].toString()} ${tipoMedicamento}'
                                  : '',
                          color: AppColors.textVerde,
                        ),
                        _InfoRow(
                          label: 'Validade',
                          value:
                              estoque != null
                                  ? DateFormat('dd/MM/yyyy').format(
                                    (estoque['dataValidade'] as Timestamp)
                                        .toDate(),
                                  )
                                  : '-',
                          color: AppColors.textVerde,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackgroundVerde,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.botoesBrancos,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: () {
                              onCancel();

                            },
                            child: Text(
                              'Editar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textVerde,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.botoesBrancos,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: () {
                              onCancel();
                            },
                            child: Text(
                              'Concluir Tratamento',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textVerde,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.botoesBrancos,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: () {
                              onCancel();
                            },
                            child: Text(
                              'Compartilhar com Cuidador',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textVerde,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 160,
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(color: color),
                  textAlign: TextAlign.right,
                  softWrap: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
