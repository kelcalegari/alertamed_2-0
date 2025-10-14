import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:diacritic/diacritic.dart';
import 'package:intl/intl.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';

import '../service/salvar_tratamento.dart';
import 'widgets_gerenciamento_tratamento/agendamento_tratamento_card.dart';
import 'widgets_gerenciamento_tratamento/formulario_tratamento_card.dart';
import 'widgets_gerenciamento_tratamento/informacoes_tratamento_card.dart';

// ------------------------------------------------------------
// Helpers & Types
// ------------------------------------------------------------

enum TipoTratamento {
  determinado,
  continuo,
  doseUnica,
}

extension TipoTratamentoX on TipoTratamento {
  String get label => switch (this) {
    TipoTratamento.determinado => 'Tratamento Determinado',
    TipoTratamento.continuo => 'Tratamento Contínuo',
    TipoTratamento.doseUnica => 'Tratamento Dose única',
  };

  static TipoTratamento fromLabel(String? s) {
    return switch (s) {
      'Tratamento Contínuo' => TipoTratamento.continuo,
      'Tratamento Dose única' => TipoTratamento.doseUnica,
      _ => TipoTratamento.determinado,
    };
  }
}

enum TipoFrequencia {
  intervalosFixos,
  horariosFixos,
  refeicoes,
}

extension TipoFrequenciaX on TipoFrequencia {
  String get label => switch (this) {
    TipoFrequencia.intervalosFixos => 'Intervalos Fixos',
    TipoFrequencia.horariosFixos => 'Horários Fixos',
    TipoFrequencia.refeicoes => 'Junto com Refeições',
  };

  static TipoFrequencia fromLabel(String? s) {
    return switch (s) {
      'Horários Fixos' => TipoFrequencia.horariosFixos,
      'Junto com Refeições' => TipoFrequencia.refeicoes,
      _ => TipoFrequencia.intervalosFixos,
    };
  }
}

class _TimeUtils {
  static DateTime? parseDate(String d) {
    final p = d.split('/');
    if (p.length != 3) return null;
    final dia = int.tryParse(p[0]);
    final mes = int.tryParse(p[1]);
    final ano = int.tryParse(p[2]);
    if (dia == null || mes == null || ano == null) return null;
    return DateTime(ano, mes, dia);
  }

  static Duration? parseHHmm(String h) {
    final p = h.split(':');
    if (p.length != 2) return null;
    final hh = int.tryParse(p[0]);
    final mm = int.tryParse(p[1]);
    if (hh == null || mm == null) return null;
    return Duration(hours: hh, minutes: mm);
  }
}

// --------- Parsers extras (robustos) ----------
String _asIntString(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  if (v is int || v is double) return v.toString();
  final s = v.toString().trim();
  final m = RegExp(r'(\d{1,3})').firstMatch(s);
  return m != null ? m.group(1)! : fallback;
}

String? _asHHmm(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(s);
  if (m == null) return null;
  final hh = int.parse(m.group(1)!);
  final mm = int.parse(m.group(2)!);
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return null;
  return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

// ------------------------------------------------------------
// Scheduler (cálculos isolados)
// ------------------------------------------------------------
class _Scheduler {
  final DateFormat fmtDia = DateFormat('dd/MM/yyyy');

  List<DateTime> gerarLembretesFixos({
    required DateTime dataInicial,
    required List<String> horariosHHmm,
    int? totalDoses,
    DateTime? dataFinalInclusiva,
  }) {
    assert((totalDoses != null) ^ (dataFinalInclusiva != null),
    'Informe totalDoses XOR dataFinalInclusiva');

    final horas = horariosHHmm
        .map(_TimeUtils.parseHHmm)
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
        23,
        59,
        59,
        999,
      );
      return !dt.isAfter(endOfDay);
    }

    while (true) {
      for (final h in horas) {
        final dt = DateTime(dia.year, dia.month, dia.day).add(h);
        if (dt.isBefore(dataInicial)) continue;
        if (!dentroDoPeriodo(dt)) return result;
        result.add(dt);
        if (totalDoses != null && result.length >= totalDoses) return result;
      }
      dia = dia.add(const Duration(days: 1));
      if (result.length > 20000) return result; // para evitar loops infinitos
    }
  }

  DateTime ultimaDoseHorariosFixosAncorada({
    required DateTime dataHoraInicial,
    required List<String> horariosHHmm,
    required int totalDoses,
  }) {
    final horas = horariosHHmm
        .map(_TimeUtils.parseHHmm)
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

  DateTime calcularDataFinalIntervalo(
      DateTime dataInicial, int frequenciaHoras, int totalDoses) {
    final duracaoTotalHoras = (totalDoses - 1) * frequenciaHoras;
    return dataInicial.add(Duration(hours: duracaoTotalHoras));
  }

  int calcularTotalDosesIntervalo(
      DateTime dataInicial, DateTime dataFinal, int frequenciaHoras) {
    final duracaoHoras = dataFinal.difference(dataInicial).inHours;
    return (duracaoHoras / frequenciaHoras).floor() + 1;
  }
}

