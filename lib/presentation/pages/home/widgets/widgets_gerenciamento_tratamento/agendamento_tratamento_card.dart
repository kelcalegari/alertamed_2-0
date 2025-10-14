import 'package:flutter/material.dart';
import '../../../../shared/widgets/custom_seletor_field.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../themes/app_colors.dart';

String? atLeastOneFilled({
  required String aValue,
  required String bValue,
  required String msg,
}) {
  final hasA = aValue.trim().isNotEmpty;
  final hasB = bValue.trim().isNotEmpty;
  if (!hasA && !hasB) return msg;
  return null;
}

class AgendamentoTratamento extends StatefulWidget {
  final GlobalKey<FormState> formKeyIndexDois;
  final TextEditingController frequenciaCtrl;
  final TextEditingController qtdMedicamentoCtrl;
  final TextEditingController qtdMedicamentoTotalCtrl;
  final TextEditingController horaInicialCtrl;
  final TextEditingController dataInicialCtrl;
  final TextEditingController dataFinalCtrl;

  /// Decide o layout principal
  final String
  selectedTipoFrequencia; // 'Intervalos Fixos' | 'Horários Fixos' | 'Junto com Refeições'
  final String
  selectedTipoTratamento; // 'Tratamento Determinado' | 'Tratamento Contínuo' | 'Tratamento Dose única'

  /// Callbacks opcionais
  final void Function(List<String> horariosFixos)?
  onHorariosFixosChanged; // 'HH:mm'
  final void Function(List<String> refeicoesSelecionadas)?
  onRefeicoesChanged; // 'cafe' | 'almoco' | 'jantar'

  const AgendamentoTratamento({
    super.key,
    required this.formKeyIndexDois,
    required this.frequenciaCtrl,
    required this.qtdMedicamentoCtrl,
    required this.qtdMedicamentoTotalCtrl,
    required this.horaInicialCtrl,
    required this.dataInicialCtrl,
    required this.dataFinalCtrl,
    required this.selectedTipoFrequencia,
    required this.selectedTipoTratamento,
    this.onHorariosFixosChanged,
    this.onRefeicoesChanged,
  });

  @override
  State<AgendamentoTratamento> createState() => _AgendamentoTratamentoState();
}

class _AgendamentoTratamentoState extends State<AgendamentoTratamento> {
  // ---- Estado para Horários Fixos ----
  final _qtdDosesDiaCtrl = TextEditingController(text: '1');
  final List<TextEditingController> _horariosCtrls = [TextEditingController()];

  // ---- Estado para Refeições ----
  final Set<String> _refeicoesSelecionadas =
      <String>{}; // 'cafe'|'almoco'|'jantar'

  // ===================== Lifecycle =====================
  @override
  void dispose() {
    _qtdDosesDiaCtrl.dispose();
    for (final c in _horariosCtrls) c.dispose();
    super.dispose();
  }

  // ===================== Helpers =====================
  bool get _isFixos => widget.selectedTipoFrequencia == 'Horários Fixos';
  bool get _isRefeicao =>
      widget.selectedTipoFrequencia == 'Junto com Refeições';
  bool get _isDeterminado =>
      widget.selectedTipoTratamento == 'Tratamento Determinado';
  bool get _isContinuo =>
      widget.selectedTipoTratamento == 'Tratamento Contínuo';
  bool get _isDoseUnica =>
      widget.selectedTipoTratamento == 'Tratamento Dose única';

  void _emitHorariosFixos() {
    if (widget.onHorariosFixosChanged == null) return;
    final list = _horariosCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    widget.onHorariosFixosChanged!(list);
  }

  void _sincronizarQtdDoses(int qtd) {
    qtd = qtd.clamp(1, 50); // guarda-chuva
    final diff = qtd - _horariosCtrls.length;

    if (diff > 0) {
      for (int i = 0; i < diff; i++) {
        _horariosCtrls.add(TextEditingController());
      }
    } else if (diff < 0) {
      for (var i = 0; i < -diff; i++) {
        final last = _horariosCtrls.removeLast();
        last.dispose();
      }
    }
    setState(() {});
    _emitHorariosFixos();
  }

  // ---------------- Refeições ----------------
  void _toggleRefeicao(String key) {
    if (_isDoseUnica) {
      _refeicoesSelecionadas
        ..clear()
        ..add(key);
    } else {
      if (_refeicoesSelecionadas.contains(key)) {
        _refeicoesSelecionadas.remove(key);
      } else {
        _refeicoesSelecionadas.add(key);
      }
    }
    setState(() {});
    _emitRefeicoesSelecionadas();
  }

