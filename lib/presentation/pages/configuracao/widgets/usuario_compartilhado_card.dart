import 'package:flutter/material.dart';

import '../../../themes/app_colors.dart';

class UsuarioCompartilhadoCard extends StatelessWidget {
  final String nome;
  final String tipo;
  final VoidCallback onRemove;

  const UsuarioCompartilhadoCard({
    super.key,
    required this.nome,
    required this.tipo,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundVerde,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(Icons.local_hospital, color: AppColors.iconColor, size: 32),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tipo,
                  style: const TextStyle(
                    color: AppColors.textBranco,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  nome,
                  style: const TextStyle(
                    color: AppColors.textBranco,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, color: AppColors.textBranco),
          ),
        ],
      ),
    );
  }
}

class ListaUsuariosCompartilhados extends StatefulWidget {
  const ListaUsuariosCompartilhados({super.key});

  @override
  State<ListaUsuariosCompartilhados> createState() =>
      _ListaUsuariosCompartilhadosState();
}

class _ListaUsuariosCompartilhadosState extends State<ListaUsuariosCompartilhados> {
  // Dados fixos simulando fetch do Provider
  List<Map<String, String>> usuarios = [
    {"nome": "Chayanne Calegari", "tipo": "Médica"},
    {"nome": "João da Silva", "tipo": "Cuidador"},
  ];

  void _removerUsuario(String nome) {
    setState(() {
      usuarios.removeWhere((u) => u["nome"] == nome);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$nome removido.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: usuarios.isEmpty
          ? const Text(
        "Nenhum usuário cadastrado no momento.",
        style: TextStyle(color: AppColors.textVerde),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Usuários Cadastrados",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textVerde,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Usuários habilitados para acompanhar seus tratamentos",
            style: TextStyle(fontSize: 14, color: AppColors.textVerde),
          ),
          const SizedBox(height: 8),
          ...usuarios.map(
                (usuario) => UsuarioCompartilhadoCard(
              nome: usuario["nome"]!,
              tipo: usuario["tipo"]!,
              onRemove: () => _removerUsuario(usuario["nome"]!),
            ),
          ),
        ],
      ),
    );
  }
}
