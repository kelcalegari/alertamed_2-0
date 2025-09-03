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

  // NOVO: decide qual layout mostrar
  final String selectedTipoFrequencia;

  // OPCIONAL: expõe os horários fixos como strings "HH:mm"
  final void Function(List<String> horariosFixos)? onHorariosFixosChanged;
  final void Function(List<String> refeicoesSelecionadas)? onRefeicoesChanged;
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
    required this.selectedTipoFrequencia,

    this.onHorariosFixosChanged,
    this.onRefeicoesChanged,
  });

  @override
  State<AgendamentoTratamento> createState() => _AgendamentoTratamentoState();
}

class _AgendamentoTratamentoState extends State<AgendamentoTratamento> {
  // ---- Estado para Horários Fixos ----
  final _qtdDosesDiaCtrl = TextEditingController(text: "1");
  final List<TextEditingController> _horariosCtrls = [TextEditingController()];

  // ---- Estado para Refeições ----
  // (usamos strings canônicas: 'cafe', 'almoco', 'jantar')
  final Set<String> _refeicoesSelecionadas = {};
  @override
  void dispose() {
    _qtdDosesDiaCtrl.dispose();
    for (final c in _horariosCtrls) c.dispose();
    super.dispose();
  }

  void _sincronizarQtdDoses(int qtd) {
    // garante o mesmo tamanho da lista de controllers
    if (qtd < 1) qtd = 1;
    if (qtd > _horariosCtrls.length) {
      final diff = qtd - _horariosCtrls.length;
      for (int i = 0; i < diff; i++) {
        _horariosCtrls.add(TextEditingController());
      }
    } else if (qtd < _horariosCtrls.length) {
      for (var i = _horariosCtrls.length - 1; i >= qtd; i--) {
        _horariosCtrls[i].dispose();
        _horariosCtrls.removeAt(i);
      }
    }
    setState(() {});
    _emitHorariosFixos();
  }

  void _emitHorariosFixos() {
    if (widget.onHorariosFixosChanged == null) return;
    final list =
        _horariosCtrls
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();
    widget.onHorariosFixosChanged!(list);
    setState(() {});
  }

  String? _validaTodosHorariosPreenchidos() {
    if (widget.selectedTipoFrequencia != 'Horários Fixos') return null;
    for (final c in _horariosCtrls) {
      if (c.text.trim().isEmpty) return "Preencha todos os horários das doses";
    }
    // (Opcional) checa duplicados
    final set = <String>{};
    for (final c in _horariosCtrls) {
      final t = c.text.trim();
      if (set.contains(t)) return "Existem horários duplicados";
      set.add(t);
    }
    return null;
  }

  // ---------------- Refeições ----------------
  void _toggleRefeicao(String key) {
    if (_refeicoesSelecionadas.contains(key)) {
      _refeicoesSelecionadas.remove(key);
    } else {
      _refeicoesSelecionadas.add(key);
    }
    setState(() {});
    _emitRefeicoesSelecionadas();
  }

  void _emitRefeicoesSelecionadas() {
    if (widget.onRefeicoesChanged == null) return;
    widget.onRefeicoesChanged!(_refeicoesSelecionadas.toList());
  }

