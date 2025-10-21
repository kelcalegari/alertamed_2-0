import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../../../core/services/credential_store.dart';
import '../../../providers/user_data_provider.dart';
import '../../routes/routes.dart';
import '../../themes/app_colors.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _done = false; // evita navegação duplicada

  @override
  void initState() {
    super.initState();
    // dá 1 frame pro logo aparecer e inicia o fluxo
    WidgetsBinding.instance.addPostFrameCallback((_) => _initFlow());
  }

  Future<void> _initFlow() async {
    if (_done) return;
    await Future.delayed(const Duration(milliseconds: 150));

    final auth = FirebaseAuth.instance;
    User? user = auth.currentUser;

    try {
      // 1) Já tem sessão?
      if (user != null) {
        try {
          await user.reload();
          user = auth.currentUser;
        } catch (_) {}
        await _routeFor(user);
        return;
      }

      // 2) Tenta login silencioso
      final creds = await CredentialStore().read();
      final email = creds.email?.trim();
      final pass  = creds.password;
      final hasCreds =
      (email != null && email.isNotEmpty && pass != null && pass.isNotEmpty);

      if (hasCreds) {
        try {
          await auth
              .signInWithEmailAndPassword(email: email!, password: pass!)
              .timeout(const Duration(seconds: 4));

          // garante estado mais recente antes de decidir
          try {
            await auth.currentUser?.reload();
          } catch (_) {}
          user = auth.currentUser;

          await _routeFor(user);
          return;
        } catch (_) {
          // credenciais inválidas: limpa e segue para onboarding
          await CredentialStore().clear();
        }
      }

      // 3) Sem user → onboarding
      _goOnce(Routes.onboarding);
    } catch (_) {
      _goOnce(Routes.onboarding);
    }
  }

  Future<void> _routeFor(User? user) async {
    if (!mounted) return;

    if (user == null) {
      _goOnce(Routes.onboarding);
      return;
    }

    if (!user.emailVerified) {
      _goOnce(Routes.verificarEmail); // <<
      return;
    }

    // prepara contextos antes da Home
    try {
      await context.read<UsuarioProvider>().onLogin();
    } catch (_) {}

    if (!mounted) return;
    _goOnce(Routes.home);
  }

  void _goOnce(String routeName) {
    if (!mounted || _done) return;
    _done = true;
    // Zera a pilha para não voltar à Splash
    Navigator.of(context).pushNamedAndRemoveUntil(routeName, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return const _SplashLogo();
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Image.asset(
          'assets/logo_alertamed.png',
          width: 180,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
