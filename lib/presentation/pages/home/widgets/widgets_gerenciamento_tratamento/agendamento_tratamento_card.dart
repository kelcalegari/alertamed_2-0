import 'package:flutter/material.dart';
import '../../../../shared/widgets/custom_seletor_field.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../themes/app_colors.dart';

class AgendamentoTratamento extends StatefulWidget {
  final GlobalKey<FormState> formKeyIndexDois;
  final TextEditingController frequenciaCtrl;
  final TextEditingController qtdMedicamentoCtrl;
  final TextEditingController qtdMedicamentoTotalCtrl;
  final TextEditingController horaInicialCtrl;
  final TextEditingController dataInicialCtrl;
  final TextEditingController dataFinalCtrl;
  final String? selectedUnidadesMedidaLembrete;
  final List<String> vectorUnidadesMedidaLembrete;
  final Function(String?) onSelectedUnidadesMedidaLembreteChanged;

  const AgendamentoTratamento({
    super.key,
    required this.formKeyIndexDois,
    required this.frequenciaCtrl,
    required this.qtdMedicamentoCtrl,
    required this.qtdMedicamentoTotalCtrl,
    required this.horaInicialCtrl,
    required this.dataInicialCtrl,
    required this.dataFinalCtrl,
    required this.selectedUnidadesMedidaLembrete,
    required this.vectorUnidadesMedidaLembrete,
    required this.onSelectedUnidadesMedidaLembreteChanged,
  });

  @override
  State<AgendamentoTratamento> createState() => _AgendamentoTratamentoState();
}

class _AgendamentoTratamentoState extends State<AgendamentoTratamento> {
  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKeyIndexDois,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Agendamento do Tratamento",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  flex: 4,
                  child: CustomTextField(
                    ctrl: widget.frequenciaCtrl,
                    label: "A cada",
                    hint: "8",
                    pad: 0,
                    textInputType: TextInputType.number,
                    icon: Icons.access_time,
                    validador: (value) =>
                    value == null || value.trim().isEmpty ? "Informe a frequência" : null,
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: CustomTextField(
                    pad: 0,
                    ctrl: widget.qtdMedicamentoCtrl,
                    label: "Quantidade",
                    textInputType: TextInputType.number,
                    hint: "1",
                    validador: (value) =>
                    value == null || value.trim().isEmpty ? "Informe a quantidade" : null,
                  ),
                ),
                Flexible(
                  flex: 4,
                  child: CustomSelectorField<String>(
                    selectedValue: widget.selectedUnidadesMedidaLembrete,
                    items: widget.vectorUnidadesMedidaLembrete
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: widget.onSelectedUnidadesMedidaLembreteChanged,
                    hint: widget.vectorUnidadesMedidaLembrete[0],
                    pad: 0,
                    validador: (value) =>
                    value == null ? "Informe a Unidade de Medida" : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Flexible(
                  flex: 5,
                  child: CustomTextField(
                    pad: 0,
                    ctrl: widget.qtdMedicamentoTotalCtrl,
                    label: "Quantidade Total",
                    textInputType: TextInputType.number,
                    hint: "1",
                    validador: (value) => value == null || value.trim().isEmpty
                        ? "Informe a quantidade total"
                        : null,
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: CustomSelectorField<String>(
                    selectedValue: widget.selectedUnidadesMedidaLembrete,
                    items: widget.vectorUnidadesMedidaLembrete
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: widget.onSelectedUnidadesMedidaLembreteChanged,
                    hint: widget.vectorUnidadesMedidaLembrete[0],
                    pad: 0,
                    validador: (value) =>
                    value == null ? "Informe a Unidade de Medida" : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              "Inicio",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Flexible(
                  flex: 4,
                  child: CustomTextField(
                    ctrl: widget.horaInicialCtrl,
                    label: "Hora",
                    hint: "8:00",
                    pad: 0,
                    textInputType: TextInputType.text,
                    icon: Icons.access_time,
                    isTime: true,
                    validador: (value) => value == null || value.trim().isEmpty
                        ? "Informe a hora da primeira dose"
                        : null,
                  ),
                ),
                Flexible(
                  flex: 5,
                  child: CustomTextField(
                    ctrl: widget.dataInicialCtrl,
                    label: "Data",
                    hint: "25/05/2025",
                    pad: 0,
                    textInputType: TextInputType.datetime,
                    validador: (value) => value == null || value.trim().isEmpty
                        ? "Informe a data da primeira dose"
                        : null,
                  ),
                ),
              ],
            ),
            const Text(
              "Termino",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textVerde,
              ),
            ),
            CustomTextField(
              ctrl: widget.dataFinalCtrl,
              label: "Data",
              hint: "25/05/2025",
              pad: 0,
              textInputType: TextInputType.text,
              validador: (value) => value == null || value.trim().isEmpty
                  ? "Informe a data do fim do tratamento"
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
