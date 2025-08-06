


import 'auth_validator_texts.dart';

class AuthValidator {
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return AuthValidatorTexts.emailRequiredMessage;
    } else if (!RegExp(r'^[\w-]+(\.[\w-]+)*@([\w-]+\.)+[a-zA-Z]{2,7}$').hasMatch(value)) {
      return AuthValidatorTexts.invalidEmailMessage;
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return AuthValidatorTexts.passwordRequiredMessage;
    } else if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$%^&*]).{8,}$').hasMatch(value)) {
      return AuthValidatorTexts.incorrectPasswordMessage;
    }
    return null;
  }
}