  String? _validaRefeicoes() {
    if (widget.selectedTipoFrequencia != 'Junto com Refeições') return null;
    if (_refeicoesSelecionadas.isEmpty) {
      return "Selecione ao menos uma refeição";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isFixos = widget.selectedTipoFrequencia == 'Horários Fixos';
    final isRefeicao = widget.selectedTipoFrequencia == 'Junto com Refeições';
    return Form(
      key: widget.formKeyIndexDois,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFixos
                  ? "Agendamento (Horários Fixos)"
                  : isRefeicao
                  ? "Agendamento (Junto com Refeições)"
                  : "Agendamento do Tratamento",
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 16),

            // ===================== MODO INTERVALOS FIXOS =====================
            if (!isFixos && !isRefeicao) ...[
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
                      validador:
                          (v) =>
                              !isFixos
                                  ? (v == null || v.trim().isEmpty
                                      ? "Informe a frequência"
                                      : null)
                                  : null,
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
                      validador:
                          (v) =>
                              !isFixos
                                  ? (v == null || v.trim().isEmpty
                                      ? "Informe a quantidade"
                                      : null)
                                  : null,
                    ),
                  ),
                  Flexible(
                    flex: 4,
                    child: CustomSelectorField<String>(
                      selectedValue: widget.selectedUnidadesMedidaLembrete,
                      items:
                          widget.vectorUnidadesMedidaLembrete
                              .map(
                                (g) =>
                                    DropdownMenuItem(value: g, child: Text(g)),
                              )
                              .toList(),
                      onChanged: widget.onSelectedUnidadesMedidaLembreteChanged,
                      hint: widget.vectorUnidadesMedidaLembrete[0],
                      pad: 0,
                      validador:
                          (v) =>
                              !isFixos
                                  ? (v == null
                                      ? "Informe a Unidade de Medida"
                                      : null)
                                  : null,
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
                      validador:
                          (v) =>
                              !isFixos
                                  ? (v == null || v.trim().isEmpty
                                      ? "Informe a quantidade total"
                                      : null)
                                  : null,
                    ),
                  ),
                  Flexible(
                    flex: 3,
                    child: CustomSelectorField<String>(
                      selectedValue: widget.selectedUnidadesMedidaLembrete,
                      items:
                          widget.vectorUnidadesMedidaLembrete
                              .map(
                                (g) =>
                                    DropdownMenuItem(value: g, child: Text(g)),
                              )
                              .toList(),
                      onChanged: widget.onSelectedUnidadesMedidaLembreteChanged,
                      hint: widget.vectorUnidadesMedidaLembrete[0],
                      pad: 0,
                      validador:
                          (v) =>
                              !isFixos
                                  ? (v == null
                                      ? "Informe a Unidade de Medida"
                                      : null)
                                  : null,
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
                      hint: "08:00",
                      pad: 0,
                      textInputType: TextInputType.text,
                      icon: Icons.access_time,
                      isTime: true,
                      validador: (v) {
                        if (isFixos) return null; // não valida nesse caso

                        if (v == null || v.trim().isEmpty) {
                          return "Informe a hora da primeira dose";
                        }

                        try {
                          final partes = v.split(":");
                          if (partes.length != 2)
                            return "Formato inválido (use HH:mm)";

                          final hora = int.parse(partes[0]);
                          final minuto = int.parse(partes[1]);

                          final agora = DateTime.now();
                          final horaInformada = DateTime(
                            agora.year,
                            agora.month,
                            agora.day,
                            hora,
                            minuto,
                          );

                          final limite = agora.add(const Duration(minutes: 10));

                          if (horaInformada.isBefore(limite)) {
                            return "A primeira dose deve ser pelo menos 10 minutos após agora";
                          }
                        } catch (e) {
                          return "Hora inválida";
                        }

                        return null;
                      },
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
                      validador:
                          (v) =>
                              !isFixos
                                  ? (v == null || v.trim().isEmpty
                                      ? "Informe a data da primeira dose"
                                      : null)
                                  : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                validador:
                    (v) =>
                        !isFixos
                            ? (v == null || v.trim().isEmpty
                                ? "Informe a data do fim do tratamento"
                                : null)
                            : null,
              ),
            ],

            // ===================== MODO HORÁRIOS FIXOS =====================
            if (isFixos) ...[
              Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: CustomTextField(
                      pad: 0,
                      ctrl: _qtdDosesDiaCtrl,
                      label: "Doses por dia",
                      textInputType: TextInputType.number,
                      hint: "3",
                      validador:
                          (v) =>
                              isFixos
                                  ? (v == null || v.trim().isEmpty
                                      ? "Informe a quantidade de doses"
                                      : null)
                                  : null,
                      onComplete: () {
                        final qtd =
                            int.tryParse(_qtdDosesDiaCtrl.text.trim()) ?? 1;
                        _sincronizarQtdDoses(qtd);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 3,
                    child: CustomTextField(
                      pad: 0,
                      ctrl: widget.qtdMedicamentoCtrl,
                      label: "Qtd por dose",
                      textInputType: TextInputType.number,
                      hint: "1",
                      validador:
                          (v) =>
                              isFixos
                                  ? (v == null || v.trim().isEmpty
                                      ? "Informe a quantidade por dose"
                                      : null)
                                  : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 4,
                    child: CustomSelectorField<String>(
                      selectedValue: widget.selectedUnidadesMedidaLembrete,
                      items:
                          widget.vectorUnidadesMedidaLembrete
                              .map(
                                (g) =>
                                    DropdownMenuItem(value: g, child: Text(g)),
                              )
                              .toList(),
                      onChanged: widget.onSelectedUnidadesMedidaLembreteChanged,
                      hint: widget.vectorUnidadesMedidaLembrete[0],
                      pad: 0,
                      validador:
                          (v) =>
                              isFixos
                                  ? (v == null
                                      ? "Informe a Unidade de Medida"
                                      : null)
                                  : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Lista dinâmica de horários
              const Text(
                "Horários das doses",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textVerde,
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(_horariosCtrls.length, (i) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: i == _horariosCtrls.length - 1 ? 0 : 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          ctrl: _horariosCtrls[i],
                          label: "Dose ${i + 1}",
                          hint: "08:00",
                          pad: 0,
                          isTime: true,
                          textInputType: TextInputType.text,
                          icon: Icons.access_time,
                          validador: (_) => _validaTodosHorariosPreenchidos(),
                          onComplete: _emitHorariosFixos,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Remover horário',
                        onPressed:
                            _horariosCtrls.length > 1
                                ? () {
                                  _horariosCtrls.removeAt(i).dispose();
                                  _qtdDosesDiaCtrl.text =
                                      _horariosCtrls.length.toString();
                                  setState(() {});
                                  _emitHorariosFixos();
                                }
                                : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      _horariosCtrls.add(TextEditingController());
                      _qtdDosesDiaCtrl.text = _horariosCtrls.length.toString();
                      setState(() {});
                      _emitHorariosFixos();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Adicionar horário"),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Período (mesmo do modo intervalos)
              const Text(
                "Período",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textVerde,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: CustomTextField(
                      ctrl: widget.dataInicialCtrl,
                      label: "Data inicial",
                      hint: "25/05/2025",
                      pad: 0,
                      textInputType: TextInputType.datetime,
                      validador:
                          (v) =>
                              isFixos
                                  ? (v == null || v.trim().isEmpty
                                      ? "Informe a data inicial"
                                      : null)
                                  : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: CustomTextField(
                      ctrl: widget.dataFinalCtrl,
                      label: "Data final",
                      hint: "25/06/2025",
                      pad: 0,
                      textInputType: TextInputType.datetime,
                      validador:
                          (v) =>
                              v == null || v.trim().isEmpty
                                  ? "Informe a data final"
                                  : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // (Opcional) total de medicamento para o período
              CustomTextField(
                pad: 0,
                ctrl: widget.qtdMedicamentoTotalCtrl,
                label: "Quantidade Total (período)",
                textInputType: TextInputType.number,
                hint: "30",
                validador:
                    (v) =>
                        isFixos
                            ? (v == null || v.trim().isEmpty
                                ? "Informe a quantidade total para o período"
                                : null)
                            : null,
              ),
            ],if (isRefeicao) ...[
              Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: CustomTextField(
                      pad: 0,
                      ctrl: widget.qtdMedicamentoCtrl,
                      label: "Qtd por dose",
                      textInputType: TextInputType.number,
                      hint: "1",
                      validador: (v) => isRefeicao
                          ? (v == null || v.trim().isEmpty
                          ? "Informe a quantidade por dose"
                          : null)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
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
                      validador: (v) => isRefeicao
                          ? (v == null ? "Informe a Unidade de Medida" : null)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Text(
                "Refeições",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textVerde,
                ),
              ),
              const SizedBox(height: 8),

              // Chips de seleção múltipla
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text("Café da manhã"),
                    selected: _refeicoesSelecionadas.contains('cafe'),
                    onSelected: (_) => _toggleRefeicao('cafe'),
                  ),
                  FilterChip(
                    label: const Text("Almoço"),
                    selected: _refeicoesSelecionadas.contains('almoco'),
                    onSelected: (_) => _toggleRefeicao('almoco'),
                  ),
                  FilterChip(
                    label: const Text("Jantar"),
                    selected: _refeicoesSelecionadas.contains('jantar'),
                    onSelected: (_) => _toggleRefeicao('jantar'),
                  ),
                ],
              ),

              // Mensagem de validação (inline)
              Builder(
                builder: (_) {
                  final err = _validaRefeicoes();
                  return err == null
                      ? const SizedBox.shrink()
                      : Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      err,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              const Text(
                "Período",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textVerde,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: CustomTextField(
                      ctrl: widget.dataInicialCtrl,
                      label: "Data inicial",
                      hint: "25/05/2025",
                      pad: 0,
                      textInputType: TextInputType.datetime,
                      validador: (v) => isRefeicao
                          ? (v == null || v.trim().isEmpty
                          ? "Informe a data inicial"
                          : null)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: CustomTextField(
                      ctrl: widget.dataFinalCtrl,
                      label: "Data final",
                      hint: "25/06/2025",
                      pad: 0,
                      textInputType: TextInputType.datetime,
                      validador: (v) =>
                      v == null || v.trim().isEmpty ? "Informe a data final" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              CustomTextField(
                pad: 0,
                ctrl: widget.qtdMedicamentoTotalCtrl,
                label: "Quantidade Total (período)",
                textInputType: TextInputType.number,
                hint: "30",
                validador: (v) => isRefeicao
                    ? (v == null || v.trim().isEmpty
                    ? "Informe a quantidade total para o período"
                    : null)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}