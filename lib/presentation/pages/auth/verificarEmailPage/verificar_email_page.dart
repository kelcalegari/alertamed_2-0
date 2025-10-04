import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../routes/routes.dart';
import '../../../themes/app_colors.dart';

class VerificarEmailPage extends StatefulWidget {
  const VerificarEmailPage({super.key});

  @override
  State<VerificarEmailPage> createState() => _VerificarEmailPageState();
}

class _VerificarEmailPageState extends State<VerificarEmailPage> {
  bool _loading = false;
  String? _info;

  Future<void> _reenviar() async {
    setState(() {
      _loading = true;
      _info = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado.');
      await user.sendEmailVerification();
      setState(() {
        _info = 'E-mail reenviado. Verifique sua caixa de entrada.';
      });
    } catch (e) {
      setState(() {
        _info = 'Falha ao reenviar: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _jaVerifiquei() async {
    setState(() {
      _loading = true;
      _info = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado.');

      await user.reload();
      // força refresh do token para refletir email_verified nas regras de segurança
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null && refreshed.emailVerified) {
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(Routes.home, (_) => false);
        }
      } else {
        setState(() {
          _info =
          'Ainda não detectei a verificação. Tente novamente em alguns segundos.';
        });
      }
    } catch (e) {
      setState(() {
        _info = 'Erro ao verificar status: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
                  // Conteúdo principal
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Confirme seu e-mail',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textVerde,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Enviamos um link de verificação para o seu e-mail. '
                              'Clique no link e depois volte aqui para liberar o acesso.',
                          textAlign: TextAlign.left,
                          style: TextStyle(color: AppColors.textVerde),
                        ),
                        if (_info != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: AppColors.background.withOpacity(0.6),
                            ),
                            child: Text(
                              _info!,
                              textAlign: TextAlign.left,
                              style: const TextStyle(
                                color: AppColors.textVerde,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Botão primário centralizado (75% da largura)
                  Center(
                    child: SizedBox(
                      width: size.width * 0.75,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _jaVerifiquei,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.botoesVerdes,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.textBranco),
                          ),
                        )
                            : const Text(
                          'Já verifiquei',
                          style: TextStyle(color: AppColors.textBranco),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Ações secundárias
                  Column(
                    children: [
                      TextButton(
                        onPressed: _loading ? null : _reenviar,
                        child: const Text(
                          'Reenviar e-mail de verificação',
                          style: TextStyle(
                            color: AppColors.textVerde,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                          if (mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                                Routes.login, (_) => false);
                          }
                        },
                        child: const Text(
                          'Sair e voltar ao login',
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
