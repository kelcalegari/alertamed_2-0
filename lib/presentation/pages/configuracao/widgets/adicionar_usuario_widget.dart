import 'package:flutter/material.dart';
import '../../../themes/app_colors.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../auth/cadastro/cadastro_texts.dart';
import '../../auth/utils/auth_validator.dart';

class AdicionarUsuarioWidget extends StatefulWidget {
  const AdicionarUsuarioWidget({super.key});

  @override
  State<AdicionarUsuarioWidget> createState() => _AdicionarUsuarioWidgetState();
}

class _AdicionarUsuarioWidgetState extends State<AdicionarUsuarioWidget> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Adicionar Usuário para Compartilhar Tratamento",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textVerde,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Convide outro usuário do AlertaMED para acompanhar seu tratamento e ajudar no controle dos medicamentos.",
              style: TextStyle(fontSize: 14, color: AppColors.textVerde),
            ),
            const SizedBox(height: 24),
            CustomTextField(
              ctrl: _emailCtrl,
              label: RegisterTexts.emailLabel,
              textInputType: TextInputType.emailAddress,
              validador: AuthValidator.validateEmail,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.botoesVerdes,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(40),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final email = _emailCtrl.text.trim();
                    // Lógica para adicionar compartilhamento
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Convite enviado para $email")),
                    );
                  }
                },
                child: const Text(
                  "Salvar",
                  style: TextStyle(
                    color: AppColors.textBranco,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
