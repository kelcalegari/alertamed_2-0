import 'package:flutter/material.dart';
import '../../../../shared/widgets/custom_seletor_field.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../themes/app_colors.dart';

class FormularioTratamento extends StatefulWidget {
  final GlobalKey<FormState> formKeyIndexUm;
  final TextEditingController nameMedicamentoCtrl;
  final TextEditingController nameDosagemCtrl;
  final String? selectedTipo;
  final List<String> vectorTipo;
  final String? selectedUnidadesMedida;
  final List<String> vectorUnidadesMedida;
  final String? selectedTipoTratamento;
  final List<String> vectorTipoTratamento;
  final String? selectedTipoFrequencia;
  final List<String> vectorTipoFrequencia;

  final void Function(String?) onTipoChanged;
  final void Function(String?) onUnidadesMedidaChanged;
  final void Function(String?) onTipoTratamentoChanged;
  final void Function(String?) onTipoFrequenciaChanged;

  const FormularioTratamento({
    super.key,
    required this.formKeyIndexUm,
    required this.nameMedicamentoCtrl,
    required this.nameDosagemCtrl,
    required this.selectedTipo,
    required this.vectorTipo,
    required this.selectedUnidadesMedida,
    required this.vectorUnidadesMedida,
    required this.selectedTipoTratamento,
    required this.vectorTipoTratamento,
    required this.selectedTipoFrequencia,
    required this.vectorTipoFrequencia,
    required this.onTipoChanged,
    required this.onUnidadesMedidaChanged,
    required this.onTipoTratamentoChanged,
    required this.onTipoFrequenciaChanged,
  });

  @override
  State<FormularioTratamento> createState() => _FormularioTratamentoState();
}

class _FormularioTratamentoState extends State<FormularioTratamento> {
  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKeyIndexUm,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Adicionar Novo Tratamento",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              ctrl: widget.nameMedicamentoCtrl,
              label: "Nome do Medicamento",
              hint: "Digite o nome",
              pad: 0,
              textInputType: TextInputType.text,
              validador: (value) =>
              value == null || value.trim().isEmpty
                  ? "Informe o nome do medicamento"
                  : null,
            ),
            const SizedBox(height: 12),
            CustomSelectorField<String>(
              selectedValue: widget.selectedTipo,
              items: widget.vectorTipo
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: widget.onTipoChanged,
              label: "Tipo de Medicação",
              hint: widget.vectorTipo[0],
              pad: 0,
              validador: (value) =>
              value == null ? "Informe o tipo da medicação" : null,
            ),
            Row(
              children: [
                Flexible(
                  flex: 3,
                  child: CustomTextField(
                    pad: 0,
                    ctrl: widget.nameDosagemCtrl,
                    label: "Dosagem",
                    textInputType: TextInputType.number,
                    hint: "1",
                    validador: (value) =>
                    value == null || value.trim().isEmpty
                        ? "Informe a dosagem"
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  flex: 2,
                  child: CustomSelectorField<String>(
                    selectedValue: widget.selectedUnidadesMedida,
                    items: widget.vectorUnidadesMedida
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: widget.onUnidadesMedidaChanged,
                    hint: widget.vectorUnidadesMedida[0],
                    pad: 0,
                    validador: (value) =>
                    value == null ? "Informe a Unidade de Medida" : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CustomSelectorField<String>(
              selectedValue: widget.selectedTipoTratamento,
              items: widget.vectorTipoTratamento
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: widget.onTipoTratamentoChanged,
              label: "Tipo de Tratamento",
              hint: widget.vectorTipoTratamento[0],
              pad: 10,
              validador: (value) =>
              value == null ? "Informe o tipo do tratamento" : null,
            ),
            const SizedBox(height: 12),
            CustomSelectorField<String>(
              selectedValue: widget.selectedTipoFrequencia,
              items: widget.vectorTipoFrequencia
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: widget.onTipoFrequenciaChanged,
              label: "Tipo de Frequência",
              hint: widget.vectorTipoFrequencia[0],
              pad: 10,
              validador: (value) =>
              value == null ? "Informe o tipo da frequência" : null,
            ),
            const SizedBox(height: 16),

          ],
        ),
      ),
    );
  }
}
