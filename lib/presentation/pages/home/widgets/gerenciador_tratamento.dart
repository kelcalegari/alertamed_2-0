import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:diacritic/diacritic.dart';
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

  /// Se for null => criação. Se não for null => edição.
  final String? idTratamento;

  const GerenciadorTratamento({
    Key? key,
    required this.onCancel,
    required this.onConcluir,
    this.idTratamento,
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
  final _qtdMedicamentoTotalCtrl = TextEditingController(text: "1");
  final _dataInicialCtrl = TextEditingController(
    text: DateFormat('dd/MM/yyyy').format(DateTime.now()),
  );
  final _dataFinalCtrl = TextEditingController();
  final _horaInicialCtrl = TextEditingController(
    text: DateFormat('HH:mm').format(
      DateTime.now().add(const Duration(hours: 1)),
    ),
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

  /// Quando o usuário digita manualmente horários fixos (HH:mm)
  List<String> _horariosFixos = [];

  /// NOVO: Refeições selecionadas no modo "Junto com Refeições"
  /// valores: 'cafe' | 'almoco' | 'jantar'
  List<String> _refeicoesSelecionadas = [];
  String? id_medicamento;
  bool _estoquePrefillDone = false;
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
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _showHint = false);
        _animationController.stop();
      }
    });

    // >>>>>>>>>> NOVO: carregar dados para edição
    if (widget.idTratamento != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final prov = Provider.of<UsuarioProvider>(context, listen: false);
        final t = prov.tratamentosMap[widget.idTratamento];
        if (t != null) {
          _preencherCamposParaEdicao(t);
        }
      });
    }
  }
  Future<void> _prefillEstoqueSeDisponivel() async {
    if (_estoquePrefillDone) return;

    final prov = Provider.of<UsuarioProvider>(context, listen: false);
    final String? userId = prov.userId;
    final String? idMed = id_medicamento;

    if (userId == null || userId.isEmpty || idMed == null || idMed.isEmpty) return;

    // 1) Tenta do Provider
    if (prov.estoqueMap.containsKey(idMed)) {
      final raw = prov.estoqueMap[idMed];
      if (raw is Map) {
        _aplicarPrefillEstoque(Map<String, dynamic>.from(raw));
        _estoquePrefillDone = true;
        return;
      }
    }

    // 2) Busca no Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios').doc(userId)
          .collection('estoque').doc(idMed)
          .get();

      if (!mounted) return;
      if (doc.exists) {
        final data = (doc.data() ?? {}) as Map<String, dynamic>;
        _aplicarPrefillEstoque(data);

        // opcional: cache local
        prov.estoqueMap[idMed] = data;
        _estoquePrefillDone = true;
      }
    } catch (e) {
      debugPrint('Falha ao carregar estoque: $e');
    }
  }

  // === NOVO: aplica nos controllers sem sobrescrever se já houver texto ===
  void _aplicarPrefillEstoque(Map<String, dynamic> e) {
    // qtdAtual
    final dynamic qtdAtualDyn = e['qtdAtual'];
    final sQtdAtual = (qtdAtualDyn == null)
        ? ''
        : (qtdAtualDyn is num) ? qtdAtualDyn.toString() : qtdAtualDyn.toString();
    if (_qtdMedicamentoEstoqueCtrl.text.isEmpty && sQtdAtual.isNotEmpty) {
      _qtdMedicamentoEstoqueCtrl.text = sQtdAtual;
    }

    // qtdMinima
    final dynamic qtdMinDyn = e['qtdMinima'];
    final sQtdMin = (qtdMinDyn == null)
        ? ''
        : (qtdMinDyn is num) ? qtdMinDyn.toString() : qtdMinDyn.toString();
    if (_qtdEstoqueMinimoCtrl.text.isEmpty && sQtdMin.isNotEmpty) {
      _qtdEstoqueMinimoCtrl.text = sQtdMin;
    }

    // dataValidade: Timestamp | DateTime | String dd/MM/yyyy
    final dv = e['dataValidade'];
    DateTime? dt;
    if (dv is Timestamp) {
      dt = dv.toDate();
    } else if (dv is DateTime) {
      dt = dv;
    } else if (dv is String && dv.trim().isNotEmpty) {
      try {
        dt = DateFormat('dd/MM/yyyy').parseStrict(dv.trim());
      } catch (_) {}
    }
    if (dt != null && _dataValidadeCtrl.text.isEmpty) {
      _dataValidadeCtrl.text = DateFormat('dd/MM/yyyy').format(dt);
    }

    if (mounted) setState(() {});
  }
  void _preencherCamposParaEdicao(Map<String, dynamic> t) {
    // Nome / tipo
    _nameMedicamentoCtrl.text = (t['nomeMedicamento'] ?? '').toString();
    _selectedTipo = (t['tipoMedicamento'] ?? _selectedTipo) as String?;

    // Concentracao: exemplo "10 mg" → valor + unidade
    final conc = (t['concentracaoMedicamento'] ?? '').toString().trim();
    final concMatch = RegExp(r'^([\d,.]+)\s*([^\d\s].*)$').firstMatch(conc);
    if (concMatch != null) {
      _nameDosagemCtrl.text = concMatch.group(1)!.replaceAll(',', '.');
      final unidade = concMatch.group(2)!.trim();
      if (_vectorUnidadesMedida.contains(unidade)) {
        _selectedUnidadesMedida = unidade;
      }
    }

    // Tipo de tratamento / frequência
    _selectedTipoTratamento = (t['tipoTratamento'] ?? _selectedTipoTratamento) as String?;
    _selectedTipoFrequencia = (t['tipoFrequencia'] ?? _selectedTipoFrequencia) as String?;

    // Datas
    final dtIni = t['dataInicio'];
    final dtFim = t['dataTermino'];
    DateTime? dIni, dFim;
    if (dtIni != null && dtIni is Timestamp) dIni = dtIni.toDate();
    if (dtFim != null && dtFim is Timestamp) dFim = dtFim.toDate();
    if (dIni != null) {
      _dataInicialCtrl.text = DateFormat('dd/MM/yyyy').format(dIni);
    }
    if (dFim != null) {
      _dataFinalCtrl.text = DateFormat('dd/MM/yyyy').format(dFim);
    }

    // Hora inicial (heurística):
    // - Horários fixos: pega o primeiro lembrete do mesmo dia e usa o "valor" HH:mm
    // - Intervalos: usa o que estiver salvo anteriormente no campo "horaInicial" se você tiver salvo;
    //   senão tenta inferir do primeiro lembrete.
    String? horaInicialInferida;

    final lembs = (t['lembretes'] is List) ? List<Map<String, dynamic>>.from(t['lembretes']) : <Map<String, dynamic>>[];
    if (_selectedTipoFrequencia == 'Horários Fixos') {
      final horas = lembs
          .map((e) => (e['valor'] ?? '').toString())
          .where((v) => RegExp(r'^\d{2}:\d{2}$').hasMatch(v))
          .toList()
        ..sort();
      _horariosFixos = horas;
      if (horas.isNotEmpty) horaInicialInferida = horas.first;
    } else if (_selectedTipoFrequencia == 'Junto com Refeições') {
      // coletar momentos: 'cafe', 'almoco', 'jantar'
      final momentos = lembs.map((e) => (e['momento'] ?? '').toString()).toSet().toList();
      _refeicoesSelecionadas = momentos.where((m) => m == 'cafe' || m == 'almoco' || m == 'jantar').toList();
    } else if (_selectedTipoFrequencia == 'Intervalos Fixos') {
      // Frequência em horas
      final fH = (t['frequenciaHoras'] ?? t['frequencia'] ?? '').toString();
      // aceitar "8" ou "8h"/"8 horas"
      final m = RegExp(r'(\d{1,2})').firstMatch(fH);
      if (m != null) _frequenciaCtrl.text = m.group(1)!;

      // Tenta inferir hora inicial do primeiro lembrete
      final hPrimeiro = lembs
          .map((e) => (e['dataHoraAgendado']))
          .whereType<Timestamp>()
          .map((ts) => ts.toDate())
          .toList()
        ..sort();
      if (hPrimeiro.isNotEmpty) {
        horaInicialInferida = DateFormat('HH:mm').format(hPrimeiro.first);
        // e garante dataInicial também
        if (dIni == null) {
          _dataInicialCtrl.text = DateFormat('dd/MM/yyyy').format(hPrimeiro.first);
        }
      }
    }

    if (horaInicialInferida != null && RegExp(r'^\d{2}:\d{2}$').hasMatch(horaInicialInferida)) {
      _horaInicialCtrl.text = horaInicialInferida;
    }

    // Quantidades
    _qtdMedicamentoCtrl.text = (t['qtdMedicamento'] ?? _qtdMedicamentoCtrl.text).toString();
    _qtdMedicamentoTotalCtrl.text = (t['qtdMedicamentoTotal'] ?? _qtdMedicamentoTotalCtrl.text).toString();

    // Observações
    _observacaoCtrl.text = (t['observacoes'] ?? '').toString();

    // Estoque (se você salva nesses campos)
    _qtdMedicamentoEstoqueCtrl.text = (t['qtdMedicamentoEstoqueCtrl'] ?? '').toString();
    _qtdEstoqueMinimoCtrl.text = (t['qtdEstoqueMinimoCtrl'] ?? _qtdEstoqueMinimoCtrl.text).toString();
    final dataValStr = (t['dataValidadeCtrl'] ?? '').toString();
    if (dataValStr.isNotEmpty) _dataValidadeCtrl.text = dataValStr;

    setState(() {}); // reflete na UI
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
        // === AQUI: depois de preencher o 1º card, geramos o id e buscamos estoque ===
        id_medicamento = gerarIdMedicamento(
          _nameMedicamentoCtrl.text,
          '${_nameDosagemCtrl.text.trim()} ${_selectedUnidadesMedida!}',
          _selectedTipo!,
        );
        _prefillEstoqueSeDisponivel();
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
          child: showHint
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
      onTipoTratamentoChanged: (value) {
        setState(() {
          _selectedTipoTratamento = value;

          // Se virar "Dose única" e estava em "Intervalos Fixos", escolhe um aceitável
          if (value == 'Tratamento Dose única' &&
              _selectedTipoFrequencia == 'Intervalos Fixos') {
            // defina o default que você preferir:
            _selectedTipoFrequencia = 'Horários Fixos';
            // ou: _selectedTipoFrequencia = 'Junto com Refeições';
          }
        });
      },
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
      selectedTipoTratamento: _selectedTipoTratamento ?? "",
      onSelectedUnidadesMedidaLembreteChanged: (value) {
        setState(() {
          _selectedUnidadesMedidaLembrete = value;
        });
      },
      selectedTipoFrequencia: _selectedTipoFrequencia ?? '',
      onHorariosFixosChanged: (horas) {
        setState(() {
          _horariosFixos = horas;
        });
      },

      // NOVO: captura as refeições selecionadas
      onRefeicoesChanged: (refs) {
        setState(() {
          _refeicoesSelecionadas = refs;
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
  String gerarIdMedicamento(String nome, String conc, String tipo) {
    final normalized = [nome, conc, tipo]
        .map((s) => removeDiacritics(s)
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' '))
        .join('|');

    return normalized.toString();
  }

  // ===== Helpers compartilhados por "Horários Fixos" e "Refeições" =====

  DateTime? _parseDateddMMyyyy(String d) {
    final p = d.split('/');
    if (p.length != 3) return null;
    final dia = int.tryParse(p[0]);
    final mes = int.tryParse(p[1]);
    final ano = int.tryParse(p[2]);
    if (dia == null || mes == null || ano == null) return null;
    return DateTime(ano, mes, dia);
  }

  Duration? _parseHoraHHmm(String h) {
    final p = h.split(':');
    if (p.length != 2) return null;
    final hh = int.tryParse(p[0]);
    final mm = int.tryParse(p[1]);
    if (hh == null || mm == null) return null;
    return Duration(hours: hh, minutes: mm);
  }

  List<DateTime> _gerarLembretesFixos({
    required DateTime dataInicial,
    required List<String> horariosHHmm,
    int? totalDoses,
    DateTime? dataFinalInclusiva,
  }) {
    assert((totalDoses != null) ^ (dataFinalInclusiva != null),
    "Informe totalDoses XOR dataFinalInclusiva");

    final horas = horariosHHmm
        .map(_parseHoraHHmm)
        .whereType<Duration>()
        .toList()
      ..sort((a, b) => a.inMinutes.compareTo(b.inMinutes));

    if (horas.isEmpty) return const [];

    final result = <DateTime>[];
    var dia = DateTime(dataInicial.year, dataInicial.month, dataInicial.day);

    bool dentroDoPeriodo(DateTime dt) {
      if (dataFinalInclusiva == null) return true;
      final endOfDay = DateTime(
        dataFinalInclusiva.year,
        dataFinalInclusiva.month,
        dataFinalInclusiva.day,
        23, 59, 59, 999,
      );
      return !dt.isAfter(endOfDay);
    }

    while (true) {
      for (final h in horas) {
        final dt = DateTime(dia.year, dia.month, dia.day).add(h);
        if (dt.isBefore(dataInicial)) continue;        // ignora 1º dia antes da âncora
        if (!dentroDoPeriodo(dt)) return result;       // estourou período
        result.add(dt);
        if (totalDoses != null && result.length >= totalDoses) return result;
      }
      dia = dia.add(const Duration(days: 1));
      if (result.length > 20000) return result; // guarda-chuva
    }
  }

  DateTime _ultimaDoseHorariosFixosAncorada({
    required DateTime dataHoraInicial,
    required List<String> horariosHHmm,
    required int totalDoses,
  }) {
    final horas = horariosHHmm
        .map(_parseHoraHHmm)
        .whereType<Duration>()
        .toList()
      ..sort((a, b) => a.inMinutes.compareTo(b.inMinutes));

    if (horas.isEmpty) {
      throw ArgumentError('Lista de horários vazia');
    }
    if (totalDoses <= 0) {
      throw ArgumentError('totalDoses deve ser > 0');
    }

    final dosesPorDia = horas.length;
    final baseDia = DateTime(
      dataHoraInicial.year,
      dataHoraInicial.month,
      dataHoraInicial.day,
    );
    final minutosAncora = dataHoraInicial.difference(baseDia).inMinutes;

    int firstIdx = horas.indexWhere((h) => h.inMinutes >= minutosAncora);
    final slotsHoje = firstIdx == -1 ? 0 : (dosesPorDia - firstIdx);

    int rem = totalDoses;

    if (slotsHoje > 0) {
      if (rem <= slotsHoje) {
        final idxInDay = firstIdx + (rem - 1);
        return baseDia.add(horas[idxInDay]);
      }
      rem -= slotsHoje;
      final fullDays = (rem - 1) ~/ dosesPorDia;
      final idxInDay2 = (rem - 1) % dosesPorDia;
      final targetDay = baseDia.add(Duration(days: 1 + fullDays));
      return targetDay.add(horas[idxInDay2]);
    } else {
      final fullDays = (rem - 1) ~/ dosesPorDia;
      final idxInDay2 = (rem - 1) % dosesPorDia;
      final targetDay = baseDia.add(Duration(days: 1 + fullDays));
      return targetDay.add(horas[idxInDay2]);
    }
  }


  void _calcularAgendamento() {
    final formatterDate = DateFormat('dd/MM/yyyy');
    final usuarioProvider = Provider.of<UsuarioProvider>(context, listen: false);

    // Campos do formulário
    final dataInicialStr = _dataInicialCtrl.text.trim();
    final horaInicialStr = _horaInicialCtrl.text.trim();
    final freqStr       = _frequenciaCtrl.text.trim();
    final qtdStr        = _qtdMedicamentoCtrl.text.trim();
    final qtdTotalStr   = _qtdMedicamentoTotalCtrl.text.trim();
    final dataFinalStr  = _dataFinalCtrl.text.trim();

    if (dataInicialStr.isEmpty || qtdStr.isEmpty) return;
    final qtdPorDose = int.tryParse(qtdStr);
    if (qtdPorDose == null || qtdPorDose <= 0) return;

    final tipoFreq = (_selectedTipoFrequencia ?? '');

    // ===================== MODO HORÁRIOS FIXOS =====================
    if (tipoFreq == 'Horários Fixos') {
      final dataInicialDate = _parseDateddMMyyyy(dataInicialStr);
      if (dataInicialDate == null) return;

      final horariosValidos = _horariosFixos.where((t) => t.trim().isNotEmpty).toList();
      if (horariosValidos.isEmpty) return;

      // ÂNCORA
      DateTime dataHoraInicial = DateTime(
        dataInicialDate.year, dataInicialDate.month, dataInicialDate.day,
      );
      final horaInicialDur = _parseHoraHHmm(horaInicialStr);
      if (horaInicialDur != null) {
        dataHoraInicial = dataHoraInicial.add(horaInicialDur);
      } else {
        final now = DateTime.now();
        final isMesmoDia = now.year == dataInicialDate.year &&
            now.month == dataInicialDate.month &&
            now.day == dataInicialDate.day;
        if (isMesmoDia) dataHoraInicial = now;
      }

      final totalQtd = qtdTotalStr.isNotEmpty ? int.tryParse(qtdTotalStr) : null;
      final dataFinalDate = dataFinalStr.isNotEmpty ? _parseDateddMMyyyy(dataFinalStr) : null;

      if (totalQtd != null && dataFinalDate == null) {
        final totalDoses = (totalQtd / qtdPorDose).floor();
        if (totalDoses <= 0) return;

        final last = _ultimaDoseHorariosFixosAncorada(
          dataHoraInicial: dataHoraInicial,
          horariosHHmm: horariosValidos,
          totalDoses: totalDoses,
        );
        _dataFinalCtrl.text = formatterDate.format(last);
        return;
      }

      if (totalQtd == null && dataFinalDate != null) {
        final lembretes = _gerarLembretesFixos(
          dataInicial: dataHoraInicial,
          horariosHHmm: horariosValidos,
          dataFinalInclusiva: dataFinalDate,
        );
        final totalDoses = lembretes.length;
        final novaQtdTotal = totalDoses * qtdPorDose;
        _qtdMedicamentoTotalCtrl.text = novaQtdTotal.toString();
        return;
      }

      if (totalQtd != null && dataFinalDate != null) {
        final lembretes = _gerarLembretesFixos(
          dataInicial: dataHoraInicial,
          horariosHHmm: horariosValidos,
          dataFinalInclusiva: dataFinalDate,
        );
        final dosesEsperadas = lembretes.length;
        final qtdEsperada = dosesEsperadas * qtdPorDose;

        if (qtdEsperada != totalQtd) {
          final totalDoses = (totalQtd / qtdPorDose).floor();
          if (totalDoses <= 0) return;

          final last = _ultimaDoseHorariosFixosAncorada(
            dataHoraInicial: dataHoraInicial,
            horariosHHmm: horariosValidos,
            totalDoses: totalDoses,
          );
          _dataFinalCtrl.text = formatterDate.format(last);
        }
        return;
      }
      return;
    }

    // ===================== MODO JUNTO COM REFEIÇÕES (NOVO) =====================
    if (tipoFreq == 'Junto com Refeições') {
      final dataInicialDate = _parseDateddMMyyyy(dataInicialStr);
      if (dataInicialDate == null) return;

      if (_refeicoesSelecionadas.isEmpty) return; // UI já valida, aqui só garante

      // Quantas doses por dia? (uma por refeição selecionada)
      final dosesPorDia = _refeicoesSelecionadas.length;
      if (dosesPorDia <= 0) return;

      final totalQtd   = qtdTotalStr.isNotEmpty ? int.tryParse(qtdTotalStr) : null;
      final dataFinalDate =
      dataFinalStr.isNotEmpty ? _parseDateddMMyyyy(dataFinalStr) : null;

      // Só total -> calcula data final (contagem por dias)
      if (totalQtd != null && dataFinalDate == null) {
        final totalDoses = (totalQtd / qtdPorDose).floor(); // p.ex. 10/1 = 10 doses
        if (totalDoses <= 0) return;

        // dias necessários = ceil(totalDoses / dosesPorDia)
        final diasNecessarios =
        (totalDoses / dosesPorDia).ceil(); // inclui o dia inicial
        final lastDay = dataInicialDate.add(Duration(days: diasNecessarios - 1));

        _dataFinalCtrl.text = DateFormat('dd/MM/yyyy').format(lastDay);
        return;
      }

      // Só data final -> calcula qtd total (contagem por dias)
      if (totalQtd == null && dataFinalDate != null) {
        // diferença inclusiva em dias
        final diffDias = dataFinalDate
            .difference(DateTime(
            dataInicialDate.year, dataInicialDate.month, dataInicialDate.day))
            .inDays + 1;
        if (diffDias <= 0) return;

        final totalDoses = diffDias * dosesPorDia; // ex.: 5 dias * 2 ref = 10 doses
        final novaQtdTotal = totalDoses * qtdPorDose;
        _qtdMedicamentoTotalCtrl.text = novaQtdTotal.toString();
        return;
      }

      // Ambos informados -> valida; se divergir, recalcula data final pela contagem por dias
      if (totalQtd != null && dataFinalDate != null) {
        final diffDias = dataFinalDate
            .difference(DateTime(
            dataInicialDate.year, dataInicialDate.month, dataInicialDate.day))
            .inDays + 1;
        if (diffDias <= 0) return;

        final dosesEsperadas = diffDias * dosesPorDia;
        final qtdEsperada = dosesEsperadas * qtdPorDose;

        if (qtdEsperada != totalQtd) {
          final totalDoses = (totalQtd / qtdPorDose).floor();
          if (totalDoses <= 0) return;

          final diasNecessarios = (totalDoses / dosesPorDia).ceil();
          final lastDay =
          dataInicialDate.add(Duration(days: diasNecessarios - 1));
          _dataFinalCtrl.text = DateFormat('dd/MM/yyyy').format(lastDay);
        }
        return;
      }

      // nenhum dos dois informado -> nada a calcular aqui
      return;
    }


    // ===================== MODO INTERVALOS FIXOS (já existente) =====================
    try {
      if (horaInicialStr.isEmpty || freqStr.isEmpty) return;

      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      final dataInicial = formatter.parse('$dataInicialStr $horaInicialStr');

      final horaStr = freqStr.split(':').first; // "8" de "8" ou "8:00"
      final frequenciaHoras = int.parse(horaStr);

      final totalQtd = qtdTotalStr.isNotEmpty ? int.tryParse(qtdTotalStr) : null;
      final dataFinal =
      dataFinalStr.isNotEmpty ? formatterDate.parse(dataFinalStr) : null;

      // 1) Só qtdTotal → calcula dataFinal
      if (totalQtd != null && dataFinal == null) {
        final totalDoses = (totalQtd / qtdPorDose).floor();
        final novaDataFinal = _calcularDataFinal(
          dataInicial,
          frequenciaHoras,
          totalDoses,
        );
        _dataFinalCtrl.text = formatterDate.format(novaDataFinal);
        return;
      }

      // 2) Só dataFinal → calcula qtdTotal
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

      // 3) Ambos → valida; se divergir, recalcula dataFinal
      if (totalQtd != null && dataFinal != null) {
        final totalDosesEsperadas = _calcularTotalDoses(
          dataInicial,
          dataFinal,
          frequenciaHoras,
        );
        final qtdEsperada = totalDosesEsperadas * qtdPorDose;

        if (qtdEsperada != totalQtd) {
          final totalDoses = (totalQtd / qtdPorDose).floor();
          final novaDataFinal = _calcularDataFinal(
            dataInicial,
            frequenciaHoras,
            totalDoses,
          );
          _dataFinalCtrl.text = formatterDate.format(novaDataFinal);
        }
      }
    } catch (_) {
      // parse error -> ignora
    }
  }

  void _salvarTratamento(UsuarioProvider usuarioProvider) async {
    final isValid1 = _formKeyIndexUm.currentState?.validate() ?? false;
    final isValid2 = _formKeyIndexDois.currentState?.validate() ?? false;
    final isValid3 = _formKeyIndexTres.currentState?.validate() ?? false;

    if (!isValid1 || !isValid2 || !isValid3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    final controller = SalvarTratamento(
      usuarioProvider: usuarioProvider,
      nomeMedicamento: _nameMedicamentoCtrl.text,
      tipoMedicamento: _selectedTipo ?? "",
      concentracaoMedicamento: '${_nameDosagemCtrl.text.trim()} ${_selectedUnidadesMedida!}',
      qtdMedicamento: _qtdMedicamentoCtrl.text.trim(),
      qtdMedicamentoTotal: _qtdMedicamentoTotalCtrl.text.trim(),
      tipoTratamento: _selectedTipoTratamento,
      frequenciaHoras: _frequenciaCtrl.text.trim(),
      horariosFixos: _horariosFixos,
      dataInicial: _dataInicialCtrl.text.trim(),
      horaInicial: _horaInicialCtrl.text.trim(),
      idCuidador: "_idCuidador",
      observacoes: _observacaoCtrl.text.trim(),
      qtdMedicamentoEstoqueCtrl: _qtdMedicamentoEstoqueCtrl.text.trim(),
      qtdEstoqueMinimoCtrl: _qtdEstoqueMinimoCtrl.text.trim(),
      dataValidadeCtrl: _dataValidadeCtrl.text.trim(),
      unidadeMedida: _selectedUnidadesMedidaLembrete ?? "",
      tipoFrequencia: _selectedTipoFrequencia ?? "",
      refeicoesSelecionadas: _refeicoesSelecionadas,
      isContinuo: _selectedTipoTratamento == 'Tratamento Contínuo',
      janelaPreGeracaoDias: 15,
    );

    try {
      if (widget.idTratamento == null) {
        await controller.criarTratamentoComLembretes();
      } else {
        await controller.atualizarTratamento(idTratamento: widget.idTratamento!);
      }
      widget.onConcluir();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao salvar tratamento')),
      );
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

  int _calcularTotalDoses(
      DateTime dataInicial,
      DateTime dataFinal,
      int frequenciaHoras,
      ) {
    final duracaoHoras = dataFinal.difference(dataInicial).inHours;
    return (duracaoHoras / frequenciaHoras).floor() + 1;
  }
}
