import 'package:flutter/material.dart';

import '../pages/auth/Login/login_page.dart';
import '../pages/auth/cadastro/cadastro_page.dart';
import '../pages/auth/verificarEmailPage/verificar_email_page.dart';
import '../pages/basePagina/splash_page.dart';
import '../pages/configuracao/configuracao_page.dart';
import '../pages/home/home_page.dart';
import '../pages/onboarding/onboarding_page.dart';



class Routes {
  static const String onboarding = '/';
  static const String home = '/home';
  static const String login = '/login';
  static const String resetPassword = '/resetPassword';
  static const String register = '/register';
  static const String configuracao = '/configuracao';
  static const String verificarEmail = '/verificarEmail';
  static const String splashPage = '/splashPage';


  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingPage());
      case home:
        return MaterialPageRoute(builder: (_) => const HomePage());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case register:
        return MaterialPageRoute(builder: (_) => const RegisterPage());
      case configuracao:
        return MaterialPageRoute(builder: (_) => const ConfiguracaoPage());
      case verificarEmail:
        return MaterialPageRoute(builder: (_) => const VerificarEmailPage());
      case splashPage:
        return MaterialPageRoute(builder: (_) => const SplashPage());
      default:

        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Rota não encontrada ou Não Implementada: ${settings.name}'),
            ),
          ),
        );
    }
  }
}
