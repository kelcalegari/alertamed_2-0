import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../providers/user_data_provider.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../service/catalogo_service.dart';
class MedicamentoSelecionado {
  final String nome;
  final String medDocPath;
  final List<Map<String, dynamic>> formas;
  MedicamentoSelecionado({required this.nome, required this.medDocPath, required this.formas});
}

class MedicamentoAutocomplete extends StatefulWidget {
  final TextEditingController nomeCtrl;
  final void Function(MedicamentoSelecionado m) onSelected;
  const MedicamentoAutocomplete({super.key, required this.nomeCtrl, required this.onSelected});
  @override
  State<MedicamentoAutocomplete> createState() => _MedicamentoAutocompleteState();
}

class _MedicamentoAutocompleteState extends State<MedicamentoAutocomplete> {
  final _focus = FocusNode();
  final _catalog = MedicationCatalogService();
  OverlayEntry? _ovl;
  Timer? _deb;
  List<Map<String, dynamic>> _sugs = [];

  @override void dispose(){_deb?.cancel(); _ovl?.remove(); _focus.dispose(); super.dispose();}

  void _onChanged(String v) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 250), () async {
      final uid = context.read<UsuarioProvider>().userId;
      final res = await _catalog.searchByPrefix(query: v, userId: uid);
      if (!mounted) return;
      setState(() => _sugs = res);
      _showOverlayIfNeeded();
    });
  }

  void _showOverlayIfNeeded() { /* mesmo padrão do overlay que você já fez */ }
  void _select(Map<String,dynamic> m){
    _ovl?.remove();
    widget.nomeCtrl.text = (m['nome'] ?? '').toString();
    widget.onSelected(MedicamentoSelecionado(
      nome: widget.nomeCtrl.text,
      medDocPath: (m['_path'] ?? '').toString(),
      formas: (m['formas'] as List?)?.cast<Map<String,dynamic>>() ?? const [],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CustomTextField(
      ctrl: widget.nomeCtrl,
      label: "Nome do medicamento",
      onChanged: _onChanged, textInputType: TextInputType.text,
      // passe o FocusNode se quiser
    );
  }
}
