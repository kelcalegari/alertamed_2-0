// services/chatgpt_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatGPTService {
  static const _apiKey = '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';
  static const _url = 'https://api.openai.com/v1/chat/completions';

  static Future<String> obterResposta(String mensagemUsuario) async {
    final response = await http.post(
      Uri.parse(_url),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "model": "gpt-4o",
        "messages": [
          {"role": "system", "content": "Você é um assistente útil e simpático especializado em medicamentos, tratamentos e reações adversas."},
          {"role": "user", "content": mensagemUsuario}
        ],
        "temperature": 0.3
      }),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['choices'][0]['message']['content'].toString().trim();
    } else {
      throw Exception('Erro ao acessar a OpenAI: ${response.body}');
    }
  }
}