// ------------------------------------------------------------
// Widget Principal
// ------------------------------------------------------------
class GerenciadorTratamento extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onConcluir;
  final String? idTratamento; // null => criação; não-null => edição

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
  // ----------------- Constantes/UI Choices -----------------
  static const _totalPages = 3;

  final _vectorTipo = const [
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

  final _vectorUnidadesMedida = const [
    'mg',
    'g',
    'mcg',
    'mL',
    'L',
    'UI',
  ];

  final _vectorTipoTratamento = const [
    'Tratamento Determinado',
    'Tratamento Contínuo',
    'Tratamento Dose única',
  ];

  final _vectorTipoFrequencia = const [
    'Intervalos Fixos',
    'Horários Fixos',
    'Junto com Refeições',
  ];



  // ----------------- Form State -----------------
  int _currentIndex = 0;
  bool _showHint = true;
  bool _estoquePrefillDone = false;
  String? idMedicamento;

  // selections
  String? _selectedTipo;
  String? _selectedUnidadesMedida;
  String? _selectedTipoTratamento;
  String? _selectedTipoFrequencia;


  // controllers
  final _formKeyIndexUm = GlobalKey<FormState>();
  final _formKeyIndexDois = GlobalKey<FormState>();
  final _formKeyIndexTres = GlobalKey<FormState>();

  final _nameMedicamentoCtrl = TextEditingController();
  final _nameDosagemCtrl = TextEditingController(text: '1');
  final _frequenciaCtrl = TextEditingController(text: '8');
  final _qtdMedicamentoCtrl = TextEditingController(text: '1');
  final _qtdMedicamentoTotalCtrl = TextEditingController(text: '1');
  final _dataInicialCtrl = TextEditingController(
    text: DateFormat('dd/MM/yyyy').format(DateTime.now()),
  );
  final _dataFinalCtrl = TextEditingController();
  final _horaInicialCtrl = TextEditingController(
    text: DateFormat('HH:mm').format(
      DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  final _qtdMedicamentoEstoqueCtrl = TextEditingController();
  final _qtdEstoqueMinimoCtrl = TextEditingController(text: '5');
  final _dataValidadeCtrl = TextEditingController();
  final _observacaoCtrl = TextEditingController();

  // dados de agendamento
  List<String> _horariosFixos = [];
  List<String> _refeicoesSelecionadas = []; // 'cafe' | 'almoco' | 'jantar'

  // animations
  late final AnimationController _animationController;
  late final Animation<Offset> _offsetAnimation;

  // services
  final _scheduler = _Scheduler();

  // ----------------- Lifecycle -----------------
  @override
  void initState() {
    super.initState();

    // defaults
    _selectedTipo = _vectorTipo.first;
    _selectedUnidadesMedida = _vectorUnidadesMedida.first;
    _selectedTipoTratamento = _vectorTipoTratamento.first;
    _selectedTipoFrequencia = _vectorTipoFrequencia.first;


    _initHintAnimation();

    // Edição: carrega dados do Provider após build
    if (widget.idTratamento != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final prov = Provider.of<UsuarioProvider>(context, listen: false);
        final t = prov.tratamentosMap[widget.idTratamento];
        if (t != null) _preencherCamposParaEdicao(t);
      });
    }
  }

  void _initHintAnimation() {
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

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showHint = false);
      _animationController.stop();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();

    for (final c in [
      _nameMedicamentoCtrl,
      _nameDosagemCtrl,
      _frequenciaCtrl,
      _qtdMedicamentoCtrl,
      _qtdMedicamentoTotalCtrl,
      _dataInicialCtrl,
      _dataFinalCtrl,
      _horaInicialCtrl,
      _qtdMedicamentoEstoqueCtrl,
      _qtdEstoqueMinimoCtrl,
      _dataValidadeCtrl,
      _observacaoCtrl,
    ]) {
      c.dispose();
    }

    super.dispose();
  }

  // ----------------- Builders -----------------
  @override
  Widget build(BuildContext context) {
    final usuarioProvider = Provider.of<UsuarioProvider>(context, listen: false);
    return GestureDetector(
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
    );
  }

  Widget _buildCard({bool showHint = false, required Widget child}) {
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
              child: const Column(
                children: [
                  Icon(
                    Icons.keyboard_arrow_up,
                    size: 28,
                    color: AppColors.textVerde,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Deslize para cima',
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
      onUnidadesMedidaChanged: (value) =>
          setState(() => _selectedUnidadesMedida = value),
      onTipoTratamentoChanged: (value) {
        setState(() {
          _selectedTipoTratamento = value;
          // Se virar Dose única e estava em Intervalos Fixos, ajusta para Horários Fixos
          if (value == 'Tratamento Dose única' &&
              _selectedTipoFrequencia == 'Intervalos Fixos') {
            _selectedTipoFrequencia = 'Horários Fixos';
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
      selectedTipoTratamento: _selectedTipoTratamento ?? '',
      selectedTipoFrequencia: _selectedTipoFrequencia ?? '',
      onHorariosFixosChanged: (horas) => setState(() => _horariosFixos = horas),
      onRefeicoesChanged: (refs) =>
          setState(() => _refeicoesSelecionadas = refs),
    );
  }

  Widget _buildInformacoesAdicionais(UsuarioProvider usuarioProvider) {
    return InformacoesAdicionais(
      formKeyIndexTres: _formKeyIndexTres,
      qtdMedicamentoEstoqueCtrl: _qtdMedicamentoEstoqueCtrl,
      qtdEstoqueMinimoCtrl: _qtdEstoqueMinimoCtrl,
      dataValidadeCtrl: _dataValidadeCtrl,
      observacaoCtrl: _observacaoCtrl,
      selectedUnidadesMedida: _selectedUnidadesMedida,
      vectorUnidadesMedida: _vectorUnidadesMedida,

      onConcluir: widget.onConcluir,
      onUnidadesMedidaChanged:
          (val) => setState(() => _selectedUnidadesMedida = val),

      onPressedSalvar: () async => _salvarTratamento(usuarioProvider),
    );
  }

  // ----------------- Actions & Logic -----------------
  void _onVerticalDrag(DragEndDetails details) {
    final v = details.primaryVelocity;
    if (v == null) return;

    if (v < 0 && _currentIndex < _totalPages - 1) {
      // indo para próxima página
      if (_currentIndex == 0) {
        final ok = _formKeyIndexUm.currentState?.validate() ?? false;
        if (!ok) return;
        // gera id de medicamento e tenta prefill do estoque
        idMedicamento = _gerarIdMedicamento(
          _nameMedicamentoCtrl.text,
          '${_nameDosagemCtrl.text.trim()} ${_selectedUnidadesMedida!}',
          _selectedTipo!,
        );
        _prefillEstoqueSeDisponivel();
      }
      if (_currentIndex == 1) {
        final ok = _formKeyIndexDois.currentState?.validate() ?? false;
        if (!ok) return;
        _calcularAgendamento();
      }
      setState(() => _currentIndex++);
    } else if (v > 0 && _currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  String _gerarIdMedicamento(String nome, String conc, String tipo) {
    final normalized = [nome, conc, tipo]
        .map((s) => removeDiacritics(s)
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' '))
        .join('|');
    return normalized.toString();
  }

  Future<void> _prefillEstoqueSeDisponivel() async {
    if (_estoquePrefillDone) return;

    final prov = Provider.of<UsuarioProvider>(context, listen: false);
    final String? userId = prov.userId;
    final String? idMed = idMedicamento;

    if (userId == null || userId.isEmpty || idMed == null || idMed.isEmpty) {
      return;
    }

    // 1) Provider cache
    if (prov.estoqueMap.containsKey(idMed)) {
      final raw = prov.estoqueMap[idMed];
      if (raw is Map) {
        _aplicarPrefillEstoque(Map<String, dynamic>.from(raw));
        _estoquePrefillDone = true;
        return;
      }
    }

    // 2) Firestore
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userId)
          .collection('estoque')
          .doc(idMed)
          .get();
      if (!mounted) return;
      if (doc.exists) {
        final data = (doc.data() ?? {});
        _aplicarPrefillEstoque(data);
        prov.estoqueMap[idMed] = data; // cache local opcional
        _estoquePrefillDone = true;
      }
    } catch (e) {
      debugPrint('Falha ao carregar estoque: $e');
    }
  }

  void _aplicarPrefillEstoque(Map<String, dynamic> e) {
    // qtdAtual
    final dynamic qtdAtualDyn = e['qtdAtual'];
    final sQtdAtual = (qtdAtualDyn == null)
        ? ''
        : (qtdAtualDyn is num)
        ? qtdAtualDyn.toString()
        : qtdAtualDyn.toString();
    if (_qtdMedicamentoEstoqueCtrl.text.isEmpty && sQtdAtual.isNotEmpty) {
      _qtdMedicamentoEstoqueCtrl.text = sQtdAtual;
    }

    // qtdMinima
    final dynamic qtdMinDyn = e['qtdMinima'];
    final sQtdMin = (qtdMinDyn == null)
        ? ''
        : (qtdMinDyn is num)
        ? qtdMinDyn.toString()
        : qtdMinDyn.toString();
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
    // -------- Nome / tipo
    _nameMedicamentoCtrl.text = (t['nomeMedicamento'] ?? '').toString();

    final tipoMed = (t['tipoMedicamento'] ?? _selectedTipo) as String?;
    if (tipoMed != null && tipoMed.isNotEmpty) {
      _selectedTipo = tipoMed;
    }

    // -------- Concentração (ex.: "10 mg" → valor + unidade normalizada)
    final conc = (t['concentracaoMedicamento'] ?? '').toString().trim();
    if (conc.isNotEmpty) {
      final m = RegExp(r'^\s*([\d.,]+)\s*([^\d\s].*)$').firstMatch(conc);
      if (m != null) {
        _nameDosagemCtrl.text = m.group(1)!.replaceAll(',', '.');

        String unidade = m.group(2)!.trim();
        // normalizações frequentes
        unidade = unidade
            .replaceAll('µg', 'mcg')
            .replaceAll('μg', 'mcg')
            .replaceAll('ML', 'mL')
            .replaceAll('Ml', 'mL')
            .replaceAll('ml', 'mL')
            .replaceAll('l', 'L')
            .trim();

        if (_vectorUnidadesMedida.contains(unidade)) {
          _selectedUnidadesMedida = unidade;
        }
      }
    }

    // -------- Tipo de tratamento / frequência
    final tt = (t['tipoTratamento'] ?? _selectedTipoTratamento) as String?;
    if (tt != null && tt.isNotEmpty) _selectedTipoTratamento = tt;

    final tf = (t['tipoFrequencia'] ?? _selectedTipoFrequencia) as String?;
    if (tf != null && tf.isNotEmpty) _selectedTipoFrequencia = tf;

    // Regra: se for Dose única e tiver vindo "Intervalos Fixos", força "Horários Fixos"
    if (_selectedTipoTratamento == 'Tratamento Dose única' &&
        _selectedTipoFrequencia == 'Intervalos Fixos') {
      _selectedTipoFrequencia = 'Horários Fixos';
    }

    // -------- Datas
    DateTime? dIni;
    DateTime? dFim;
    final dtIni = t['dataInicio'];
    final dtFim = t['dataTermino'];

    if (dtIni is Timestamp) dIni = dtIni.toDate();
    if (dtIni is DateTime) dIni = dtIni;

    if (dtFim is Timestamp) dFim = dtFim.toDate();
    if (dtFim is DateTime) dFim = dtFim;

    if (dIni != null) _dataInicialCtrl.text = DateFormat('dd/MM/yyyy').format(dIni);
    if (dFim != null) _dataFinalCtrl.text = DateFormat('dd/MM/yyyy').format(dFim);

    // -------- Lembretes / modos
    String? horaInicialInferida;
    _horariosFixos = [];
    _refeicoesSelecionadas = [];

    final lembs = (t['lembretes'] is List)
        ? List<Map<String, dynamic>>.from(t['lembretes'])
        : const <Map<String, dynamic>>[];

    if (_selectedTipoFrequencia == 'Horários Fixos') {
      final horas = <String>{};
      for (final e in lembs) {
        final v = _asHHmm(e['valor']) ?? _asHHmm(e['hora']) ?? _asHHmm(e['hhmm']);
        if (v != null) horas.add(v);
      }
      final list = horas.toList()..sort();
      _horariosFixos = list;
      if (list.isNotEmpty) horaInicialInferida = list.first;

      // fallback: se não veio pelos lembretes, tenta extrair do texto de frequencia "N× ao dia: 08:00, 20:00"
      if (_horariosFixos.isEmpty) {
        final freqTxt = (t['frequencia'] ?? '').toString();
        final matches = RegExp(r'\b(\d{1,2}:\d{2})\b').allMatches(freqTxt).map((m) => m.group(1)!).toList();
        if (matches.isNotEmpty) {
          _horariosFixos = (matches.toSet().toList()..sort());
          horaInicialInferida ??= _horariosFixos.first;
        }
      }

    } else if (_selectedTipoFrequencia == 'Junto com Refeições') {
      final momentos = <String>{};
      for (final e in lembs) {
        final m1 = (e['momento'] ?? '').toString().trim().toLowerCase();
        final m2 = (e['refeicao'] ?? '').toString().trim().toLowerCase();
        for (final m in [m1, m2]) {
          if (m == 'cafe' || m == 'almoco' || m == 'jantar') momentos.add(m);
        }
      }
      _refeicoesSelecionadas = momentos.toList()..sort();

    } else if (_selectedTipoFrequencia == 'Intervalos Fixos') {
      // frequencia em horas (aceita number ou string; ou cai no resumo "A cada X horas")
      final fH = _asIntString(
        (t['frequenciaHoras'] ?? '').toString().isNotEmpty ? t['frequenciaHoras'] : (t['frequencia'] ?? ''),
      );
      if (fH.isNotEmpty) _frequenciaCtrl.text = fH;

      // tentar inferir hora inicial da primeira ocorrência agendada
      final datas = lembs
          .map((e) => e['dataHoraAgendado'])
          .whereType<Timestamp>()
          .map((ts) => ts.toDate())
          .toList()
        ..sort();

      if (datas.isNotEmpty) {
        final first = datas.first;
        horaInicialInferida = DateFormat('HH:mm').format(first);
        if (dIni == null) {
          _dataInicialCtrl.text = DateFormat('dd/MM/yyyy').format(first);
        }
      }
      // fallback adicional
      if (horaInicialInferida == null) {
        horaInicialInferida = _asHHmm(t['horaInicial']);
      }
    }

    if (horaInicialInferida != null &&
        RegExp(r'^\d{2}:\d{2}$').hasMatch(horaInicialInferida)) {
      _horaInicialCtrl.text = horaInicialInferida;
    }

    // -------- Quantidades (robusto para strings/números grandes)
    final qd = _asIntString(t['qtdMedicamento'], fallback: _qtdMedicamentoCtrl.text);
    if (qd.isNotEmpty) _qtdMedicamentoCtrl.text = qd;

    final qt = _asIntString(t['qtdMedicamentoTotal'], fallback: _qtdMedicamentoTotalCtrl.text);
    if (qt.isNotEmpty) _qtdMedicamentoTotalCtrl.text = qt;

    // -------- Observações
    _observacaoCtrl.text = (t['observacoes'] ?? '').toString();

    // -------- Id do medicamento + prefill do estoque (edição)
    final idMedDoc = (t['idMedicamento'] ?? '').toString().trim();
    if (idMedDoc.isNotEmpty) {
      idMedicamento = idMedDoc;
    } else {
      // gera a partir dos campos já preenchidos (fallback)
      idMedicamento = _gerarIdMedicamento(
        _nameMedicamentoCtrl.text,
        '${_nameDosagemCtrl.text.trim()} ${_selectedUnidadesMedida ?? ''}'.trim(),
        _selectedTipo ?? '',
      );
    }
    // Se ainda não fizemos prefill do estoque, tenta agora
    if (!_estoquePrefillDone && (idMedicamento?.isNotEmpty ?? false)) {
      _prefillEstoqueSeDisponivel();
    }

    setState(() {});
  }


  void _calcularAgendamento() {
    final fmtDia = DateFormat('dd/MM/yyyy');

    final dataInicialStr = _dataInicialCtrl.text.trim();
    final horaInicialStr = _horaInicialCtrl.text.trim();
    final freqStr = _frequenciaCtrl.text.trim();
    final qtdStr = _qtdMedicamentoCtrl.text.trim();
    final qtdTotalStr = _qtdMedicamentoTotalCtrl.text.trim(); // ignorado em Fixos/Refeições
    final dataFinalStr = _dataFinalCtrl.text.trim();

    if (dataInicialStr.isEmpty || qtdStr.isEmpty) return;

    final qtdPorDose = int.tryParse(qtdStr);
    if (qtdPorDose == null || qtdPorDose <= 0) return;

    final tipoFreq = _selectedTipoFrequencia ?? '';

    // Helpers locais
    DateTime? _parseDate(String s) {
      try {
        return DateFormat('dd/MM/yyyy').parseStrict(s);
      } catch (_) {
        return null;
      }
    }

    Duration? _hhmm(String s) {
      final p = s.split(':');
      if (p.length != 2) return null;
      final h = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        return null;
      }
      return Duration(hours: h, minutes: m);
    }

    String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
    List<int> _toSortedMinutesUnique(Iterable<String> hhmm) {
      final mins = <int>{};
      for (final s in hhmm) {
        final d = _hhmm(s.trim());
        if (d != null) mins.add(d.inMinutes);
      }
      final list = mins.toList()..sort();
      return list;
    }

    final now = DateTime.now();
    final nowPlus10 = now.add(const Duration(minutes: 10));
    final hojeKey = _dayKey(now);

    // -------------------- HORÁRIOS FIXOS --------------------
    if (tipoFreq == 'Horários Fixos') {
      final dataInicialDate = _parseDate(dataInicialStr);
      if (dataInicialDate == null) return;

      final horariosValidos =
      _horariosFixos.where((t) => t.trim().isNotEmpty).toList();
      if (horariosValidos.isEmpty) return;

      final dataFinalDate =
      dataFinalStr.isNotEmpty ? _parseDate(dataFinalStr) : null;
      if (dataFinalDate == null) return;

      final endIncl = DateTime(dataFinalDate.year, dataFinalDate.month,
          dataFinalDate.day, 23, 59, 59, 999);

      final minutes = _toSortedMinutesUnique(horariosValidos);
      if (minutes.isEmpty) return;

      int totalDoses = 0;
      DateTime dia = DateTime(
          dataInicialDate.year, dataInicialDate.month, dataInicialDate.day);

      while (!dia.isAfter(endIncl)) {
        final isHoje = _dayKey(dia) == hojeKey;
        for (final min in minutes) {
          final dt = DateTime(dia.year, dia.month, dia.day)
              .add(Duration(minutes: min));
          if (isHoje && dt.isBefore(nowPlus10)) continue; // pula hoje +10min
          if (dt.isAfter(endIncl)) break;
          totalDoses++;
        }
        dia = dia.add(const Duration(days: 1));
      }

      _qtdMedicamentoTotalCtrl.text =
          (totalDoses * qtdPorDose).toString();
      return;
    }

    // -------------------- JUNTO COM REFEIÇÕES --------------------
    if (tipoFreq == 'Junto com Refeições') {
      final dataInicialDate = _parseDate(dataInicialStr);
      if (dataInicialDate == null) return;
      if (_refeicoesSelecionadas.isEmpty) return;

      final dataFinalDate =
      dataFinalStr.isNotEmpty ? _parseDate(dataFinalStr) : null;
      if (dataFinalDate == null) return;

      // horários padrão (se não veio do provider aqui)
      final defaults = {'cafe': '07:30', 'almoco': '12:00', 'jantar': '19:00'};

      final selectedHHmm = <String>[];
      for (final r in _refeicoesSelecionadas) {
        final s = defaults[r];
        if (s != null) selectedHHmm.add(s);
      }
      final minutes = _toSortedMinutesUnique(selectedHHmm);
      if (minutes.isEmpty) return;

      final endIncl = DateTime(dataFinalDate.year, dataFinalDate.month,
          dataFinalDate.day, 23, 59, 59, 999);
      DateTime dia = DateTime(
          dataInicialDate.year, dataInicialDate.month, dataInicialDate.day);

      int totalDoses = 0;
      while (!dia.isAfter(endIncl)) {
        final isHoje = _dayKey(dia) == hojeKey;
        for (final min in minutes) {
          final dt = DateTime(dia.year, dia.month, dia.day)
              .add(Duration(minutes: min));
          if (isHoje && dt.isBefore(nowPlus10)) continue;
          if (dt.isAfter(endIncl)) break;
          totalDoses++;
        }
        dia = dia.add(const Duration(days: 1));
      }

      _qtdMedicamentoTotalCtrl.text =
          (totalDoses * qtdPorDose).toString();
      return;
    }

    // -------------------- INTERVALOS FIXOS --------------------
    try {
      if (horaInicialStr.isEmpty || freqStr.isEmpty) return;

      final formatter = DateFormat('dd/MM/yyyy HH:mm');
      final dataInicial = formatter.parse('$dataInicialStr $horaInicialStr');

      final horaStr = freqStr.split(':').first; // suporta "8" ou "8:00"
      final frequenciaHoras = int.parse(horaStr);

      final totalQtd = qtdTotalStr.isNotEmpty ? int.tryParse(qtdTotalStr) : null;
      final dataFinal = dataFinalStr.isNotEmpty
          ? DateFormat('dd/MM/yyyy').parse(dataFinalStr)
          : null;

      // Só qtdTotal → calcula dataFinal
      if (totalQtd != null && dataFinal == null) {
        final totalDoses = (totalQtd / qtdPorDose).floor();
        if (totalDoses <= 0) return;
        final novaDataFinal = _scheduler.calcularDataFinalIntervalo(
          dataInicial,
          frequenciaHoras,
          totalDoses,
        );
        _dataFinalCtrl.text = DateFormat('dd/MM/yyyy').format(novaDataFinal);
        return;
      }

      // Só dataFinal → calcula qtdTotal
      if (totalQtd == null && dataFinal != null) {
        final totalDoses = _scheduler.calcularTotalDosesIntervalo(
          dataInicial,
          dataFinal,
          frequenciaHoras,
        );
        _qtdMedicamentoTotalCtrl.text =
            (totalDoses * qtdPorDose).toString();
        return;
      }

      // Ambos → valida e ajusta se necessário
      if (totalQtd != null && dataFinal != null) {
        final totalDosesEsperadas = _scheduler.calcularTotalDosesIntervalo(
          dataInicial,
          dataFinal,
          frequenciaHoras,
        );
        final qtdEsperada = totalDosesEsperadas * qtdPorDose;
        if (qtdEsperada != totalQtd) {
          final totalDoses = (totalQtd / qtdPorDose).floor();
          if (totalDoses <= 0) return;
          final novaDataFinal = _scheduler.calcularDataFinalIntervalo(
            dataInicial,
            frequenciaHoras,
            totalDoses,
          );
          _dataFinalCtrl.text = DateFormat('dd/MM/yyyy').format(novaDataFinal);
        }
      }
    } catch (_) {
      // ignora parse errors
    }
  }

  Future<void> _salvarTratamento(UsuarioProvider usuarioProvider) async {
    final ok1 = _formKeyIndexUm.currentState?.validate() ?? false;
    final ok2 = _formKeyIndexDois.currentState?.validate() ?? false;
    final ok3 = _formKeyIndexTres.currentState?.validate() ?? false;

    if (!ok1 || !ok2 || !ok3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos obrigatórios')),
      );
      return;
    }

    final controller = SalvarTratamento(
      usuarioProvider: usuarioProvider,
      nomeMedicamento: _nameMedicamentoCtrl.text,
      tipoMedicamento: _selectedTipo ?? '',
      concentracaoMedicamento:
      '${_nameDosagemCtrl.text.trim()} ${_selectedUnidadesMedida!}',
      qtdMedicamento: _qtdMedicamentoCtrl.text.trim(),
      qtdMedicamentoTotal: _qtdMedicamentoTotalCtrl.text.trim(),
      tipoTratamento: _selectedTipoTratamento,
      frequenciaHoras: _frequenciaCtrl.text.trim(),
      horariosFixos: _horariosFixos,
      dataInicial: _dataInicialCtrl.text.trim(),
      horaInicial: _horaInicialCtrl.text.trim(),
      observacoes: _observacaoCtrl.text.trim(),
      qtdMedicamentoEstoqueCtrl: _qtdMedicamentoEstoqueCtrl.text.trim(),
      qtdEstoqueMinimoCtrl: _qtdEstoqueMinimoCtrl.text.trim(),
      dataValidadeCtrl: _dataValidadeCtrl.text.trim(),
      tipoFrequencia: _selectedTipoFrequencia ?? '',
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
      debugPrint('Erro ao salvar: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao salvar tratamento')),
      );
    }
  }
}
