import 'package:flutter/material.dart';

class LoginHeader extends StatelessWidget {
  const LoginHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Image.asset('assets/logo_alertamed.png', width: 200),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