  void _emitRefeicoesSelecionadas() {
    if (widget.onRefeicoesChanged == null) return;
    widget.onRefeicoesChanged!(_refeicoesSelecionadas.toList(growable: false));
  }

  String? _validaRefeicoes() {
    if (!_isRefeicao) return null;
    if (_refeicoesSelecionadas.isEmpty)
      return 'Selecione ao menos uma refeição';
    return null;
  }

  // ===================== Build =====================
  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.formKeyIndexDois,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              title:
                  _isFixos
                      ? 'Agendamento (Horários Fixos)'
                      : _isRefeicao
                      ? 'Agendamento (Junto com Refeições)'
                      : 'Agendamento do Tratamento',
            ),
            const SizedBox(height: 16),

            // ===================== INTERVALOS FIXOS =====================
            if (!_isFixos && !_isRefeicao)
              _IntervalosFixos(
                isDoseUnica: _isDoseUnica,
                isDeterminado: _isDeterminado,
                frequenciaCtrl: widget.frequenciaCtrl,
                qtdMedicamentoCtrl: widget.qtdMedicamentoCtrl,
                qtdMedicamentoTotalCtrl: widget.qtdMedicamentoTotalCtrl,
                horaInicialCtrl: widget.horaInicialCtrl,
                dataInicialCtrl: widget.dataInicialCtrl,
                dataFinalCtrl: widget.dataFinalCtrl,
              ),

            // ===================== HORÁRIOS FIXOS =====================
            if (_isFixos)
              _HorariosFixos(
                isDoseUnica: _isDoseUnica,
                isDeterminado: _isDeterminado,
                qtdDosesDiaCtrl: _qtdDosesDiaCtrl,
                horariosCtrls: _horariosCtrls,
                qtdMedicamentoCtrl: widget.qtdMedicamentoCtrl,
                dataInicialCtrl: widget.dataInicialCtrl,
                dataFinalCtrl: widget.dataFinalCtrl,
                onChangeQtdDoses: (q) => _sincronizarQtdDoses(q),
                onEmitHorarios: _emitHorariosFixos,
              ),

            // ===================== REFEIÇÕES =====================
            if (_isRefeicao)
              _Refeicoes(
                isDeterminado: _isDeterminado,
                qtdMedicamentoCtrl: widget.qtdMedicamentoCtrl,
                dataInicialCtrl: widget.dataInicialCtrl,
                dataFinalCtrl: widget.dataFinalCtrl,
                selected: _refeicoesSelecionadas,
                onToggle: _toggleRefeicao,
                errorText: _validaRefeicoes(),
                qtdTotalCtrl: widget.qtdMedicamentoTotalCtrl,
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// Sub-widgets
// =============================================================

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: AppColors.textVerde,
      ),
    );
  }
}

class _IntervalosFixos extends StatelessWidget {
  final bool isDoseUnica;
  final bool isDeterminado;
  final TextEditingController frequenciaCtrl;
  final TextEditingController qtdMedicamentoCtrl;
  final TextEditingController qtdMedicamentoTotalCtrl;
  final TextEditingController horaInicialCtrl;
  final TextEditingController dataInicialCtrl;
  final TextEditingController dataFinalCtrl;

  const _IntervalosFixos({
    required this.isDoseUnica,
    required this.isDeterminado,
    required this.frequenciaCtrl,
    required this.qtdMedicamentoCtrl,
    required this.qtdMedicamentoTotalCtrl,
    required this.horaInicialCtrl,
    required this.dataInicialCtrl,
    required this.dataFinalCtrl,
  });

