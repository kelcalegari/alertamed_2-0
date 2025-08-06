import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../routes/routes.dart';
import '../../../themes/app_colors.dart';

class SemanaSelector extends StatefulWidget {
  final Function(DateTime) onSemanaChanged;

  const SemanaSelector({Key? key, required this.onSemanaChanged})
    : super(key: key);

  @override
  _SemanaSelectorState createState() => _SemanaSelectorState();
}

class _SemanaSelectorState extends State<SemanaSelector> {
  DateTime semanaAtual = DateTime.now();
  DateTime diaSelecionado = DateTime.now();

  List<DateTime> getDiasDaSemana() {
    int diaSemana = semanaAtual.weekday; // 1 = segunda, 7 = domingo
    DateTime segunda = semanaAtual.subtract(
      Duration(days: diaSemana - 1),
    ); // começa na segunda

    return List.generate(7, (index) => segunda.add(Duration(days: index)));
  }

  void mudarSemana(int direcao) {
    setState(() {
      semanaAtual = semanaAtual.add(Duration(days: 7 * direcao));
      final dias = getDiasDaSemana();
      if (!dias.any((d) => isSameDate(d, diaSelecionado))) {
        diaSelecionado = dias[0];
      }
    });
    widget.onSemanaChanged(diaSelecionado);
  }

  bool isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String getTituloDiaSelecionado() {
    final hoje = DateTime.now();
    if (isSameDate(diaSelecionado, hoje)) {
      return "HOJE ${diaSelecionado.day.toString().padLeft(2, '0')} DE ${DateFormat.MMMM('pt_BR').format(diaSelecionado).toUpperCase()}";
    } else {
      return "${DateFormat.EEEE('pt_BR').format(diaSelecionado).toUpperCase()} ${diaSelecionado.day.toString().padLeft(2, '0')} DE ${DateFormat.MMMM('pt_BR').format(diaSelecionado).toUpperCase()}";
    }
  }

  @override
  Widget build(BuildContext context) {
    final dias = getDiasDaSemana();

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
                  setState(() {
                    diaSelecionado = DateTime.now();
                    semanaAtual = DateTime.now();
                  });
                  widget.onSemanaChanged(diaSelecionado);
                },
                child: Text(
                  getTituloDiaSelecionado(),
                  style: TextStyle(
                    color: AppColors.textBranco,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [

                  IconButton(
                    icon: Icon(Icons.settings, color: AppColors.textBranco),
                    onPressed: () {
                      Navigator.pushNamed(context, Routes.configuracao);
                    },
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: 8),
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
              children:
                  dias.map((dia) {
                    final bool isSelecionado = isSameDate(dia, diaSelecionado);

                    return Flexible(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            diaSelecionado = dia;
                          });
                          widget.onSemanaChanged(diaSelecionado);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat.E(
                                'pt_BR',
                              ).format(dia)[0].toUpperCase(),
                              style: TextStyle(
                                color: AppColors.textBranco,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 4),
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    isSelecionado
                                        ? AppColors.diaSelecionado
                                        : AppColors.cardBackgroundBranco,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                dia.day.toString(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      isSelecionado
                                          ? AppColors.textVerde
                                          : Colors.black,
                                  fontWeight:
                                      isSelecionado
                                          ? FontWeight.bold
                                          : FontWeight.normal,
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
