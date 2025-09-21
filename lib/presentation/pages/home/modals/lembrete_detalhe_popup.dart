import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';

class LembreteDetalhePopup {
  static void show({
    required BuildContext context,
    required String nome,
    required String dose,
    required String horario,
    required String data,
    required String observacao,
    required VoidCallback onTomar,
    required void Function(DateTime novoHorario) onAdiar,
    required VoidCallback onPular,
    VoidCallback? onVerDetalhe,
  }) {
    final usuarioProvider = Provider.of<UsuarioProvider>(
      context,
      listen: false,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Hora do seu remédio!",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textVerde,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLinha("Nome", nome),
                    _buildLinha("Dose", dose),
                    _buildLinha("Horário previsto", horario),
                    _buildLinha("Observação", observacao),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onVerDetalhe,
                      child: const Text(
                        "Ver detalhe do medicamento",
                        style: TextStyle(
                          color: AppColors.textVerde,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    if (usuarioProvider.isContextoSouEu) ...[
                      const SizedBox(height: 20),
                      _buildBotaoPrincipal(
                        "Tomei",
                        AppColors.botoesVerdes,
                        onTomar,
                      ),
                    ],
                    if ((!usuarioProvider.isContextoSouEu &&
                        !usuarioProvider.isPacienteComVisualizacao)|| usuarioProvider.isContextoSouEu) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildBotaoSecundario(
                              "Adiar",
                              AppColors.botoesCinza,
                              () async {
                                final DateTime? novaData = await showDatePicker(
                                  context: context,
                                  initialDate: DateFormat(
                                    'dd/MM/yyyy',
                                  ).parse(data),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );

                                if (novaData == null) return;

                                final TimeOfDay? novoHorario =
                                    await showTimePicker(
                                      context: context,
                                      initialTime: _parseTimeOfDay(horario),
                                    );

                                if (novoHorario == null) return;

                                final DateTime novaDataHora = DateTime(
                                  novaData.year,
                                  novaData.month,
                                  novaData.day,
                                  novoHorario.hour,
                                  novoHorario.minute,
                                );

                                onAdiar(novaDataHora);
                              },
                            ),
                          ),

                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildBotaoSecundario(
                              "Pular",
                              AppColors.botoesVermelho,
                              onPular,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _buildLinha(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            "$titulo: ",
            style: const TextStyle(
              color: AppColors.textVerde,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }

  static Widget _buildBotaoPrincipal(
    String texto,
    Color cor,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: cor,
          foregroundColor: AppColors.textBranco,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        onPressed: onPressed,
        child: Text(texto),
      ),
    );
  }

  static Widget _buildBotaoSecundario(
    String texto,
    Color cor,
    VoidCallback onPressed,
  ) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: AppColors.textBranco,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onPressed,
      child: Text(texto),
    );
  }

  static TimeOfDay _parseTimeOfDay(String horario) {
    final partes = horario.split(':');
    final hora = int.tryParse(partes[0]) ?? 0;
    final minuto = int.tryParse(partes[1]) ?? 0;
    return TimeOfDay(hour: hora, minute: minuto);
  }
}
