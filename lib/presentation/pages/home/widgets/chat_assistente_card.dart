import 'package:flutter/material.dart';

class ChatAssistenteCard extends StatelessWidget {
  final List<String> mensagens;
  final TextEditingController controller;
  final VoidCallback onEnviar;

  const ChatAssistenteCard({
    super.key,
    required this.mensagens,
    required this.controller,
    required this.onEnviar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Assistente AlertaMED',
            style: TextStyle(
              color: Color(0xFF002600),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Mensagens
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: mensagens.length,
              itemBuilder: (context, index) {
                final msg = mensagens[mensagens.length - 1 - index];
                final isAssistente = index % 2 == 0; // alternância básica

                return Align(
                  alignment: isAssistente ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: isAssistente ? Colors.grey.shade300 : const Color(0xFF002600),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg,
                      style: TextStyle(
                        color: isAssistente ? Colors.black87 : Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Campo de entrada
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Digite aquiii',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEnviar,
                  icon: const Icon(Icons.send, color: Color(0xFF002600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