  // Helpers
  int? _toInt(String? s) {
    if (s == null) return null;
    final v = s.trim();
    if (v.isEmpty) return null;
    return int.tryParse(v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isDoseUnica)
          Row(
            children: [
              Flexible(
                flex: 4,
                child: CustomTextField(
                  ctrl: frequenciaCtrl,
                  label: 'A cada',
                  hint: '8',
                  pad: 0,
                  textInputType: TextInputType.number,
                  icon: Icons.access_time,
                  validador:
                      (v) =>
                          (isDeterminado || !isDoseUnica)
                              ? (v == null || v.trim().isEmpty
                                  ? 'Informe a frequência'
                                  : null)
                              : null,
                ),
              ),
              Flexible(
                flex: 3,
                child: CustomTextField(
                  pad: 0,
                  ctrl: qtdMedicamentoCtrl,
                  label: 'Qtd por dose',
                  textInputType: TextInputType.number,
                  hint: '1',
                  validador: (v) {
                    final dose = _toInt(v);
                    if (dose == null || dose <= 0) {
                      return 'Informe uma quantidade por dose válida';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        if (isDeterminado) ...[
          const SizedBox(height: 20),
          CustomTextField(
            pad: 0,
            ctrl: qtdMedicamentoTotalCtrl,
            label: 'Quantidade Total',
            textInputType: TextInputType.number,
            hint: '1',
            validador: (v) {
              // Regra "ao menos um": Data final OU Quantidade total
              final base = atLeastOneFilled(
                aValue: v ?? '',
                bValue: dataFinalCtrl.text,
                msg: 'Informe a data final ou a quantidade total',
              );
              if (base != null) return base; // se ambos vazios, retorna aqui

              // Se quantidade total estiver preenchida, valida as regras extras
              final total = _toInt(v);
              if (total != null) {
                // precisa de Qtd por dose válida
                final porDose = _toInt(qtdMedicamentoCtrl.text);
                if (porDose == null || porDose <= 0) {
                  return 'Informe primeiro uma "Qtd por dose" válida';
                }
                if (total <= 0) {
                  return 'Quantidade total deve ser maior que 0';
                }
                if (total < porDose) {
                  return 'Quantidade total deve ser maior ou igual que a Qtd por dose';
                }
                if (total % porDose != 0) {
                  return 'Quantidade total deve ser múltiplo da Qtd por dose';
                }
              }
              return null;
            },
          ),
        ],
        if (!isDoseUnica)
          const Text(
            'Inicio',
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
                ctrl: horaInicialCtrl,
                label: 'Hora',
                hint: '08:00',
                pad: 0,
                textInputType: TextInputType.text,
                icon: Icons.access_time,
                isTime: true,
                validador: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Informe a hora da primeira dose';
                  }
                  try {
                    final partes = v.split(':');
                    if (partes.length != 2)
                      return 'Formato inválido (use HH:mm)';
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
                    final limite = agora.add(const Duration(minutes: 1));
                    if (horaInformada.isBefore(limite)) {
                      return 'A primeira dose deve ser pelo menos 1 minutos após agora';
                    }
                  } catch (_) {
                    return 'Hora inválida';
                  }
                  return null;
                },
              ),
            ),
            Flexible(
              flex: 5,
              child: CustomTextField(
                ctrl: dataInicialCtrl,
                label: 'Data',
                hint: '25/05/2025',
                pad: 0,
                textInputType: TextInputType.datetime,
                validador:
                    (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Informe a data da primeira dose'
                            : null,
              ),
            ),
          ],
        ),
        if (isDeterminado) ...[
          const Text(
            'Fim',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textVerde,
            ),
          ),
          CustomTextField(
            ctrl: dataFinalCtrl,
            label: 'Data',
            hint: '25/06/2025',
            pad: 0,
            textInputType: TextInputType.text,
            validador: (v) {
              // mantém a mesma regra de "ao menos um"
              final res = atLeastOneFilled(
                aValue: v ?? '',
                bValue: qtdMedicamentoTotalCtrl.text,
                msg: 'Informe a data final ou a quantidade total',
              );
              return res;
            },
          ),
        ],
      ],
    );
  }
}

class _HorariosFixos extends StatelessWidget {
  final bool isDoseUnica;
  final bool isDeterminado;
  final TextEditingController qtdDosesDiaCtrl;
  final List<TextEditingController> horariosCtrls;
  final TextEditingController qtdMedicamentoCtrl;
  final TextEditingController dataInicialCtrl;
  final TextEditingController dataFinalCtrl;
  final void Function(int qtd) onChangeQtdDoses;
  final VoidCallback onEmitHorarios;

