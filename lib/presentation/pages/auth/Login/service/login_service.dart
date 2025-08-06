import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../routes/routes.dart';
import '../../../../shared/modals/custom_popup.dart';
import '../login_texts.dart';

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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      Navigator.pushReplacementNamed(context, Routes.home);
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


      CustomPopup.show(
        context: context,
        title: LoginTexts.dialogTitle,
        message: errorMsg,
      );
    }
  }
}
