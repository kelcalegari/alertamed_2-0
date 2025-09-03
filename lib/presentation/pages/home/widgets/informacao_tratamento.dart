import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';

class InformacaoTratamento extends StatelessWidget {
  final VoidCallback onCancel;
  final Map<String, dynamic> tratamento;

  const InformacaoTratamento({
    super.key,
    required this.onCancel,
    required this.tratamento,
  });

  // ===================== Helpers =====================

  String _cap(String s) =>
      (s.isEmpty) ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  List<Map<String, dynamic>> _lembretesDo(Map<String, dynamic> t) {
    final raw = t['lembretes'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  // Normaliza e valida HH:mm
  String? _normalizeHora(String raw) {
    final v = (raw).trim();
    final re = RegExp(r'^(\d{1,2}):(\d{2})$');
    final m = re.firstMatch(v);
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    if (h == null || min == null) return null;
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    final h2 = h.toString().padLeft(2, '0');
    final m2 = min.toString().padLeft(2, '0');
    return '$h2:$m2';
  }

  /// Caso "Horários Fixos": ["08:30", "20:30"]
  List<String> _formatHorariosFixos(Map<String, dynamic> t) {
    final ls = _lembretesDo(t)
        .map((e) => (e['valor'] ?? '').toString())
        .map(_normalizeHora)
        .whereType<String>()
        .toList();

    ls.sort((a, b) => a.compareTo(b));
    return ls;
  }

  /// Caso "Junto com Refeições": ["Café", "Almoço", "Jantar", ...]
  List<String> _formatRefeicoes(Map<String, dynamic> t) {
    final refeicoes = _lembretesDo(t)
        .map((e) => (e['momento'] ?? '').toString().trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    // ordem canônica
    const ordem = [
      'cafe',
      'lanche_manha',
      'almoco',
      'lanche_tarde',
      'jantar',
      'ceia'
    ];

    refeicoes.sort((a, b) {
      int ia = ordem.indexOf(a);
      int ib = ordem.indexOf(b);
      ia = ia < 0 ? 1 << 20 : ia;
      ib = ib < 0 ? 1 << 20 : ib;
      if (ia != ib) return ia.compareTo(ib);
      return a.compareTo(b);
    });

    return refeicoes.map((k) => _cap(k.replaceAll('_', ' '))).toList();
  }

  /// Caso "Intervalos Fixos": "a cada Xh"
  String? _formatIntervalo(Map<String, dynamic> t) {
    final lembretes = _lembretesDo(t);
    if (lembretes.isEmpty) return null;
    // costuma vir em lembretes[0].valor = "8" (horas)
    final raw = (lembretes.first['valor'] ?? '').toString().trim();
    final num? horas = num.tryParse(raw);
    if (horas == null || horas <= 0) return null;
    // arredonda para apresentação
    if (horas % 1 == 0) {
      return 'a cada ${horas.toInt()}h';
    } else {
      return 'a cada ${horas.toString()}h';
    }
  }

  String _formatData(Timestamp? ts) {
    if (ts == null) return 'Não informado';
    final dt = ts.toDate();
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    final String nomeMedicamento = (tratamento['nomeMedicamento'] ?? '').toString();
    final String concentracaoMedicamento = (tratamento['concentracaoMedicamento'] ?? '').toString();
    final String tipoMedicamento = (tratamento['tipoMedicamento'] ?? '').toString();
    final String dosagem = (tratamento['dosagem'] ?? '').toString();
    final String unidadeMedida = (tratamento['unidadeMedida'] ?? '').toString();
    final String frequencia = (tratamento['frequencia'] ?? '').toString();
    final String tipoFrequencia = (tratamento['tipoFrequencia'] ?? '').toString();

    final usuarioProvider = Provider.of<UsuarioProvider>(context);
    final String idMedicamento = (tratamento['idMedicamento'] ?? '').toString();
    final Map<String, dynamic>? estoque = usuarioProvider.estoqueMap[idMedicamento];

    // Dados por tipo de frequência
    final isRef = tipoFrequencia.toLowerCase().contains('refei');
    final isFixos = tipoFrequencia.toLowerCase().contains('horários fixos') ||
        tipoFrequencia.toLowerCase().contains('horarios fixos');
    final isIntervalo = tipoFrequencia.toLowerCase().contains('intervalos fixos');

    final horariosFixos = isFixos ? _formatHorariosFixos(tratamento) : const <String>[];
    final refeicoes = isRef ? _formatRefeicoes(tratamento) : const <String>[];
    final intervalo = isIntervalo ? _formatIntervalo(tratamento) : null;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! > 10) {
          onCancel();
        }
      },
      child: Container(
        height: mediaQuery.size.height,
        decoration: const BoxDecoration(
          color: AppColors.cardBackgroundBranco,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---------- Card superior (resumo) ----------
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Exibe nome + concentração se houver
                        (concentracaoMedicamento.isNotEmpty)
                            ? '$nomeMedicamento $concentracaoMedicamento'
                            : nomeMedicamento,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textVerde,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        label: 'Tipo',
                        value: tipoMedicamento,
                        color: AppColors.textVerde,
                      ),
                      if (concentracaoMedicamento.isNotEmpty)
                        _InfoRow(
                          label: 'Concentração',
                          value: concentracaoMedicamento,
                          color: AppColors.textVerde,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ---------- Card do tratamento atual ----------
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackgroundVerde,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tratamento Atual',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textBranco,
                          ),
                        ),
                        const SizedBox(height: 12),

                        _InfoRow(
                          label: 'Dosagem',
                          // Se a tua "dosagem" já representa quantidade (ex.: "1"),
                          // a unidade real de tomada costuma ser "unidadeMedida" (ex.: "comp")
                          value: unidadeMedida.isEmpty ? dosagem : '$dosagem $unidadeMedida',
                          color: AppColors.textBranco,
                        ),
                        _InfoRow(
                          label: 'Frequência',
                          value: frequencia.isEmpty ? 'Não informada' : frequencia,
                          color: AppColors.textBranco,
                        ),
                        _InfoRow(
                          label: 'Tipo de frequência',
                          value: tipoFrequencia.isEmpty ? 'Não informada' : tipoFrequencia,
                          color: AppColors.textBranco,
                        ),

                        // ---- Caso específico: Refeições ----
                        if (refeicoes.isNotEmpty)
                          _InfoRow(
                            label: 'Por refeição',
                            value: refeicoes.join('  •  '),
                            color: AppColors.textBranco,
                          ),

                        // ---- Caso específico: Horários Fixos ----
                        if (horariosFixos.isNotEmpty)
                          _InfoRow(
                            label: 'Horários fixos',
                            value: horariosFixos.join(', '),
                            color: AppColors.textBranco,
                          ),

                        // ---- Caso específico: Intervalos Fixos ----
                        if (intervalo != null)
                          _InfoRow(
                            label: 'Intervalo',
                            value: intervalo,
                            color: AppColors.textBranco,
                          ),

                        _InfoRow(
                          label: 'Início',
                          value: _formatData(tratamento['dataInicio'] as Timestamp?),
                          color: AppColors.textBranco,
                        ),
                        _InfoRow(
                          label: 'Término',
                          value: _formatData(tratamento['dataTermino'] as Timestamp?),
                          color: AppColors.textBranco,
                        ),
                        _InfoRow(
                          label: 'Status',
                          value: (tratamento['status'] ?? 'Não informado').toString(),
                          color: AppColors.textBranco,
                        ),

                        if ((tratamento['observacoes'] ?? '').toString().trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Observações',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textBranco,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (tratamento['observacoes'] ?? '').toString(),
                            style: const TextStyle(color: AppColors.textBranco),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // ---------- Card de estoque ----------
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundVerde,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackgroundBranco,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estoque',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textVerde,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          label: 'Quantidade',
                          value: estoque != null
                              ? '${estoque['qtdAtual'].toString()} $tipoMedicamento'
                              : '',
                          color: AppColors.textVerde,
                        ),
                        _InfoRow(
                          label: 'Avisar em',
                          value: estoque != null
                              ? '${estoque['qtdMinima'].toString()} $tipoMedicamento'
                              : '',
                          color: AppColors.textVerde,
                        ),
                        _InfoRow(
                          label: 'Validade',
                          value: estoque != null
                              ? DateFormat('dd/MM/yyyy')
                              .format((estoque['dataValidade'] as Timestamp).toDate())
                              : '-',
                          color: AppColors.textVerde,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ---------- Ações ----------
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardBackgroundBranco,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackgroundVerde,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.botoesBrancos,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: onCancel,
                            child: const Text(
                              'Editar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textVerde,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.botoesBrancos,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: onCancel,
                            child: const Text(
                              'Concluir Tratamento',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textVerde,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.botoesBrancos,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: onCancel,
                            child: const Text(
                              'Compartilhar com Cuidador',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textVerde,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 160,
                child: Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(color: color),
                  textAlign: TextAlign.right,
                  softWrap: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
