import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/user_data_provider.dart';

class TratamentosCard extends StatelessWidget {
  final DateTime dataReferencia;
  final void Function(Map<String, dynamic> medicamento, Map<String, dynamic> tratamento) onTapTratamento;

  const TratamentosCard({
    super.key,
    required this.dataReferencia,
    required this.onTapTratamento,
  });

  // ================= Helpers de data =================
  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _ativoNaData(Map<String, dynamic> t, DateTime ref) {
    final status = (t['status'] ?? '').toString().toLowerCase();
    if (status == 'cancelado') return false;

    final inicioTs = t['dataInicio'];
    if (inicioTs is! Timestamp) return false;
    final inicio = _dateOnly(inicioTs.toDate());

    final terminoTs = t['dataTermino'];
    final DateTime? termino = (terminoTs is Timestamp) ? _dateOnly(terminoTs.toDate()) : null;

    final refDay = _dateOnly(ref);

    final depoisOuNoInicio = !refDay.isBefore(inicio);      // ref >= inicio
    final antesOuNoTermino = (termino == null) ? true : !refDay.isAfter(termino); // ref <= termino

    return depoisOuNoInicio && antesOuNoTermino;
  }

  // ================= Helpers de formatação =================
  String _fmtData(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _linhaAgendaHoje(List lembretes) {
    if (lembretes.isEmpty) return '';
    final List<String> partes = [];
    for (final l in lembretes) {
      final tipo = (l['tipo'] ?? '').toString();
      final valor = (l['valor'] ?? '').toString();
      final momento = (l['momento'] ?? '').toString(); // antes|junto|depois
      if (tipo == 'hora_fixa' && valor.isNotEmpty) {
        partes.add(valor); // ex: 08:00
      } else if (tipo == 'refeicao' && valor.isNotEmpty) {
        final quando = (momento.isNotEmpty) ? '$momento ' : '';
        partes.add('$quando$valor'); // ex: "antes almoço"
      }
    }
    if (partes.isEmpty) return '';
    return 'Hoje: ${partes.join(' • ')}';
  }

  // Badge "chip"
  Widget _badge(String text, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? const Color(0xFF004d40),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg ?? Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Constrói o título com nome + (tipo) + badges inline, usando RichText
  Widget _tituloComBadges({
    required String nome,
    required String tipo,
    required List<InlineSpan> badgeSpans,
  }) {
    final titulo = [
      nome,
      if (tipo.isNotEmpty) ' ($tipo)',
    ].join('');

    return RichText(
      maxLines: 2, // permite quebrar badges para a linha de baixo se necessário
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          height: 1.15,
        ),
        children: <InlineSpan>[
          TextSpan(text: titulo),
          // pequeno espaço entre o texto e o primeiro badge
          if (badgeSpans.isNotEmpty) const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(width: 6),
          ),
          ...badgeSpans,
        ],
      ),
    );
  }

  // Converte um widget de badge para um WidgetSpan inline
  InlineSpan _badgeSpan(Widget badge) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 2),
        child: badge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<UsuarioProvider>(context);

    final values = provider.tratamentosMap.values.cast<Map<String, dynamic>>();

    final tratamentos = values.where((t) => _ativoNaData(t, dataReferencia)).toList()
      ..sort((a, b) => (a['nomeMedicamento'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['nomeMedicamento'] ?? '').toString().toLowerCase()));

    if (tratamentos.isEmpty) {
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
              'Seus Tratamentos',
              style: TextStyle(color: Color(0xFF002600), fontSize: 20),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF002600),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const ListTile(
                  title: Text(
                    'Não há tratamentos ativos nesta data',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  trailing: Icon(Icons.info_outline, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

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
            'Seus Tratamentos',
            style: TextStyle(color: Color(0xFF002600), fontSize: 20),
          ),
          const SizedBox(height: 12),
          ...tratamentos.map((tratamento) {
            final nome = (tratamento['nomeMedicamento'] ?? 'Medicamento').toString();
            final tipo = (tratamento['tipoMedicamento'] ?? '').toString();
            final conc = (tratamento['concentracaoMedicamento'] ?? '').toString();
            final dosagem = (tratamento['dosagem'] ?? '').toString();
            final freq = (tratamento['frequencia'] ?? '').toString();
            final tipoTrat = (tratamento['tipoTratamento'] ?? '').toString();
            final obs = (tratamento['observacoes'] ?? '').toString();
            final status = (tratamento['status'] ?? 'ativo').toString().toLowerCase();


            final inicioTs = tratamento['dataInicio'] as Timestamp?;
            final terminoTs = tratamento['dataTermino'] as Timestamp?;
            final inicio = inicioTs?.toDate();
            final termino = terminoTs?.toDate();


            // Badges inline no título
            final badgeSpans = <InlineSpan>[
              if (conc.isNotEmpty) _badgeSpan(_badge(conc, bg: Colors.white24)),
              if (status != 'ativo')
                _badgeSpan(_badge(
                  status[0].toUpperCase() + status.substring(1),
                  bg: status == 'cancelado' ? Colors.red[700] : Colors.orange[700],
                )),
            ];

            // Subtitle: até 3 linhas curtas (sem badges agora)
            final subs = <Widget>[
              if (dosagem.isNotEmpty || freq.isNotEmpty)
                Text(
                  [if (dosagem.isNotEmpty) dosagem, if (freq.isNotEmpty) freq].join(' • '),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              if (inicio != null)
                Text(
                  termino != null
                      ? '${_fmtData(inicio)} → ${_fmtData(termino)}'
                      : 'Contínuo${tipoTrat.isNotEmpty ? ' • $tipoTrat' : ''}',
                  style: const TextStyle(color: Colors.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),

              if (obs.isNotEmpty)
                Text(
                  obs,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
            ];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF002600),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () => onTapTratamento(tratamento, tratamento),
                  leading: const Icon(Icons.medication, color: Colors.white),
                  title: _tituloComBadges(
                    nome: nome,
                    tipo: tipo,
                    badgeSpans: badgeSpans,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: subs,
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white),
                  isThreeLine: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minLeadingWidth: 0,
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
