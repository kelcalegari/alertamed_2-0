import 'package:flutter/material.dart';
import '../../../themes/app_colors.dart';
import '../service/chatgpt_service.dart';

class CardAssistenteIA extends StatefulWidget {
  final VoidCallback onClose;

  const CardAssistenteIA({super.key, required this.onClose});

  @override
  State<CardAssistenteIA> createState() => _CardAssistenteIAState();
}

class _CardAssistenteIAState extends State<CardAssistenteIA> {
  final TextEditingController controller = TextEditingController();
  final List<String> mensagens = [
    'Olá! Sou seu assistente.\nPosso ajudar com dúvidas sobre medicamentos, sintomas ou interações.'
  ];

  void enviarMensagem() async {
    final texto = controller.text.trim();
    if (texto.isEmpty) return;

    setState(() {
      mensagens.add(texto); // Mensagem do usuário
    });

    controller.clear();

    try {
      final resposta = await ChatGPTService.obterResposta(texto);
      setState(() {
        mensagens.add(resposta);
      });
    } catch (e) {
      setState(() {
        mensagens.add('Erro ao obter resposta da IA.');
      });
    }
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
                  final msg = mensagens[mensagens.length - 1 - index];
                  final isAssistente = index % 2 == 0;

                  return Align(
                    alignment: isAssistente ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: isAssistente ? Colors.grey.shade300 : AppColors.botoesVerdes,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        msg,
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
                        hintText: 'Digite aquiii',
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
