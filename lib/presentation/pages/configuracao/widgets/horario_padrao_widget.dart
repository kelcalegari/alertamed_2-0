import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../shared/widgets/custom_seletor_field.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../themes/app_colors.dart';
import '../model/horarios_model.dart'; // DiaSemana, HorarioRefeicaoModel, helpers

class HorariosPadraoEditor extends StatefulWidget {
  final Color? primaryColor;
  final VoidCallback? onSaved;

  const HorariosPadraoEditor({super.key, this.primaryColor, this.onSaved});

  @override
  State<HorariosPadraoEditor> createState() => _HorariosPadraoEditorState();
}

class _HorariosPadraoEditorState extends State<HorariosPadraoEditor> {
  /// Estado local editável
  final List<HorarioRefeicaoModel> _horarios = [];

  bool _inicializado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Carrega do provider apenas 1x
    if (!_inicializado) {
      final provider = context.read<UsuarioProvider>();
      _sincronizarComProvider(provider);
      _inicializado = true;
    }
  }

  void _sincronizarComProvider(UsuarioProvider provider) {
    _horarios
      ..clear()
      ..addAll(_fromProviderList(provider.horariosRefeicoes));
    _sanitizar(); // garante Padrão e ordenação
    setState(() {});
  }

  // ---------- Converters Provider <-> Model ----------

  List<HorarioRefeicaoModel> _fromProviderList(
    List<Map<String, dynamic>> list,
  ) {
    if (list.isEmpty) return defaultHorarios();
    return list.map((m) {
      final diaStr = (m['dia'] as String);
      return HorarioRefeicaoModel(
        dia: _diaFromString(diaStr),
        cafe: strToTime(m['horaCafe'] as String),
        almoco: strToTime(m['horaAlmoco'] as String),
        janta: strToTime(m['horaJanta'] as String),
      );
    }).toList();
  }

  List<Map<String, dynamic>> _toProviderList(List<HorarioRefeicaoModel> list) {
    return list
        .map(
          (h) => {
            'dia': diaLabel(h.dia),
            'horaCafe': timeToStr(h.cafe),
            'horaAlmoco': timeToStr(h.almoco),
            'horaJanta': timeToStr(h.janta),
          },
        )
        .toList();
  }

  DiaSemana _diaFromString(String s) {
    // aceita "Padrão"/"Padrao" e Dom..Sáb
    final lower = s.toLowerCase();
    if (lower == 'padrão' || lower == 'padrao') return DiaSemana.padrao;

    for (final d in DiaSemana.values) {
      if (diaLabel(d).toLowerCase() == lower) return d;
    }
    // fallback seguro
    return DiaSemana.padrao;
  }

  // ---------- Regras/UI helpers ----------

  void _sanitizar() {
    // Remove Padrão temporário
    final semPadrao =
        _horarios.where((h) => h.dia != DiaSemana.padrao).toList();

    // Se a semana não estiver completa, insere Padrão no topo
    final temTodos = diasSemanaSemPadrao.every(
      (d) => semPadrao.any((h) => h.dia == d),
    );
    if (!temTodos) {
      final existentePadrao = _horarios.firstWhere(
        (h) => h.dia == DiaSemana.padrao,
        orElse: () => defaultHorarios().first,
      );
      _horarios
        ..clear()
        ..add(existentePadrao)
        ..addAll(semPadrao);
    } else {
      _horarios
        ..clear()
        ..addAll(semPadrao);
    }

    // Ordenar: Padrão (se houver) primeiro; depois Dom..Sáb
    _horarios.sort((a, b) {
      if (a.dia == DiaSemana.padrao && b.dia != DiaSemana.padrao) return -1;
      if (b.dia == DiaSemana.padrao && a.dia != DiaSemana.padrao) return 1;
      return diasSemanaSemPadrao
          .indexOf(a.dia)
          .compareTo(diasSemanaSemPadrao.indexOf(b.dia));
    });
  }

  bool _diaEmUso(DiaSemana d) => _horarios.any((h) => h.dia == d);

  Future<void> _selecionarHorario(
    DiaSemana dia, {
    required String tipo,
    required TimeOfDay initial,
  }) async {
    final selecionado = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (selecionado == null) return;

    final idx = _horarios.indexWhere((h) => h.dia == dia);
    if (idx < 0) return;

    final atual = _horarios[idx];
    switch (tipo) {
      case 'cafe':
        _horarios[idx] = atual.copyWith(cafe: selecionado);
        break;
      case 'almoco':
        _horarios[idx] = atual.copyWith(almoco: selecionado);
        break;
      case 'janta':
        _horarios[idx] = atual.copyWith(janta: selecionado);
        break;
    }
    setState(() {});
  }

  List<DropdownMenuItem<DiaSemana>> _diasDisponiveisPara(DiaSemana atual) {
    final usados = _horarios.map((h) => h.dia).toSet();

    return DiaSemana.values
        .where((d) {
          // Nunca ofereça "Padrão" no dropdown
          if (d == DiaSemana.padrao) return false;
          // Ofereça o dia atual (para manter seleção válida) ou dias não usados
          return d == atual || !usados.contains(d);
        })
        .map((d) => DropdownMenuItem(value: d, child: Text(diaLabel(d))))
        .toList();
  }

  void _trocarDia(DiaSemana from, DiaSemana to) {
    if (to == DiaSemana.padrao || _diaEmUso(to)) return;
    final idx = _horarios.indexWhere((h) => h.dia == from);
    if (idx < 0) return;
    _horarios[idx] = _horarios[idx].copyWith(dia: to);
    _sanitizar();
    setState(() {});
  }

  void _removerDia(DiaSemana dia) {
    if (dia == DiaSemana.padrao) return;
    _horarios.removeWhere((h) => h.dia == dia);
    _sanitizar();
    setState(() {});
  }

  void _adicionarDia() {
    final usados = _horarios.map((h) => h.dia).toSet();
    final candidatos =
        diasSemanaSemPadrao.where((d) => !usados.contains(d)).toList();
    if (candidatos.isEmpty) return;
    _horarios.add(
      HorarioRefeicaoModel(
        dia: candidatos.first,
        cafe: const TimeOfDay(hour: 7, minute: 30),
        almoco: const TimeOfDay(hour: 12, minute: 0),
        janta: const TimeOfDay(hour: 19, minute: 0),
      ),
    );
    _sanitizar();
    setState(() {});
  }

  // ---------- UI ----------

  Widget _linha(HorarioRefeicaoModel h) {
    final isPadrao = h.dia == DiaSemana.padrao;

    // Controllers para manter os valores exibidos
    final cafeCtrl = TextEditingController(
      text:
          '${h.cafe.hour.toString().padLeft(2, '0')}:${h.cafe.minute.toString().padLeft(2, '0')}',
    );
    final almocoCtrl = TextEditingController(
      text:
          '${h.almoco.hour.toString().padLeft(2, '0')}:${h.almoco.minute.toString().padLeft(2, '0')}',
    );
    final jantaCtrl = TextEditingController(
      text:
          '${h.janta.hour.toString().padLeft(2, '0')}:${h.janta.minute.toString().padLeft(2, '0')}',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child:
                isPadrao
                    ? SizedBox(
                      height: 56,
                      child: CustomSelectorField<DiaSemana>(
                        selectedValue: DiaSemana.padrao,
                        items: const [
                          DropdownMenuItem(
                            value: DiaSemana.padrao,
                            child: Text('Padrão'),
                          ),
                        ],
                        onChanged: (_) {},
                        pad: 0,
                        locked: true,
                        fontSize: 15,
                      ),
                    )
                    : SizedBox(
                      height: 56,
                      child: CustomSelectorField<DiaSemana>(
                        selectedValue: h.dia,
                        items: _diasDisponiveisPara(h.dia),
                        pad: 0,
                        onChanged: (value) {
                          if (value == null || value == h.dia) return;
                          if (_diaEmUso(value)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Dia já utilizado.'),
                              ),
                            );
                            return;
                          }
                          _trocarDia(h.dia, value);
                        },
                        fontSize: 15,
                      ),
                    ),
          ),

          const SizedBox(width: 3),

          // Campos com CustomTextField
          Expanded(
            child: CustomTextField(
              ctrl: cafeCtrl,
              textInputType: TextInputType.number,
              isTime: true,
              pad: 0,
              initialTime: h.cafe,
              fontSize: 15,
              onComplete: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: h.cafe,
                );
                if (picked != null) {
                  _trocarHora(h.dia, "cafe", picked);
                }
              },
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: CustomTextField(
              ctrl: almocoCtrl,
              textInputType: TextInputType.number,
              isTime: true,
              pad: 0,
              initialTime: h.almoco,
              fontSize: 15,
              onComplete: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: h.almoco,
                );
                if (picked != null) {
                  _trocarHora(h.dia, "almoco", picked);
                }
              },
            ),
          ),
          const SizedBox(width: 3),

          Expanded(
            child: CustomTextField(
              ctrl: jantaCtrl,
              textInputType: TextInputType.number,
              isTime: true,
              pad: 0,
              initialTime: h.janta,
              fontSize: 15,
              onComplete: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: h.janta,
                );
                if (picked != null) {
                  _trocarHora(h.dia, "janta", picked);
                }
              },
            ),
          ),
          const SizedBox(width: 3),

          // Botão remover
          if (!isPadrao)
            IconButton(
              tooltip: 'Remover dia',
              icon: const Icon(Icons.delete_outline, size: 18), // menor ícone
              padding: EdgeInsets.zero, // remove padding extra
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32), // botão compacto
              onPressed: () => _removerDia(h.dia),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  void _trocarHora(DiaSemana dia, String tipo, TimeOfDay novo) {
    final idx = _horarios.indexWhere((h) => h.dia == dia);
    if (idx < 0) return;

    final atual = _horarios[idx];
    switch (tipo) {
      case 'cafe':
        _horarios[idx] = atual.copyWith(cafe: novo);
        break;
      case 'almoco':
        _horarios[idx] = atual.copyWith(almoco: novo);
        break;
      case 'janta':
        _horarios[idx] = atual.copyWith(janta: novo);
        break;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UsuarioProvider>();
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Horários Padrão por Refeição',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textVerde,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Defina os horários das refeições para facilitar o agendamento dos medicamentos.',
          ),
          const SizedBox(height: 16),

          Row(
            children: const [
              Expanded(
                flex: 2,
                child: Text(
                  'Dia',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textVerde,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Café',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textVerde,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Almoço',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textVerde,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Janta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textVerde,
                  ),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 8),

          ListView.builder(
            itemCount: _horarios.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (_, i) => _linha(_horarios[i]),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _adicionarDia,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar dia'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  final lista = _toProviderList(_horarios);
                  await provider.salvarHorariosRefeicoes(lista);
                  widget.onSaved?.call();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Horários salvos!')),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
