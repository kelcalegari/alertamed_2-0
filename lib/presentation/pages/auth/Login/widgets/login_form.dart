import 'package:flutter/material.dart';
import '../../../../routes/routes.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../themes/app_colors.dart';
import '../../utils/auth_validator.dart';

import '../service/login_service.dart';
import '../login_texts.dart';

class LoginForm extends StatelessWidget {
  final LoginService loginService;

  const LoginForm({super.key, required this.loginService});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.cardBackgroundBranco,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Form(
        key: loginService.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(LoginTexts.loginTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,color: AppColors.textVerde)),
            const SizedBox(height: 20),
            CustomTextField(
              ctrl: loginService.emailController,
              label: LoginTexts.emailLabel,
              textInputType: TextInputType.emailAddress,
              validador: AuthValidator.validateEmail,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              ctrl: loginService.passwordController,
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
                  onPressed: () => Navigator.pushNamed(context, Routes.resetPassword),
                  child: const Text(LoginTexts.forgotPassword, style: TextStyle(color: AppColors.textVerde, fontWeight: FontWeight.bold)),
                ),
              ],
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
                  onPressed: () => loginService.autenticarUsuario(context),
                  child: const Text(LoginTexts.loginButton, style: TextStyle(color: AppColors.textBranco)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(LoginTexts.noAccount,style: TextStyle(color: AppColors.textVerde),),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, Routes.register),
                  child: const Text(LoginTexts.createAccount,style: TextStyle(color: AppColors.textVerde, fontWeight: FontWeight.bold),),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
