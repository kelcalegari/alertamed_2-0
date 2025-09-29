import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../shared/widgets/custom_seletor_field.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../themes/app_colors.dart';
import '../../../../../providers/user_data_provider.dart';
import '../../service/catalogo_service.dart';

class FormularioTratamento extends StatefulWidget {
  final GlobalKey<FormState> formKeyIndexUm;
  final TextEditingController nameMedicamentoCtrl;
  final TextEditingController nameDosagemCtrl;

  // props do pai continuam válidas (usadas como fallback)
  final String? selectedTipo;
  final List<String> vectorTipo;
  final String? selectedUnidadesMedida;
  final List<String> vectorUnidadesMedida;
  final String? selectedTipoTratamento;
  final List<String> vectorTipoTratamento;
  final String? selectedTipoFrequencia;
  final List<String> vectorTipoFrequencia;

  // callbacks existentes (seguem funcionando; mas não são obrigatórios pro fluxo local)
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
  // ---------- Autocomplete ----------
  final _focusNome = FocusNode();
  final _catalog = MedicationCatalogService();
  Timer? _debounce;

  List<Map<String, dynamic>> _sugestoes = [];
  String? _medDocPath;

  // ---------- Estado local de seleção ----------
  // Vetores/seleções locais (se vazios, caem no que veio do pai)
  List<String> _tiposLocais = [];
  String? _selectedTipoLocal;

  List<String> _unidadesLocais = [];
  String? _selectedUnidadeLocal;

  // Getters que priorizam local e caem pro pai
  List<String> get _tiposParaUI =>
      _tiposLocais.isNotEmpty ? _tiposLocais : widget.vectorTipo;
  String? get _tipoSelecionadoUI =>
      _selectedTipoLocal ?? widget.selectedTipo;

  List<String> get _unidadesParaUI =>
      _unidadesLocais.isNotEmpty ? _unidadesLocais : widget.vectorUnidadesMedida;
  String? get _unidadeSelecionadaUI =>
      _selectedUnidadeLocal ?? widget.selectedUnidadesMedida;
  final GlobalKey _sugestoesKey = GlobalKey();

