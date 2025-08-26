import 'package:flutter/material.dart';
import '../../../themes/app_colors.dart';

class CardAssistenteIA extends StatefulWidget {
  final VoidCallback onClose;

  const CardAssistenteIA({super.key, required this.onClose});

  @override
  State<CardAssistenteIA> createState() => _CardAssistenteIAState();
}

class _CardAssistenteIAState extends State<CardAssistenteIA> {
  final TextEditingController controller = TextEditingController();

  final List<Map<String, String>> mensagens = [
    {
      'role': 'assistant',
      'content': 'Olá! Sou seu assistente.\nPosso ajudar com dúvidas sobre medicamentos, sintomas ou interações.'
    }
  ];

  void enviarMensagem() {
    final texto = controller.text.trim();
    if (texto.isEmpty) return;

    setState(() {
      mensagens.add({'role': 'user', 'content': texto});
      mensagens.add({
        'role': 'assistant',
        'content': 'Resposta simulada para: "$texto"' // Substituir pela resposta da IA futuramente
      });
    });

    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! > 10) {
          widget.onClose();
        }
      },
      child: Container(
        height: mediaQuery.size.height,
        padding: EdgeInsets.only(
          bottom: mediaQuery.viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 16,
        ),
        decoration: const BoxDecoration(
          color: AppColors.cardBackgroundBranco,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Assistente AlertaMED',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textVerde,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Lista de mensagens
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: mensagens.length,
                itemBuilder: (context, index) {
                  final reversedIndex = mensagens.length - 1 - index;
                  final msg = mensagens[reversedIndex];
                  final isAssistente = msg['role'] == 'assistant';

                  return Align(
                    alignment:
                    isAssistente ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: isAssistente
                            ? Colors.grey.shade300
                            : AppColors.botoesVerdes,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        msg['content'] ?? '',
                        style: TextStyle(
                          fontSize: 15,
                          color: isAssistente ? Colors.black87 : Colors.white,
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
                        hintText: 'Digite aqui...',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => enviarMensagem(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppColors.textVerde),
                    onPressed: enviarMensagem,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
