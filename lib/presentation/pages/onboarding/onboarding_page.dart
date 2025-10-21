import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/credential_store.dart';
import '../../routes/routes.dart';
import '../../themes/app_colors.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _checking = true; // enquanto true, mostra só o “splash”
  bool _trying = false;
  bool _triedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _trySilentLogin());
  }

  Future<void> _trySilentLogin() async {
    if (_triedOnce) return;
    _triedOnce = true;

    // (opcional) dá um “respiro” pro logo aparecer
    await Future.delayed(const Duration(milliseconds: 120));

    final creds = await CredentialStore().read();
    final email = creds.email?.trim();
    final pass  = creds.password;

    // Sem credenciais → encerra checagem e mostra Onboarding
    if (email == null || email.isEmpty || pass == null || pass.isEmpty) {
      if (mounted) setState(() => _checking = false);
      return;
    }

    setState(() { _trying = true; _checking = true; });
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: pass)
          .timeout(const Duration(seconds: 4));

      if (!mounted) return;

      // Garante estado recente do usuário
      try { await FirebaseAuth.instance.currentUser?.reload(); } catch (_) {}

      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.emailVerified) {
        Navigator.pushReplacementNamed(context, Routes.verificarEmail);
      } else {
        Navigator.pushReplacementNamed(context, Routes.home);
      }
    } catch (_) {
      // Falhou → limpa credenciais e mostra Onboarding
      await CredentialStore().clear();
      if (!mounted) return;
      setState(() { _trying = false; _checking = false; });
      // (Opcional) Snackbar silenciosa
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('Login automático indisponível. Faça login manual.')),
      // );
    }
  }

  @override
  Widget build(BuildContext context) {
    // === FASE SPLASH: só o logo enquanto checa/loga ===
    if (_checking) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Image.asset(
            'assets/logo_alertamed.png',
            height: 200,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    // === FASE ONBOARDING: conteúdo normal ===
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 80),
              Column(
                children: [
                  Image.asset(
                    'assets/logo_alertamed.png',
                    height: 200,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gerencie seus medicamentos de forma simples e segura!',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textVerde),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '• Lembretes inteligentes\n'
                          '• Monitoramento de sintomas\n'
                          '• Controle de estoque de medicamentos\n'
                          '• Análise de reações adversas',
                      style: TextStyle(fontSize: 16, color: AppColors.textVerde),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.75,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.botoesVerdes,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _trying
                              ? null
                              : () => Navigator.pushNamed(context, Routes.login),
                          child: Text(
                            _trying ? 'Verificando...' : 'Próximo',
                            style: const TextStyle(color: AppColors.textBranco, fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // (Opcional) overlay se quiser bloquear ações durante alguma verificação posterior
          if (_trying)
            Container(
              color: Colors.black.withOpacity(0.05),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
        ],
      ),
    );
  }
}
