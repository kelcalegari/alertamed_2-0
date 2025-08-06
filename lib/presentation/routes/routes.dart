import 'package:flutter/material.dart';

import '../pages/auth/Login/login_page.dart';
import '../pages/auth/cadastro/cadastro_page.dart';
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
      case resetPassword:
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
