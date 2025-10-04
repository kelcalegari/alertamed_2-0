import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/custom_seletor_field.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../themes/app_colors.dart';

class InformacoesAdicionais extends StatefulWidget {
  final GlobalKey<FormState> formKeyIndexTres;
  final TextEditingController qtdMedicamentoEstoqueCtrl;
  final TextEditingController qtdEstoqueMinimoCtrl;
  final TextEditingController dataValidadeCtrl;
  final TextEditingController observacaoCtrl;
  final String? selectedUnidadesMedida;
  final List<String> vectorUnidadesMedida;
  final String? selectedCompartilharTratamento;
  final List<String> vectorCompartilharTratamento;
  final VoidCallback onConcluir;
  final ValueChanged<String?> onUnidadesMedidaChanged;
  final ValueChanged<String?> onCompartilharTratamentoChanged;

  /// Agora assíncrono para podermos aguardar e mostrar o loading no botão
  final Future<void> Function()? onPressedSalvar;

  const InformacoesAdicionais({
    Key? key,
    required this.formKeyIndexTres,
    required this.qtdMedicamentoEstoqueCtrl,
    required this.qtdEstoqueMinimoCtrl,
    required this.dataValidadeCtrl,
    required this.observacaoCtrl,
    required this.selectedUnidadesMedida,
    required this.vectorUnidadesMedida,
    required this.selectedCompartilharTratamento,
    required this.vectorCompartilharTratamento,
    required this.onConcluir,
    required this.onUnidadesMedidaChanged,
    required this.onCompartilharTratamentoChanged,
    required this.onPressedSalvar,
  }) : super(key: key);

  @override
  State<InformacoesAdicionais> createState() => _InformacoesAdicionaisState();
}

class _InformacoesAdicionaisState extends State<InformacoesAdicionais> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKeyIndexTres,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Informações Adicionais",
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Estoque",
              style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Flexible(
                  flex: 3,
                  child: CustomTextField(
                    pad: 0,
                    ctrl: widget.qtdMedicamentoEstoqueCtrl,
                    label: "Quantidade",
                    textInputType: TextInputType.number,
                    hint: "1",
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: CustomTextField(
                    pad: 0,
                    ctrl: widget.qtdEstoqueMinimoCtrl,
                    label: "Avisar em",
                    textInputType: TextInputType.number,
                    hint: "1",
                  ),
                ),
                Flexible(
                  flex: 4,
                  child: CustomSelectorField<String>(
                    selectedValue: widget.selectedUnidadesMedida,
                    items: widget.vectorUnidadesMedida
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: widget.onUnidadesMedidaChanged,
                    hint: widget.vectorUnidadesMedida.isNotEmpty ? widget.vectorUnidadesMedida[0] : "unidade",
                    pad: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CustomTextField(
              ctrl: widget.dataValidadeCtrl,
              label: "Validade",
              hint: "25/05/2026",
              pad: 0,
              textInputType: TextInputType.datetime,
              icon: Icons.calendar_month,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              ctrl: widget.observacaoCtrl,
              label: "Observação",
              hint: "",
              pad: 0,
              textInputType: TextInputType.multiline,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.botoesVerdes,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _isSaving
                    ? null
                    : () async {
                  // (opcional) validar form antes
                  // final ok = widget.formKeyIndexTres.currentState?.validate() ?? true;
                  // if (!ok) return;

                  setState(() => _isSaving = true);
                  try {
                    if (widget.onPressedSalvar != null) {
                      await widget.onPressedSalvar!();
                    }
                    // quem decide chamar onConcluir é a tela pai;
                    // se quiser concluir aqui, descomente:
                    // widget.onConcluir();
                  } catch (e) {
                    // apresente feedback se quiser
                    // ScaffoldMessenger.of(context).showSnackBar(
                    //   const SnackBar(content: Text('Erro ao salvar')),
                    // );
                    rethrow;
                  } finally {
                    if (mounted) setState(() => _isSaving = false);
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _isSaving
                      ? Row(
                    key: const ValueKey('saving'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text("Salvando…", style: TextStyle(color: AppColors.textBranco)),
                    ],
                  )
                      : const Text(
                    "Salvar",
                    key: ValueKey('save'),
                    style: TextStyle(color: AppColors.textBranco),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
