import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';
import 'package:intl/intl.dart';

import '../service/salvar_tratamento.dart';
import 'widgets_gerenciamento_tratamento/agendamento_tratamento_card.dart';
import 'widgets_gerenciamento_tratamento/formulario_tratamento_card.dart';
import 'widgets_gerenciamento_tratamento/informacoes_tratamento_card.dart';

class GerenciadorTratamento extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onConcluir;

  const GerenciadorTratamento({
    Key? key,
    required this.onCancel,
    required this.onConcluir,
  }) : super(key: key);

  @override
  State<GerenciadorTratamento> createState() => _GerenciadorTratamentoState();
}

class _GerenciadorTratamentoState extends State<GerenciadorTratamento>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  final _totalPages = 3;
  final _formKeyIndexUm = GlobalKey<FormState>();
  final _formKeyIndexDois = GlobalKey<FormState>();
  final _formKeyIndexTres = GlobalKey<FormState>();

  final _nameMedicamentoCtrl = TextEditingController();
  final _frequenciaCtrl = TextEditingController(text: "8");
  final _qtdMedicamentoCtrl = TextEditingController(text: "1");
  final _qtdMedicamentoTotalCtrl = TextEditingController();
  final _dataInicialCtrl = TextEditingController(
    text: DateFormat('dd/MM/yyyy').format(DateTime.now()),
  );
  final _dataFinalCtrl = TextEditingController();
  final _horaInicialCtrl = TextEditingController(
    text: DateFormat('HH:mm').format(DateTime.now()),
  );
  final _nameDosagemCtrl = TextEditingController(text: "1");
  final _qtdMedicamentoEstoqueCtrl = TextEditingController();
  final _qtdEstoqueMinimoCtrl = TextEditingController(text: "5");
  final _dataValidadeCtrl = TextEditingController();
  final _observacaoCtrl = TextEditingController();

  String? _selectedTipo;
  final _vectorTipo = [
    'Comprimido',
    'Cápsula',
    'Xarope',
    'Gotas',
    'Injetável',
    'Pomada',
    'Creme',
    'Supositório',
    'Aerossol',
    'Solução oral',
    'Pó para reconstituição',
  ];
  String? _selectedUnidadesMedida;
  final _vectorUnidadesMedida = [
    'mg',
    'g',
    'mcg',
    'mL',
    'L',
    'UI',
    'un',
    'comp',
    'cáps',
    'gota',
    'env',
    'flacon',
    'frasco',
    'ampola',
  ];
  String? _selectedUnidadesMedidaLembrete;
  final _vectorUnidadesMedidaLembrete = [
    'mg',
    'g',
    'mcg',
    'mL',
    'L',
    'UI',
    'un',
    'comp',
    'cáps',
    'gota',
    'env',
    'flacon',
    'frasco',
    'ampola',
  ];
  String? _selectedTipoTratamento;
  final _vectorTipoTratamento = [
    'Tratamento Determinado',
    'Tratamento Contínuo',
    'Tratamento Dose única',
  ];

  String? _selectedTipoFrequencia;
  final _vectorTipoFrequencia = [
    'Intervalos Fixos',
    'Horários Fixos',
    'Junto com Refeições',
  ];
  String? _selectedCompartilharTratamento;
  final _vectorCompartilharTratamento = [
    'Não',
    'Sim, Médica Chayanne Calegari',
  ];
  bool _showHint = true;
  late AnimationController _animationController;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _selectedTipo = _vectorTipo.first;
    _selectedUnidadesMedida = _vectorUnidadesMedida.first;
    _selectedUnidadesMedidaLembrete = _vectorUnidadesMedidaLembrete.first;
    _selectedTipoTratamento = _vectorTipoTratamento.first;
    _selectedTipoFrequencia = _vectorTipoFrequencia.first;
    _selectedCompartilharTratamento = _vectorCompartilharTratamento.first;

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _offsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.2),
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showHint = false;
        });
        _animationController.stop();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();

    _nameMedicamentoCtrl.dispose();
    _frequenciaCtrl.dispose();
    _qtdMedicamentoCtrl.dispose();
    _qtdMedicamentoTotalCtrl.dispose();
    _dataInicialCtrl.dispose();
    _dataFinalCtrl.dispose();
    _horaInicialCtrl.dispose();
    _nameDosagemCtrl.dispose();
    _qtdMedicamentoEstoqueCtrl.dispose();
    _qtdEstoqueMinimoCtrl.dispose();
    _dataValidadeCtrl.dispose();
    _observacaoCtrl.dispose();

    super.dispose();
  }

  void _onVerticalDrag(DragEndDetails details) {
    if (details.primaryVelocity == null) return;

    if (details.primaryVelocity! < 0 && _currentIndex < _totalPages - 1) {
      if (_currentIndex == 0) {
        final isValid = _formKeyIndexUm.currentState?.validate() ?? false;
        if (!isValid) return;
      }
      if (_currentIndex == 1) {
        _calcularAgendamento();
        final isValid = _formKeyIndexDois.currentState?.validate() ?? false;
        if (!isValid) return;
      }

      setState(() => _currentIndex++);
    } else if (details.primaryVelocity! > 0 && _currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuarioProvider = Provider.of<UsuarioProvider>(context, listen: false);
    return Container(
      child: GestureDetector(
        onVerticalDragEnd: _onVerticalDrag,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.cardBackgroundBranco,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: IndexedStack(
              //key: ValueKey(_currentIndex),
              index: _currentIndex,
              children: [
                _buildCard(
                  showHint: _showHint,
                  child: _buildFormularioTratamento(),
                ),
                _buildCard(child: _buildAgendamentoTratamento()),
                _buildCard(child: _buildInformacoesAdicionais(usuarioProvider)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({bool showHint = false, Widget? child}) {
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child:
              showHint
                  ? Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: SlideTransition(
                      position: _offsetAnimation,
                      child: Column(
                        children: const [
                          Icon(
                            Icons.keyboard_arrow_up,
                            size: 28,
                            color: AppColors.textVerde,
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Deslize para cima",
                            style: TextStyle(
                              color: AppColors.textVerde,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),

        Expanded(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.cardBackgroundBranco,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ],
    );
  }

  Widget _buildFormularioTratamento() {
    return FormularioTratamento(
      formKeyIndexUm: _formKeyIndexUm,
      nameMedicamentoCtrl: _nameMedicamentoCtrl,
      nameDosagemCtrl: _nameDosagemCtrl,
      selectedTipo: _selectedTipo,
      vectorTipo: _vectorTipo,
      selectedUnidadesMedida: _selectedUnidadesMedida,
      vectorUnidadesMedida: _vectorUnidadesMedida,
      selectedTipoTratamento: _selectedTipoTratamento,
      vectorTipoTratamento: _vectorTipoTratamento,
      selectedTipoFrequencia: _selectedTipoFrequencia,
      vectorTipoFrequencia: _vectorTipoFrequencia,
      onTipoChanged: (value) => setState(() => _selectedTipo = value),
      onUnidadesMedidaChanged:
          (value) => setState(() => _selectedUnidadesMedida = value),
      onTipoTratamentoChanged:
          (value) => setState(() => _selectedTipoTratamento = value),
      onTipoFrequenciaChanged:
          (value) => setState(() => _selectedTipoFrequencia = value),
    );
  }

  Widget _buildAgendamentoTratamento() {
    return AgendamentoTratamento(
      formKeyIndexDois: _formKeyIndexDois,
      frequenciaCtrl: _frequenciaCtrl,
      qtdMedicamentoCtrl: _qtdMedicamentoCtrl,
      qtdMedicamentoTotalCtrl: _qtdMedicamentoTotalCtrl,
      horaInicialCtrl: _horaInicialCtrl,
      dataInicialCtrl: _dataInicialCtrl,
      dataFinalCtrl: _dataFinalCtrl,
      selectedUnidadesMedidaLembrete: _selectedUnidadesMedidaLembrete,
      vectorUnidadesMedidaLembrete: _vectorUnidadesMedidaLembrete,
      onSelectedUnidadesMedidaLembreteChanged: (value) {
        setState(() {
          _selectedUnidadesMedidaLembrete = value;
        });
      },
    );
  }

  _buildInformacoesAdicionais(UsuarioProvider usuarioProvider) {
    return InformacoesAdicionais(
      formKeyIndexTres: _formKeyIndexTres,
      qtdMedicamentoEstoqueCtrl: _qtdMedicamentoEstoqueCtrl,
      qtdEstoqueMinimoCtrl: _qtdEstoqueMinimoCtrl,
      dataValidadeCtrl: _dataValidadeCtrl,
      observacaoCtrl: _observacaoCtrl,
      selectedUnidadesMedida: _selectedUnidadesMedida,
      vectorUnidadesMedida: _vectorUnidadesMedida,
      selectedCompartilharTratamento: _selectedCompartilharTratamento,
      vectorCompartilharTratamento: _vectorCompartilharTratamento,
      onConcluir: widget.onConcluir,
      onUnidadesMedidaChanged:
          (val) => setState(() => _selectedUnidadesMedida = val),
      onCompartilharTratamentoChanged:
          (val) => setState(() => _selectedCompartilharTratamento = val),
      onPressedSalvar:  () => _salvarTratamento(usuarioProvider),
    );
  }

  void _calcularAgendamento() {
    final formatter = DateFormat('dd/MM/yyyy HH:mm');

    final dataInicialStr = _dataInicialCtrl.text.trim();
    final horaInicialStr = _horaInicialCtrl.text.trim();
    final freqStr = _frequenciaCtrl.text.trim();
    final qtdStr = _qtdMedicamentoCtrl.text.trim();
    final qtdTotalStr = _qtdMedicamentoTotalCtrl.text.trim();
    final dataFinalStr = _dataFinalCtrl.text.trim();

    try {
      if (dataInicialStr.isEmpty ||
          horaInicialStr.isEmpty ||
          freqStr.isEmpty ||
          qtdStr.isEmpty)
        return;

      final dataInicial = formatter.parse('$dataInicialStr $horaInicialStr');
      final horaStr = freqStr.split(':').first;
      final frequenciaHoras = int.parse(horaStr);
      final qtdPorDose = int.parse(qtdStr);

      final totalQtd =
          qtdTotalStr.isNotEmpty ? int.tryParse(qtdTotalStr) : null;
      final dataFinal =
          dataFinalStr.isNotEmpty
              ? DateFormat('dd/MM/yyyy').parse(dataFinalStr)
              : null;

      // 1. Só qtdTotal preenchido → calcular dataFinal
      if (totalQtd != null && dataFinal == null) {
        final totalDoses = (totalQtd / qtdPorDose).floor();
        final novaDataFinal = _calcularDataFinal(
          dataInicial,
          frequenciaHoras,
          totalDoses,
        );
        _dataFinalCtrl.text = DateFormat('dd/MM/yyyy').format(novaDataFinal);
        return;
      }

      // 2. Só dataFinal preenchida → calcular qtdTotal
      if (totalQtd == null && dataFinal != null) {
        final totalDoses = _calcularTotalDoses(
          dataInicial,
          dataFinal,
          frequenciaHoras,
        );
        final novaQtdTotal = totalDoses * qtdPorDose;
        _qtdMedicamentoTotalCtrl.text = novaQtdTotal.toString();
        return;
      }

      // 3. Ambos preenchidos → validar se batem
      if (totalQtd != null && dataFinal != null) {
        final totalDosesEsperadas = _calcularTotalDoses(
          dataInicial,
          dataFinal,
          frequenciaHoras,
        );
        final qtdEsperada = totalDosesEsperadas * qtdPorDose;

        // Se valor esperado for diferente, confiar na frequência e qtd e recalcular a data final
        if (qtdEsperada != totalQtd) {
          final totalDoses = (totalQtd / qtdPorDose).floor();
          final novaDataFinal = _calcularDataFinal(
            dataInicial,
            frequenciaHoras,
            totalDoses,
          );
          _dataFinalCtrl.text = DateFormat('dd/MM/yyyy').format(novaDataFinal);
        }
      }
    } catch (_) {
      // erro no parse → ignora
    }
  }

  void _salvarTratamento(UsuarioProvider usuarioProvider) async {
    final isValid1 = _formKeyIndexUm.currentState?.validate() ?? false;
    final isValid2 = _formKeyIndexDois.currentState?.validate() ?? false;
    final isValid3 = _formKeyIndexTres.currentState?.validate() ?? false;

    if (!isValid1 || !isValid2 || !isValid3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    final controller = SalvarTratamento(
      usuarioProvider: usuarioProvider,
      nomeMedicamento: _nameMedicamentoCtrl.text,
      tipoMedicamento: _selectedTipo ?? "",
      concentracaoMedicamento: _nameDosagemCtrl.text.trim() + " " + _selectedUnidadesMedida!,
      qtdMedicamento: _qtdMedicamentoCtrl.text.trim(),
      qtdMedicamentoTotal: _qtdMedicamentoTotalCtrl.text.trim(),
      tipoTratamento: _selectedTipoTratamento,
      frequenciaHoras: _frequenciaCtrl.text.trim(),
      dataInicial: _dataInicialCtrl.text.trim(),
      horaInicial: _horaInicialCtrl.text.trim(),
      idCuidador: "_idCuidador", // pega do seu estado/variável
      observacoes: _observacaoCtrl.text.trim(),
      qtdMedicamentoEstoqueCtrl: _qtdMedicamentoEstoqueCtrl.text.trim(),
      qtdEstoqueMinimoCtrl: _qtdEstoqueMinimoCtrl.text.trim(),
      dataValidadeCtrl: _dataValidadeCtrl.text.trim(),
      unidadeMedida: _selectedUnidadesMedidaLembrete ?? "",
    );

    try {
      await controller.criarTratamentoComLembretes();
      widget.onConcluir();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao salvar tratamento')));
    }
  }

  DateTime _calcularDataFinal(
    DateTime dataInicial,
    int frequenciaHoras,
    int totalDoses,
  ) {
    final duracaoTotalHoras = (totalDoses - 1) * frequenciaHoras;
    return dataInicial.add(Duration(hours: duracaoTotalHoras));
  }

  /// Calcula o total de doses a partir da data inicial, data final e frequência em horas
  int _calcularTotalDoses(
    DateTime dataInicial,
    DateTime dataFinal,
    int frequenciaHoras,
  ) {
    final duracaoHoras = dataFinal.difference(dataInicial).inHours;
    return (duracaoHoras / frequenciaHoras).floor() + 1;
  }
}
