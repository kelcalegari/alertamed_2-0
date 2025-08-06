import 'package:flutter/material.dart';

import '../../../core/services/notification_service.dart';
import '../../routes/routes.dart';
import '../../themes/app_colors.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,color: AppColors.textVerde),
                ),
                const SizedBox(height: 16),
                const Text(
                  '• Lembretes inteligentes\n'
                      '• Monitoramento de sintomas\n'
                      '• Controle de estoque de medicamentos\n'
                      '• Análise de reações adversas',
                  style: TextStyle(fontSize: 16,color: AppColors.textVerde),
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
                      onPressed: () async {
                        Navigator.pushNamed(context, Routes.login);
                      },
                      child: const Text(
                        'Próximo',
                        style: TextStyle(color: AppColors.textBranco, fontSize: 16),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}