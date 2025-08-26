import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class ChatGPTService {
  static const _url = 'https://api.openai.com/v1/chat/completions';

  static Future<String> obterRespostaComContexto({
    required String pergunta,
    required Map<String, dynamic> dadosUsuario,
    required Map<String, dynamic> tratamentosMap,
    required List<Map<String, dynamic>> lembretes,
    required List<Map<String, dynamic>> sintomas,
    required List<Map<String, String>> ultimasInteracoes,
    required Map<String, dynamic> infoMedica,
  }) async {
    final DateFormat formatadorData = DateFormat('dd/MM/yyyy HH:mm');
    await dotenv.load(fileName: ".env");
    final openAiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    String _fmt(dynamic v) {
      if (v == null) return '—';
      final s = v.toString().trim();
      return s.isEmpty ? '—' : s;
    }
    // Filtro de sintomas dos últimos 5 dias
    final agora = DateTime.now();
    final sintomasRecentes = sintomas.where((s) {
      final data = (s['dataHora'] as Timestamp).toDate();
      return data.isAfter(agora.subtract(Duration(days: 5)));
    }).toList();

    // Construção de resumo dos tratamentos ativos
    final tratamentosAtivos = tratamentosMap.values.where((t) => t['status'] == 'ativo');
    final resumoTratamentos = tratamentosAtivos.map((t) {
      return "- ${t['nomeMedicamento']} (${t['dosagem']}, ${t['frequencia']}) de ${DateFormat('dd/MM/yyyy').format((t['dataInicio'] as Timestamp).toDate())} até ${DateFormat('dd/MM/yyyy').format((t['dataTermino'] as Timestamp).toDate())}";
    }).join('\n');

    // Histórico de ingestão de medicamentos
    final historicoLembretes = lembretes.where((l) {
      final ts = (l['dataHoraTomado'] ?? l['dataHoraAgendado']);
      if (ts is! Timestamp) return false;
      return ts.toDate().isAfter(agora.subtract(const Duration(days: 5)));
    }).map((l) {
      final ts = (l['dataHoraTomado'] ?? l['dataHoraAgendado']) as Timestamp;
      final idTratamento = (l['idTratamento'] ?? '').toString();
      final t = (tratamentosMap[idTratamento] ?? {}) as Map<String, dynamic>;
      final nome = (t['nomeMedicamento'] ?? '—').toString();
      final concentracaoMedicamento = (t['concentracaoMedicamento'] ?? '—').toString();

      final tomado = l['tomado'] == true ? 'Tomado' : 'Não Tomado';
      return '- $nome $concentracaoMedicamento • ${formatadorData.format(ts.toDate())} • $tomado';
    }).join('\n');

    // Sintomas recentes formatados
    final resumoSintomas = sintomasRecentes.map((s) {
      final data = (s['dataHora'] as Timestamp).toDate();
      return "- ${s['nome']} (${s['intensidade']}) em ${formatadorData.format(data)}";
    }).join('\n');

    final gravidez = _fmt(infoMedica['gravidez']);            // "Sim" | "Não" | "Não se aplica" | —
    final alergias = _fmt(infoMedica['alergias']);            // string (ex: "Dipirona, Amendoim")
    final deficiencias = _fmt(infoMedica['deficiencias']);    // string livre
    final comorbidades = _fmt(infoMedica['comorbidades']);    // string livre

    final hoje = DateTime.now(); // horário local do dispositivo
    final inicio = hoje.subtract(const Duration(days: 4)); // hoje + 4 dias anteriores
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');

    final periodoTexto = 'Período considerado: ${df.format(inicio)} a ${df.format(hoje)} (últimos 5 dias).'
        '\nData de hoje: ${df.format(hoje)}.';

    final instrucoesSistema = '''
    Você é o Assistente AlertaMED — assistente farmacêutico virtual.
    
    ## Escopo
    - Horários e lembretes de medicamentos.
    - Adesão: adiantar, atrasar, pular.
    - Sintomas/efeitos adversos e orientações de segurança (sem diagnóstico).
    - Recomendações de medicamentos quando apropriado.
    
    ## Restrições
    - Não diagnostique, não prescreva, não ajuste doses individualizadas, não interprete exames, não altere tratamento médico.
    - Não trate temas fora da saúde do medicamento.
    - Nunca usenas respostas os termos “OTC”, “MIP/MIPs”, “sem receita”, “de venda livre”, frases metalinguísticas (“com base no contexto/histórico…”) ou vagas (“alguns medicamentos podem ajudar…”).
    - Não prometa eficácia; não sugira antibióticos, hormônios, psicotrópicos ou fármacos sujeitos a prescrição.
    
    ## Como responder
    - Use apenas os dados recebidos; **não faça perguntas** e **não mencione** que usou dados do contexto.
    - Antes de sugerir, verifique interações/reação adversa com tratamentos ativos; havendo risco, **não** recomende e oriente avaliação médica.
    - Sugira **princípio ativo** + **classe**; **marcas só se o usuário pedir**, em 2–3 exemplos (ordem alfabética) e sempre junto do princípio ativo.
    - **Não** personalize dose; oriente seguir a **bula** e limites usuais; em dúvida, **não** recomende.
    
    ## Sinais de alerta (encaminhe)
    Dor intensa súbita, febre alta persistente, falta de ar, dor torácica, sangramento, confusão, rigidez de nuca, desidratação importante, reação alérgica importante, piora rápida ou sintomas >72h sem melhora.
    - Se houver suspeita de **interação**/**reação adversa**, **avise claramente** e **não** incentive automedicação até avaliação médica.

    ## Estilo
    - PT-BR, **Markdown (GFM)**.
    - Direto, objetivo, **sem repetir informações**.
    - Inclua: **“Isto não substitui avaliação médica.”** ao orientar segurança ou sugerir medicamentos.

    '''.trim();
    final contextoClinico  = '''
  
    $periodoTexto
    
    • Condições Pessoais:
      - Gravidez: $gravidez
      - Alergias: $alergias
      - Deficiências: $deficiencias
      - Comorbidades: $comorbidades
        
    Abaixo estão as informações clínicas do usuário de 5 dias:
    
    • Tratamentos:
    $resumoTratamentos
    
    • Sintomas Recentes:
    $resumoSintomas
    
    • Histórico de Ingestão de Medicamentos:
    $historicoLembretes
    ''';

    // Construção da lista de mensagens com histórico
    final List<Map<String, String>> mensagens = [
      {"role": "system", "content": instrucoesSistema},
      {"role": "user", "content": contextoClinico},
      ...ultimasInteracoes,
      {"role": "user", "content": pergunta}
    ];

    // Requisição
    final response = await http.post(
      Uri.parse(_url),
      headers: {
        'Authorization': 'Bearer $openAiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "model": "gpt-4o",
        "messages": mensagens,
        "temperature": 0.4,
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
