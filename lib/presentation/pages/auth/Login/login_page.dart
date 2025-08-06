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
                            CustomTextField(
                              ctrl: controller.emailController,
                              label: LoginTexts.emailLabel,
                              textInputType: TextInputType.emailAddress,
                              validador: AuthValidator.validateEmail,
                            ),
                            const SizedBox(height: 16),
                            CustomTextField(
                              ctrl: controller.passwordController,
                              label: LoginTexts.passwordLabel,
                              textInputType: TextInputType.visiblePassword,
                              isPassword: true,
                              validador: AuthValidator.validatePassword,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pushNamed(context, Routes.resetPassword),
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
                        ),
                        onPressed: () {
                          if (controller.formKey.currentState!.validate()) {
                            controller.autenticarUsuario(context);
                          }
                        },
                        child: const Text(
                          LoginTexts.loginButton,
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
                        LoginTexts.noAccount,
                        style: TextStyle(color: AppColors.textVerde),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, Routes.register),
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