  const _HorariosFixos({
    required this.isDoseUnica,
    required this.isDeterminado,
    required this.qtdDosesDiaCtrl,
    required this.horariosCtrls,
    required this.qtdMedicamentoCtrl,
    required this.dataInicialCtrl,
    required this.dataFinalCtrl,
    required this.onChangeQtdDoses,
    required this.onEmitHorarios,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isDoseUnica)
          CustomTextField(
            pad: 0,
            ctrl: qtdMedicamentoCtrl,
            label: 'Quantidade por dose',
            textInputType: TextInputType.number,
            hint: '1',
            validador:
                (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Informe a quantidade por dose'
                        : null,
          ),
        if (!isDoseUnica) ...[
          const SizedBox(height: 16),
          const Text(
            'Horários das doses',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textVerde,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(horariosCtrls.length, (i) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: i == horariosCtrls.length - 1 ? 0 : 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      ctrl: horariosCtrls[i],
                      label: 'Dose ${i + 1}',
                      hint: '08:00',
                      pad: 0,
                      isTime: true,
                      textInputType: TextInputType.text,
                      icon: Icons.access_time,
                      validador: (v) {
                        for (final c in horariosCtrls) {
                          if (c.text.trim().isEmpty)
                            return 'Preencha todos os horários das doses';
                        }
                        final set = <String>{};
                        for (final c in horariosCtrls) {
                          final t = c.text.trim();
                          if (!set.add(t)) return 'Existem horários duplicados';
                        }
                        return null;
                      },
                      onComplete: onEmitHorarios,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remover horário',
                    onPressed:
                        horariosCtrls.length > 1
                            ? () {
                              final removed = horariosCtrls.removeAt(i);
                              removed.dispose();
                              qtdDosesDiaCtrl.text =
                                  horariosCtrls.length.toString();
                              (context as Element).markNeedsBuild();
                              onEmitHorarios();
                            }
                            : null,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            );
          }),
        ],
        if (isDoseUnica) ...[
          CustomTextField(
            pad: 0,
            ctrl: qtdMedicamentoCtrl,
            label: 'Quantidade por dose',
            textInputType: TextInputType.number,
            hint: '1',
            validador:
                (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Informe a quantidade'
                        : null,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            ctrl: dataInicialCtrl, // usa data inicial como data do dia
            label: 'Data',
            hint: '25/05/2025',
            pad: 0,
            textInputType: TextInputType.datetime,
            validador:
                (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a data' : null,
            onComplete: () => (dataFinalCtrl.text = dataInicialCtrl.text),
          ),
          const SizedBox(height: 16),
          CustomTextField(
            ctrl: horariosCtrls[0],
            label: 'Dose',
            hint: '08:00',
            pad: 0,
            isTime: true,
            textInputType: TextInputType.text,
            icon: Icons.access_time,
            validador:
                (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe a hora' : null,
            onComplete: onEmitHorarios,
          ),
        ] else ...[
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  horariosCtrls.add(TextEditingController());
                  qtdDosesDiaCtrl.text = horariosCtrls.length.toString();
                  (context as Element).markNeedsBuild();
                  onEmitHorarios();
                },
                icon: const Icon(Icons.add),
                label: const Text('Adicionar horário'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Período',
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
                  ctrl: dataInicialCtrl,
                  label: 'Data',
                  hint: '25/05/2025',
                  pad: 0,
                  textInputType: TextInputType.datetime,
                  validador:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Informe a data inicial'
                              : null,
                ),
              ),
              const SizedBox(width: 8),
              if (isDeterminado)
                Flexible(
                  child: CustomTextField(
                    ctrl: dataFinalCtrl,
                    label: 'Data final',
                    hint: '25/06/2025',
                    pad: 0,
                    textInputType: TextInputType.datetime,
                    validador:
                        (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Informe a data final'
                                : null,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Refeicoes extends StatelessWidget {
  final bool isDeterminado;
  final TextEditingController qtdMedicamentoCtrl;
  final TextEditingController dataInicialCtrl;
  final TextEditingController dataFinalCtrl;
  final Set<String> selected;
  final void Function(String key) onToggle;
  final String? errorText;
  final TextEditingController qtdTotalCtrl;

  const _Refeicoes({
    required this.isDeterminado,
    required this.qtdMedicamentoCtrl,
    required this.dataInicialCtrl,
    required this.dataFinalCtrl,
    required this.selected,
    required this.onToggle,
    required this.errorText,
    required this.qtdTotalCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomTextField(
          pad: 0,
          ctrl: qtdMedicamentoCtrl,
          label: 'Qtd por dose',
          textInputType: TextInputType.number,
          hint: '1',
          validador:
              (v) =>
                  (v == null || v.trim().isEmpty)
                      ? 'Informe a quantidade por dose'
                      : null,
        ),
        const SizedBox(height: 16),
        const Text(
          'Refeições',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.textVerde,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('Café da manhã'),
              selected: selected.contains('cafe'),
              onSelected: (_) => onToggle('cafe'),
            ),
            FilterChip(
              label: const Text('Almoço'),
              selected: selected.contains('almoco'),
              onSelected: (_) => onToggle('almoco'),
            ),
            FilterChip(
              label: const Text('Jantar'),
              selected: selected.contains('jantar'),
              onSelected: (_) => onToggle('jantar'),
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'Período',
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
                ctrl: dataInicialCtrl,
                label: 'Data inicial',
                hint: '25/05/2025',
                pad: 0,
                textInputType: TextInputType.datetime,
                validador:
                    (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Informe a data inicial'
                            : null,
              ),
            ),
            const SizedBox(width: 8),
            if (isDeterminado)
              Flexible(
                child: CustomTextField(
                  ctrl: dataFinalCtrl,
                  label: 'Data final',
                  hint: '25/06/2025',
                  pad: 0,
                  textInputType: TextInputType.datetime,
                  validador:
                      (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Informe a data final'
                              : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
