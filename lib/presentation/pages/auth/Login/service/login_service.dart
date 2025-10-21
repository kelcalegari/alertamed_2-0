import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../../../../core/services/credential_store.dart';
import '../../../../../providers/user_data_provider.dart';
import '../../../../routes/routes.dart';
import '../../../../shared/modals/custom_popup.dart';
import '../../../home/service/alterar_lembrete.dart';
import '../../utils/auth_validator.dart';
import '../login_texts.dart';
import 'package:flutter/services.dart';

class LoginService {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  void dispose() {
    emailController.dispose();
    passwordController.dispose();
  }

  Future<void> autenticarUsuario(BuildContext context) async {
    if (!formKey.currentState!.validate()) return;

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'user-not-found', message: 'Usuário não encontrado.');
      }

      await user.reload();
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      final refreshed = FirebaseAuth.instance.currentUser!;
      final verified = refreshed.emailVerified;

      if (!verified) {
        try {
          await refreshed.sendEmailVerification();
        } catch (_) {}

        if (context.mounted) {
          CustomPopup.show(
            context: context,
            title: LoginTexts.dialogTitle,
            message:
            'Enviamos um link de verificação para o seu e-mail. '
                'Clique no link e depois toque em "Já verifiquei" na próxima tela.',
          );
          Navigator.pushReplacementNamed(context, Routes.verificarEmail);
        }
        return;
      }

      if (context.mounted) {

        await context.read<UsuarioProvider>().onLogin();
        await LembreteService().criarNotificacoesPosLogin(
          context: context,
          idUsuario: FirebaseAuth.instance.currentUser!.uid,
        );
        await CredentialStore().save(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
        try {
           TextInput.finishAutofillContext(shouldSave: true);
        } catch (_) {
          // silencioso; nem todo dispositivo precisa/tem isso ativo
        }
        Navigator.pushReplacementNamed(context, Routes.home);
      }
    } on FirebaseAuthException catch (e) {
      String errorMsg;
      switch (e.code) {
        case 'invalid-email':
          errorMsg = LoginTexts.errorInvalidEmail;
          break;
        case 'user-disabled':
          errorMsg = LoginTexts.errorUserDisabled;
          break;
        case 'user-not-found':
          errorMsg = LoginTexts.errorUserNotFound;
          break;
        case 'wrong-password':
          errorMsg = LoginTexts.errorWrongPassword;
          break;
        case 'invalid-credential':
          errorMsg = LoginTexts.errorInvalidCredential;
          break;
        case 'too-many-requests':
          errorMsg = LoginTexts.errorTooManyRequests;
          break;
        case 'operation-not-allowed':
          errorMsg = LoginTexts.errorOperationNotAllowed;
          break;
        default:
          errorMsg = '${LoginTexts.errorDefault} (${e.code})';
      }

      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: LoginTexts.dialogTitle,
          message: errorMsg,
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: LoginTexts.dialogTitle,
          message: 'Falha na autenticação: $e',
        );
      }
    }
  }

  /// 🔐 Redefinição de senha usando o e-mail digitado no campo da tela de login
  Future<void> redefinirSenhaComEmailDoCampo(BuildContext context) async {
    final email = emailController.text.trim();

    // valida formato de e-mail com o mesmo validador da UI
    final emailError = AuthValidator.validateEmail(email);
    if (emailError != null) {
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: LoginTexts.dialogTitle,
          message: 'Informe um e-mail válido para redefinir a senha.',
        );
      }
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: "E-mail de redefinição enviado",
          message:
          'Enviamos um e-mail com o link para redefinir sua senha. '
              'Verifique sua caixa de entrada (e o Spam).',
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'invalid-email':
          msg = LoginTexts.errorInvalidEmail;
          break;
        case 'user-not-found':
          msg = 'Não encontramos conta com esse e-mail.';
          break;
        case 'too-many-requests':
          msg = LoginTexts.errorTooManyRequests;
          break;
        default:
          msg = 'Não foi possível enviar o e-mail de redefinição. (${e.code})';
      }
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: LoginTexts.dialogTitle,
          message: msg,
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: LoginTexts.dialogTitle,
          message: 'Ocorreu um erro: $e',
        );
      }
    }
  }

  /// Reenvia o e-mail de verificação manualmente (útil na tela de verificação).
  Future<void> reenviarVerificacao(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado.');
      await user.sendEmailVerification();
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: LoginTexts.dialogTitle,
          message: 'E-mail de verificação reenviado.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: LoginTexts.dialogTitle,
          message: 'Não foi possível reenviar: $e',
        );
      }
    }
  }
}
