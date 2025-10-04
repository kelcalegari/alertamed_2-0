import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../shared/modals/custom_popup.dart';
import '../service/salvar_sintomas.dart';
import '../widgets/historico_card.dart';

// Long-press handler
Future<void> onLongPressSintoma(BuildContext context, EventoHistorico e) async {
  // garante que esse card tem ID do doc
  final sintomaId = e.id;
  if (sintomaId == null) return;

  // checa janela de 15 min (server-side nas regras e client aqui)
  final pode = await podeEditarSintoma(sintomaId);
  if (!pode) {
    // reaproveita teu CustomPopup para avisar
    CustomPopup.show(
      context: context,
      title: 'Edição indisponível',
      message:
          'A edição de sintomas só é permitida até 15 minutos após o registro.',
      buttonText: 'Entendi',
    );
    return;
  }

  // abre o sheet de edição
  _abrirSheetEditarSintoma(context, sintomaId);
}

// Bottom-sheet estilo popup com formulário
void _abrirSheetEditarSintoma(BuildContext context, String sintomaId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return _EditarSintomaSheet(sintomaId: sintomaId);
    },
  );
}

// Widget do sheet (busca o doc p/ preencher, edita e salva)
class _EditarSintomaSheet extends StatefulWidget {
  final String sintomaId;
  const _EditarSintomaSheet({required this.sintomaId});

  @override
  State<_EditarSintomaSheet> createState() => _EditarSintomaSheetState();
}

class _EditarSintomaSheetState extends State<_EditarSintomaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _intensidadeCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final ref = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .collection('sintomas')
          .doc(widget.sintomaId);
      final snap = await ref.get();
      final d = snap.data() ?? {};
      _nomeCtrl.text = (d['nome'] ?? '').toString();
      _intensidadeCtrl.text = (d['intensidade'] ?? '').toString();
      _obsCtrl.text = (d['observacoes'] ?? '').toString();
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _intensidadeCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await editarSintoma(
        sintomaId: widget.sintomaId,
        nome: _nomeCtrl.text.trim().isEmpty ? null : _nomeCtrl.text.trim(),
        intensidade:
            _intensidadeCtrl.text.trim().isEmpty
                ? null
                : _intensidadeCtrl.text.trim(),
        observacoes: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
        usuarioProvider: Provider.of<UsuarioProvider>(context, listen: false),
      );
      if (mounted) {
        final provider = Provider.of<UsuarioProvider>(context, listen: false);
        await provider.refreshSintomas();
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Stack(
      children: [
        // fundo borrado
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(color: Colors.black.withOpacity(0.3)),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child:
                  _carregando
                      ? const SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator()),
                      )
                      : Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Editar sintoma',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _nomeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nome do sintoma',
                                border: OutlineInputBorder(),
                              ),
                              validator:
                                  (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Informe o nome'
                                          : null,
                            ),
                            const SizedBox(height: 10),

                            TextFormField(
                              controller: _intensidadeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Intensidade',
                                hintText: 'ex.: leve, moderada, forte ou 1–10',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),

                            TextFormField(
                              controller: _obsCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Observações',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),

                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0C1F0C),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _salvar,
                                child: const Text('Salvar alterações'),
                              ),
                            ),
                            const SizedBox(height: 8),

                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                          ],
                        ),
                      ),
            ),
          ),
        ),
      ],
    );
  }
}
