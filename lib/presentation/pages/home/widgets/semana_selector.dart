import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_data_provider.dart';
import '../../../routes/routes.dart';
import '../../../themes/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// + utilitário para renderizar nome público por UID
class _NomePublico extends StatelessWidget {
  final String uid;
  final String fallback; // exibe algo caso ainda não carregou
  final TextStyle? style;
  const _NomePublico({
    Key? key,
    required this.uid,
    this.fallback = 'Usuário',
    this.style,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseFirestore.instance
        .collection('usuarios_publicos')
        .doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data();
          final nome = (data?['displayName'] as String?)?.trim();
          return Text(
            (nome?.isNotEmpty ?? false) ? nome! : fallback,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }
        if (snap.hasError) {
          return Text(fallback, overflow: TextOverflow.ellipsis, style: style);
        }
        // carregando
        return Text(fallback, overflow: TextOverflow.ellipsis, style: style);
      },
    );
  }
}

class SemanaSelector extends StatefulWidget {
  final Function(DateTime) onSemanaChanged;
  final DateTime selectedDate; // ⬅️ novo (controlado pelo pai)

  const SemanaSelector({
    Key? key,
    required this.onSemanaChanged,
    required this.selectedDate, // ⬅️ novo
  }) : super(key: key);

  @override
  _SemanaSelectorState createState() => _SemanaSelectorState();
}

class _SemanaSelectorState extends State<SemanaSelector> {
  // Semana de referência que o carrossel mostra (muda ao arrastar)
  late DateTime semanaAtual;

  @override
  void initState() {
    super.initState();
    semanaAtual = _inicioDaSemana(widget.selectedDate);
  }

  @override
  void didUpdateWidget(covariant SemanaSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Se o pai trocou o dia (ex.: back para HOJE), sincroniza a semana exibida
    if (!_isMesmoDia(widget.selectedDate, oldWidget.selectedDate)) {
      setState(() {
        semanaAtual = _inicioDaSemana(widget.selectedDate);
      });
    }
  }

  DateTime _inicioDaSemana(DateTime d) {
    // 1 = seg, ... 7 = dom
    final weekday = d.weekday;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: weekday - 1));
  }

  bool _isMesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> getDiasDaSemana() {
    final segunda = _inicioDaSemana(semanaAtual);
    return List.generate(7, (i) => segunda.add(Duration(days: i)));
  }

  void mudarSemana(int direcao) {
    setState(() {
      semanaAtual = semanaAtual.add(Duration(days: 7 * direcao));
    });
    // Se a nova semana não contém o dia selecionado atual, opcionalmente
    // força o primeiro dia da semana como selecionado:
    final dias = getDiasDaSemana();
    if (!dias.any((d) => _isMesmoDia(d, widget.selectedDate))) {
      widget.onSemanaChanged(dias.first); // ⬅️ atualiza no pai
    }
  }

  String getTituloDiaSelecionado(DateTime diaSelecionado) {
    final hoje = DateTime.now();
    final fmtMes = DateFormat.MMMM('pt_BR');
    final fmtSem = DateFormat.EEEE('pt_BR');
    if (_isMesmoDia(diaSelecionado, hoje)) {
      return "HOJE ${diaSelecionado.day.toString().padLeft(2, '0')} DE ${fmtMes.format(diaSelecionado).toUpperCase()}";
    } else {
      return "${fmtSem.format(diaSelecionado).toUpperCase()} ${diaSelecionado.day.toString().padLeft(2, '0')} DE ${fmtMes.format(diaSelecionado).toUpperCase()}";
    }
  }

  @override
  Widget build(BuildContext context) {
    final dias = getDiasDaSemana();
    final diaSelecionado = DateTime(widget.selectedDate.year, widget.selectedDate.month, widget.selectedDate.day);

    final prov = context.watch<UsuarioProvider>();
    final meuUid = prov.userId;
    final meuNome = (prov.dadosUsuario['nome'] as String?) ?? 'Você';
    final pacientes = prov.vinculosMap.entries
        .where((e) => (e.value['meuPapel'] == 'cuidador') && (e.value['status'] == 'ativo'))
        .map((e) => e.key)
        .toList();
    final contextoId = prov.contextoUsuarioId;
    final bool isCuidador = pacientes.isNotEmpty;

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onLongPress: () {
                  final hoje = DateTime.now();
                  // Long press: força HOJE no pai
                  widget.onSemanaChanged(DateTime(hoje.year, hoje.month, hoje.day));
                  // E sincroniza a semana exibida
                  setState(() {
                    semanaAtual = _inicioDaSemana(hoje);
                  });
                },
                child: Text(
                  getTituloDiaSelecionado(diaSelecionado),
                  style: const TextStyle(
                    color: AppColors.textBranco,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings, color: AppColors.textBranco),
                    onPressed: () {
                      Navigator.pushNamed(context, Routes.configuracao);
                    },
                  ),
                  if (isCuidador)
                    PopupMenuButton<String>(
                      icon: Icon(
                        contextoId == meuUid ? Icons.account_circle_outlined : Icons.local_hospital_outlined,
                        color: AppColors.textBranco,
                      ),
                      color: AppColors.cardBackgroundBranco,
                      onSelected: (uidSelecionado) async {
                        await prov.setContextoUsuario(uidSelecionado);
                        setState(() {}); // atualiza ícone
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: meuUid,
                          child: Row(
                            children: [
                              const Icon(Icons.account_circle_outlined, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: _NomePublico(uid: meuUid, fallback: meuNome)),
                              if (contextoId == meuUid) const Icon(Icons.check, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        ...pacientes.map((otherUid) {
                          return PopupMenuItem<String>(
                            value: otherUid,
                            child: Row(
                              children: [
                                const Icon(Icons.local_hospital_outlined, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: _NomePublico(uid: otherUid, fallback: otherUid)),
                                if (contextoId == otherUid) const Icon(Icons.check, size: 18),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < 0) {
                mudarSemana(1);
              } else if (details.primaryVelocity! > 0) {
                mudarSemana(-1);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: dias.map((dia) {
                final bool isSelecionado = _isMesmoDia(dia, diaSelecionado);
                return Flexible(
                  child: InkWell(
                    onTap: () {
                      widget.onSemanaChanged(dia); // seleciona no pai
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat.E('pt_BR').format(dia)[0].toUpperCase(),
                          style: const TextStyle(color: AppColors.textBranco, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelecionado ? AppColors.diaSelecionado : AppColors.cardBackgroundBranco,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            dia.day.toString(),
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelecionado ? AppColors.textVerde : Colors.black,
                              fontWeight: isSelecionado ? FontWeight.bold : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