  bool _isPointInsideSugestoes(Offset globalPos) {
    final ctx = _sugestoesKey.currentContext;
    if (ctx == null) return false;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    return rect.contains(globalPos);
  }
  @override
  void initState() {
    super.initState();
    _focusNome.addListener(() {
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();

    _focusNome.dispose();
    super.dispose();
  }

  // ---------- Autocomplete: digitação ----------
  void _onNomeChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final uid = context.read<UsuarioProvider>().userId;
      final res = await _catalog.searchByPrefix(query: value, userId: uid);
      if (!mounted) return;
      setState(() => _sugestoes = res); // apenas isso
    });
  }




  // ---------- Aplicação da seleção do catálogo ----------
  void _onSelecionarMedicamento(Map<String, dynamic> med) {
    // Atualiza nome e guarda path
    widget.nameMedicamentoCtrl.text = (med['nome'] ?? '').toString();
    _medDocPath = (med['_path'] ?? '').toString();

    // Helpers locais para mesclar sem duplicar e preservar ordem
    List<String> dedupPreservandoOrdem(Iterable<String> xs) {
      final seen = <String>{};
      final out = <String>[];
      for (final x in xs) {
        final v = x.trim();
        if (v.isEmpty) continue;
        if (seen.add(v)) out.add(v);
      }
      return out;
    }

    List<String> mergePrioritizando(List<String> base, List<String> top) {
      // 'top' vem primeiro, depois 'base', sem duplicatas
      return dedupPreservandoOrdem([...top, ...base]);
    }

    final formas = (med['formas'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (formas.isEmpty) {
      // Mesmo sem formas, apenas fecha sugestões e desfoca
      setState(() => _sugestoes = []);
      FocusScope.of(context).unfocus();
      return;
    }

    // Tipos "possíveis" vindos do catálogo
    final tiposPossiveis = <String>[
      for (final f in formas)
        if ((f['tipo'] ?? '').toString().trim().isNotEmpty) (f['tipo'] as String),
    ];

    // Tipo provável (primeiro das formas)
    String? tipoProvavel = tiposPossiveis.isNotEmpty ? tiposPossiveis.first : null;

    // Descobre a forma selecionada (caso exista tipo provável)
    Map<String, dynamic> formaSel = formas.first;
    if (tipoProvavel != null) {
      formaSel = formas.firstWhere(
            (f) => f['tipo'] == tipoProvavel,
        orElse: () => formas.first,
      );
    }

    // Unidades e concentrações da forma selecionada
    final unidadesPossiveis = (formaSel['unidades'] as List?)
        ?.map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList() ??
        const [];

    final concs = (formaSel['concentracoes'] as List?)
        ?.map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList() ??
        const [];

    // Tenta inferir dosagem e unidade a partir da 1ª concentração (ex.: "500 mg")
    String? unidadeInf;
    if (concs.isNotEmpty) {
      final m = RegExp(r'^([\d,.]+)\s*([^\d\s].*)$').firstMatch(concs.first);
      if (m != null) {
        widget.nameDosagemCtrl.text = m.group(1)!.replaceAll(',', '.');
        unidadeInf = m.group(2)!.trim();
      }
    }

    // --- MERGE TIPOS: prioriza prováveis no topo, mas mantém todos do pai ---
    final todosTiposOrdenados = mergePrioritizando(widget.vectorTipo, tiposPossiveis);

    // Seleção de tipo:
    // 1) mantém seleção atual se ainda existir
    // 2) senão, usa o provável
    // 3) senão, mantém a seleção do pai (se existir na lista)
    String? tipoSel = _selectedTipoLocal ?? widget.selectedTipo;
    if (tipoSel != null && !todosTiposOrdenados.contains(tipoSel)) {
      tipoSel = null;
    }
    tipoSel ??= tipoProvavel ?? (widget.selectedTipo != null &&
        todosTiposOrdenados.contains(widget.selectedTipo!)
        ? widget.selectedTipo
        : null);

    // --- MERGE UNIDADES: prioriza prováveis no topo, mas mantém todas do pai ---
    final todasUnidadesOrdenadas =
    mergePrioritizando(widget.vectorUnidadesMedida, unidadesPossiveis);

    // Seleção de unidade:
    // 1) mantém seleção atual se ainda existir
    // 2) senão, usa a inferida (se existir na lista)
    // 3) senão, primeira disponível
    String? unidadeSel = _selectedUnidadeLocal ?? widget.selectedUnidadesMedida;
    if (unidadeSel != null && !todasUnidadesOrdenadas.contains(unidadeSel)) {
      unidadeSel = null;
    }
    if (unidadeSel == null && unidadeInf != null && todasUnidadesOrdenadas.contains(unidadeInf)) {
      unidadeSel = unidadeInf;
    }
    unidadeSel ??= todasUnidadesOrdenadas.isNotEmpty ? todasUnidadesOrdenadas.first : null;

    setState(() {
      // Atualiza vetores locais com merge (prováveis no topo)
      _tiposLocais = todosTiposOrdenados;
      _selectedTipoLocal = tipoSel;

      _unidadesLocais = todasUnidadesOrdenadas;
      _selectedUnidadeLocal = unidadeSel;

      // Fecha a lista de sugestões
      _sugestoes = [];
    });

    // Sai do foco do campo
    FocusScope.of(context).unfocus();

    // Callbacks do pai (mantidos)
    if (_selectedTipoLocal != null) widget.onTipoChanged(_selectedTipoLocal);
    if (_selectedUnidadeLocal != null) widget.onUnidadesMedidaChanged(_selectedUnidadeLocal);
  }


  @override
  Widget build(BuildContext context) {
    final isDoseUnica =
        widget.selectedTipoTratamento == 'Tratamento Dose única';

    // filtra opções de frequência se Dose Única
    final List<String> freqAll = widget.vectorTipoFrequencia;
    final List<String> freqOptions = isDoseUnica
        ? freqAll.where((f) => f != 'Intervalos Fixos').toList()
        : freqAll;

    if (isDoseUnica &&
        widget.selectedTipoFrequencia == 'Intervalos Fixos' &&
        freqOptions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onTipoFrequenciaChanged(freqOptions.first);
      });
    }

    final tiposUI = _tiposParaUI;
    final tipoSelUI = _tipoSelecionadoUI;
    final unidadesUI = _unidadesParaUI;
    final unidadeSelUI = _unidadeSelecionadaUI;

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

            // ===== NOME com autocomplete interno =====
            CustomTextField(
              ctrl: widget.nameMedicamentoCtrl,
              label: "Nome do Medicamento",
              hint: "Digite o nome",
              pad: 0,
              onTapOutside: (event) {
                // Se clicou dentro da área da lista, não feche
                if (_isPointInsideSugestoes(event.position)) return;
                if (mounted) setState(() => _sugestoes = []);
                _focusNome.unfocus();
              },
              textInputType: TextInputType.text,
              focusNode: _focusNome,
              onChanged: _onNomeChanged,
              validador: (value) =>
              value == null || value.trim().isEmpty ? "Informe o nome do medicamento" : null,

              bottom: (_sugestoes.isNotEmpty && _focusNome.hasFocus)
                  ? Container(
                key: _sugestoesKey, // <<<<<< AQUI
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _sugestoes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = _sugestoes[i];
                    final nome = (m['nome'] ?? '').toString();
                    final isCustom = m['_isCustom'] == true;
                    return ListTile(
                      dense: true,
                      title: Text(nome),
                      subtitle: isCustom ? const Text('Catálogo do usuário') : null,
                      onTap: () => _onSelecionarMedicamento(m),
                    );
                  },
                ),
              )
                  : null,
            ),

            const SizedBox(height: 12),

            // ===== TIPO (usa locais se existirem) =====
            CustomSelectorField<String>(
              selectedValue: tipoSelUI,
              items: tiposUI
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _selectedTipoLocal = v;
                  // quando troca tipo, zera/unidades pela nova forma se tivermos catálogo carregado
                  // NOTA: como não persistimos as 'formas' aqui, mantemos a seleção e deixamos o pai tratar se necessário
                });
                widget.onTipoChanged(v);
              },
              label: "Tipo de Medicação",
              hint: tiposUI.isNotEmpty ? tiposUI.first : "Selecione",
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

                // ===== UNIDADE (usa locais se existirem) =====
                Flexible(
                  flex: 2,
                  child: CustomSelectorField<String>(
                    selectedValue: unidadeSelUI,
                    items: unidadesUI
                        .map((g) =>
                        DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedUnidadeLocal = v);
                      widget.onUnidadesMedidaChanged(v);
                    },
                    hint: unidadesUI.isNotEmpty ? unidadesUI.first : "unidade",
                    pad: 0,
                    validador: (value) => value == null
                        ? "Informe a Unidade de Medida"
                        : null,
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
              items: freqOptions
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: widget.onTipoFrequenciaChanged,
              label: "Tipo de Frequência",
              hint: freqOptions.isNotEmpty ? freqOptions.first : null,
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
