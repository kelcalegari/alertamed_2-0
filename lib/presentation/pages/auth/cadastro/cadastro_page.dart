import 'package:smartmed/presentation/pages/auth/cadastro/service/register_service.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/custom_seletor_field.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../themes/app_colors.dart';
import '../utils/auth_validator.dart';
import 'cadastro_texts.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final registerService = RegisterService();
  String? _selectedGender;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _birthCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            expandedHeight: 200, // altura máxima da área expansível
            pinned: false,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              background: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  Image.asset('assets/logo_alertamed.png', width: 200),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.cardBackgroundBranco,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      RegisterTexts.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textVerde,
                      ),
                    ),
                    const SizedBox(height: 20),
                    CustomTextField(
                      ctrl: _nameCtrl,
                      label: RegisterTexts.nameLabel,
                      validador:
                          (value) =>
                              value == null || value.isEmpty
                                  ? RegisterTexts.nameRequired
                                  : null,
                      textInputType: TextInputType.name,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      ctrl: _birthCtrl,
                      label: RegisterTexts.birthLabel,
                      textInputType: TextInputType.datetime,
                      validador:
                          (value) =>
                              value == null || value.isEmpty
                                  ? RegisterTexts.birthRequired
                                  : null,
                    ),
                    const SizedBox(height: 16),
                    CustomSelectorField<String>(
                      selectedValue: _selectedGender,
                      items:
                          RegisterTexts.vectorGender
                              .map(
                                (g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(g), // sem style aqui
                                ),
                              )
                              .toList(),
                      onChanged:
                          (value) => setState(() => _selectedGender = value),
                      label: RegisterTexts.genderLabel,
                      hint: RegisterTexts.genderHint,
                      icon: Icons.person,
                      validador:
                          (value) =>
                              value == null
                                  ? RegisterTexts.genderRequired
                                  : null,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      ctrl: _emailCtrl,
                      label: RegisterTexts.emailLabel,
                      textInputType: TextInputType.emailAddress,
                      validador: AuthValidator.validateEmail,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      ctrl: _passwordCtrl,
                      label: RegisterTexts.passwordLabel,
                      textInputType: TextInputType.visiblePassword,
                      isPassword: true,
                      validador: AuthValidator.validatePassword,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      ctrl: _confirmPasswordCtrl,
                      label: RegisterTexts.passwordConfirmLabel,
                      textInputType: TextInputType.visiblePassword,
                      isPassword: true,
                      validador: AuthValidator.validatePassword,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      RegisterTexts.termsText,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textVerde,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        RegisterTexts.termsButton,
                        style: TextStyle(
                          color: AppColors.textVerde,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: SizedBox(
                        width: size.width * 0.75,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.botoesVerdes,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: criarConta,
                          child: const Text(
                            RegisterTexts.createAccount,
                            style: TextStyle(color: AppColors.textBranco),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          RegisterTexts.alreadyHaveAccount,
                          style: TextStyle(color: AppColors.textVerde),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text(
                            RegisterTexts.loginHere,
                            style: TextStyle(
                              color: AppColors.textVerde,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> criarConta() async {
    if (!_formKey.currentState!.validate()) return;

    await registerService.criarConta(
      context: context,
      nome: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      senha: _passwordCtrl.text,
      sexo: _selectedGender!,
      dataNascimentoTexto: _birthCtrl.text.trim(),
    );

  }
}
