import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../themes/app_colors.dart';
import '../modals/sintomas_editar_popup.dart';

enum EventoStatus {
  sintoma,
  medicamentoTomado,
  medicamentoAdiado,
  medicamentoCancelado,
}

class EventoHistorico {
  final EventoStatus status;
  final DateTime hora;          // hora "do evento" (vide regras acima)
  final String nome;            // nome do sintoma/medicamento
  final String? id;             // id do doc (opcional)
  final DateTime? adiouPara;    // se adiado, nova hora (opcional)

  const EventoHistorico({
    required this.status,
    required this.hora,
    required this.nome,
    this.id,
    this.adiouPara,
  });
}

class HistoricoCard extends StatelessWidget {
  final DateTime dia;
  final void Function(EventoHistorico evento)? onTap;

  const HistoricoCard({
    super.key,
    required this.dia,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dfHora = DateFormat.Hm(locale);

    final dfDiaHora = DateFormat('dd/MM HH:mm', locale);

    final eventos = context.select<UsuarioProvider, List<EventoHistorico>>((p) {
      DateTime? _asLocal(dynamic ts) {
        if (ts == null) return null;
        if (ts is DateTime) return ts.toLocal();
        final dt = ts.toDate();
        return dt is DateTime ? dt.toLocal() : null;
      }

      bool _sameDay(DateTime? a, DateTime b) =>
          a != null && DateUtils.isSameDay(a, b);

      String _nomeMedicamento(dynamic idTratamento) {
        final t = p.tratamentosMap[idTratamento];
        if (t == null) return 'Remédio';
        return (t['nomeMedicamento'] ?? t['nome'] ?? 'Remédio').toString();
      }

      String? _id(dynamic m) => (m['id'] ?? m['id'])?.toString();

      // Monta lista
      final List<EventoHistorico> lista = [];

      // Sintomas
      for (final s in p.sintomas) {
        final dt = _asLocal(s['dataHora']);
        if (_sameDay(dt, dia)) {
          lista.add(EventoHistorico(
            status: EventoStatus.sintoma,
            hora: dt!,
            nome: (s['nome'] ?? '').toString(),
            id: _id(s),
          ));
        }
      }

      // Lembretes
      for (final l in p.lembretes) {
        final tomado = l['tomado'] == true;
        final adiado = l['adiado'] == true;
        final cancelado = (l['Cancelado'] == true) || (l['cancelado'] == true); // tolera variação
        final dtAgendado = _asLocal(l['dataHoraAgendado']);
        final dtTomado = _asLocal(l['dataHoraTomado']);
        final idTratamento = l['idTratamento'];

        // Tomado (evento no momento em que tomou)
        if (tomado && dtTomado != null && _sameDay(dtTomado, dia)) {
          lista.add(EventoHistorico(
            status: EventoStatus.medicamentoTomado,
            hora: dtTomado,
            nome: _nomeMedicamento(idTratamento),
            id: _id(l),
          ));
        }

        // Cancelado (evento no horário original agendado)
        if (cancelado && dtAgendado != null && _sameDay(dtAgendado, dia)) {
          lista.add(EventoHistorico(
            status: EventoStatus.medicamentoCancelado,
            hora: dtAgendado,
            nome: _nomeMedicamento(idTratamento),
            id: _id(l),
          ));
        }

        // Adiado (evento no horário original; tenta achar o novo horário)
        if (adiado && dtAgendado != null && _sameDay(dtAgendado, dia)) {
          DateTime? novaHora;
          final idNovo = l['idNovoLembrete']?.toString();
          if (idNovo != null && idNovo.isNotEmpty) {
            final novo = p.lembretes.cast<Map<String, dynamic>?>().firstWhere(
                  (x) => x != null && _id(x) == idNovo,
              orElse: () => null,
            );
            novaHora = _asLocal(novo?['dataHoraAgendado']);
          }

          lista.add(EventoHistorico(
            status: EventoStatus.medicamentoAdiado,
            hora: dtAgendado,
            nome: _nomeMedicamento(idTratamento),
            id: _id(l),
            adiouPara: novaHora,
          ));
        }
      }

      // Ordena por hora
      lista.sort((a, b) => a.hora.compareTo(b.hora));
      return lista;
    });

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Histórico",
              style: TextStyle(color: AppColors.textBranco, fontSize: 18)),
          const SizedBox(height: 8),

          if (eventos.isEmpty)
            _vazio()
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: eventos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final e = eventos[index];
                final hora = dfHora.format(e.hora);
                final icon = _iconFor(e.status);
                final statusChip = _statusChip(e, dfHora, dfDiaHora);

                return InkWell(
                  enableFeedback: false,
                  key: ValueKey('${e.status}-${e.hora.millisecondsSinceEpoch}-${e.id ?? e.nome}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap == null ? null : () => onTap!(e),
                  onLongPress: () {
                    if (e.status == EventoStatus.sintoma) {
                      HapticFeedback.lightImpact();
                      try {
                         onLongPressSintoma(context, e);
                      } catch (err) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro ao abrir edição: $err')),
                        );
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackgroundBranco,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          hora,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textVerde,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            children: [
                              Icon(icon, color: AppColors.textVerde, size: 20),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _capitalize(e.nome),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textVerde,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (statusChip != null) statusChip,
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _vazio() => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppColors.cardBackgroundBranco,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      "Nenhum evento nesse dia.",
      style: TextStyle(color: AppColors.textVerde),
    ),
  );

  static IconData _iconFor(EventoStatus s) {
    switch (s) {
      case EventoStatus.sintoma:
        return Icons.healing;
      case EventoStatus.medicamentoTomado:
        return Icons.medication; // poderia ser Icons.check_circle_outline
      case EventoStatus.medicamentoAdiado:
        return Icons.schedule;
      case EventoStatus.medicamentoCancelado:
        return Icons.cancel_outlined;
    }
  }

  static Widget? _statusChip(
      EventoHistorico e,
      DateFormat dfHora,
      DateFormat dfDiaHora,
      ) {
    switch (e.status) {
      case EventoStatus.sintoma:
        return null;
      case EventoStatus.medicamentoTomado:
        return _chip("Tomado");
      case EventoStatus.medicamentoAdiado:
      // agora sempre tenta mostrar DIA + DATA + HORA do novo agendamento
        final destino = (e.adiouPara != null)
            ? " → ${dfDiaHora.format(e.adiouPara!)}"
            : ""; // se não tiver o novo horário, mantém apenas "Adiado"
        return _chip(
          "Adiado$destino",
          bg: AppColors.botoesCinza,
          fg: AppColors.textBranco
        );
      case EventoStatus.medicamentoCancelado:
        return _chip(
          "Cancelado",
          bg: AppColors.botoesVermelho,
          fg: AppColors.textBranco,
        );
    }
  }

  static Widget _chip(String text, {Color? bg, Color? fg}) {
    final base = bg ?? AppColors.cardBackgroundVerde;
    final stroke = (fg ?? base).withOpacity(0.7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: stroke),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg ?? AppColors.textBranco,
        ),
      ),
    );
  }


  static String _capitalize(String? s) {
    if (s == null || s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }
}
