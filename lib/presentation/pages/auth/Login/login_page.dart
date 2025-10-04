import 'package:flutter/material.dart';
import '../../../routes/routes.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../themes/app_colors.dart';
import '../utils/auth_validator.dart';
import 'login_texts.dart';
import 'service/login_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final controller = LoginService();


  bool _isLoggingIn = false;



  @override
  void dispose() {
    controller.dispose();
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
            expandedHeight: 300,
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
          SliverFillRemaining(
            hasScrollBody: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.cardBackgroundBranco,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Form(
                      key: controller.formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            LoginTexts.loginTitle,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textVerde,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ===== Campo de e-mail (apenas pré-preenchido com o último usado) =====
                          CustomTextField(
                            ctrl: controller.emailController,
                            label: LoginTexts.emailLabel,
                            textInputType: TextInputType.emailAddress,
                            validador: AuthValidator.validateEmail,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.email,
                              AutofillHints.username, // alguns gerenciadores preferem "username"
                            ],
                          ),

                          const SizedBox(height: 16),
                          CustomTextField(
                            ctrl: controller.passwordController,
                            label: LoginTexts.passwordLabel,
                            textInputType: TextInputType.visiblePassword,
                            isPassword: true,
                            validador: AuthValidator.validatePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [
                              AutofillHints.password,
                            ],

                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    controller.redefinirSenhaComEmailDoCampo(context),
                                child: const Text(
                                  LoginTexts.forgotPassword,
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
                          disabledBackgroundColor:
                          AppColors.botoesVerdes.withOpacity(0.6),
                          disabledForegroundColor:
                          AppColors.textBranco.withOpacity(0.9),
                        ),
                        onPressed: _isLoggingIn
                            ? null
                            : () async {
                          if (controller.formKey.currentState!.validate()) {
                            setState(() => _isLoggingIn = true);

                            await controller.autenticarUsuario(context);

                            if (mounted) setState(() => _isLoggingIn = false);
                          }
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _isLoggingIn
                              ? Row(
                            key: const ValueKey('logging'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Entrando…',
                                style: TextStyle(color: AppColors.textBranco),
                              ),
                            ],
                          )
                              : const Text(
                            LoginTexts.loginButton,
                            key: ValueKey('login'),
                            style: TextStyle(color: AppColors.textBranco),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        LoginTexts.noAccount,
                        style: TextStyle(color: AppColors.textVerde),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, Routes.register),
                        child: const Text(
                          LoginTexts.createAccount,
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
        ],
      ),
    );
  }
}
