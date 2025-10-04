import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartmed/providers/user_data_provider.dart';

import '../../../shared/widgets/custom_seletor_field.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../themes/app_colors.dart';
import '../service/salvar_sintomas.dart';

class CardAdicionarSintomas extends StatefulWidget {
  final void Function() onCancel;
  final void Function(String sintoma, int intensidade, String observacao) onSave;

  const CardAdicionarSintomas({
    super.key,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<CardAdicionarSintomas> createState() => _CardAdicionarSintomasState();
}

class _CardAdicionarSintomasState extends State<CardAdicionarSintomas> {
  final TextEditingController sintomaController = TextEditingController();
  final TextEditingController observacaoController = TextEditingController();
  String? intensidadeSelecionada = 'Média';
  bool _isSaving = false;

  @override
  void dispose() {
    sintomaController.dispose();
    observacaoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! > 10) {
          widget.onCancel();
        }
      },
      child: Container(
        height: mediaQuery.size.height,
        decoration: const BoxDecoration(
          color: AppColors.cardBackgroundBranco,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: mediaQuery.viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Adicionar Novo Sintoma',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textVerde,
                ),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                ctrl: sintomaController,
                label: 'Sintoma',
                validador: (value) =>
                (value == null || value.isEmpty) ? 'O campo Sintoma é obrigatório' : null,
                textInputType: TextInputType.name,
              ),
              const SizedBox(height: 12),
              CustomSelectorField<String>(
                selectedValue: intensidadeSelecionada,
                items: ['Leve', 'Média', 'Grave']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) => setState(() => intensidadeSelecionada = value),
                label: 'Intensidade',
                hint: 'Selecione a intensidade',
                icon: Icons.bolt,
                validador: (value) => value == null ? 'A intensidade é obrigatória' : null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                ctrl: observacaoController,
                label: 'Observação',
                textInputType: TextInputType.multiline,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.botoesVerdes,
                  foregroundColor: AppColors.botoesBrancos,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSaving
                    ? null
                    : () async {
                  final usuarioProvider = context.read<UsuarioProvider>();
                  setState(() => _isSaving = true);
                  try {
                    await salvarSintomas(
                      nome: sintomaController.text.trim(),
                      intensidade: intensidadeSelecionada ?? 'Média',
                      observacoes: observacaoController.text.trim(),
                      usuarioProvider: usuarioProvider,
                    );

                    widget.onSave(
                      sintomaController.text.trim(),
                      ['Leve', 'Média', 'Grave']
                          .indexOf(intensidadeSelecionada ?? 'Média'),
                      observacaoController.text.trim(),
                    );
                  } catch (e) {
                    debugPrint('Erro ao salvar sintoma: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Erro ao salvar sintoma')),
                    );
                  } finally {
                    if (mounted) setState(() => _isSaving = false);
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isSaving
                      ? Row(
                    key: const ValueKey('saving'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text('Salvando…', style: TextStyle(color: AppColors.textBranco)),
                    ],
                  )
                      : const Text(
                    'Salvar',
                    key: ValueKey('save'),
                    style: TextStyle(color: AppColors.textBranco),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
