import 'package:flutter/material.dart';

import '../../../themes/app_colors.dart';



class HorarioSilencioso {
  String dia;
  TimeOfDay inicio;
  TimeOfDay fim;

  HorarioSilencioso({
    required this.dia,
    required this.inicio,
    required this.fim,
  });
}

class ModoSilenciosoWidget extends StatefulWidget {
  const ModoSilenciosoWidget({super.key});

  @override
  State<ModoSilenciosoWidget> createState() => _ModoSilenciosoWidgetState();
}

class _ModoSilenciosoWidgetState extends State<ModoSilenciosoWidget> {
  final List<String> diasDisponiveis = [
    "Padrão", "Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"
  ];

  final List<String> diasDaSemana = [
    "Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"
  ];

  final List<HorarioSilencioso> horarios = [
    HorarioSilencioso(
      dia: "Padrão",
      inicio: const TimeOfDay(hour: 22, minute: 0),
      fim: const TimeOfDay(hour: 7, minute: 0),
    ),
    HorarioSilencioso(
      dia: "Adicione",
      inicio: const TimeOfDay(hour: 0, minute: 0),
      fim: const TimeOfDay(hour: 0, minute: 0),
    ),
  ];

  void _verificarDiasEAtualizar() {
    final diasSelecionados = horarios.map((h) => h.dia).toList();
    final contemTodos = diasDaSemana.every((d) => diasSelecionados.contains(d));

    if (contemTodos) {
      horarios.removeWhere((h) => h.dia == "Padrão");
    } else {
      if (!horarios.any((h) => h.dia == "Padrão")) {
        horarios.insert(
          0,
          HorarioSilencioso(
            dia: "Padrão",
            inicio: const TimeOfDay(hour: 22, minute: 0),
            fim: const TimeOfDay(hour: 7, minute: 0),
          ),
        );
      }
    }

    final usados = horarios.map((h) => h.dia).where((d) => d != "Adicione").toSet();
    final podeAdicionar = usados.length < diasDaSemana.length;

    if (podeAdicionar && !horarios.any((h) => h.dia == "Adicione")) {
      horarios.add(HorarioSilencioso(
        dia: "Adicione",
        inicio: const TimeOfDay(hour: 0, minute: 0),
        fim: const TimeOfDay(hour: 0, minute: 0),
      ));
    } else if (!podeAdicionar) {
      horarios.removeWhere((h) => h.dia == "Adicione");
    }
  }

  Future<void> _selecionarHorario(int index, String tipo) async {
    final TimeOfDay? selecionado = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (selecionado != null) {
      setState(() {
        if (tipo == "inicio") {
          horarios[index].inicio = selecionado;
        } else {
          horarios[index].fim = selecionado;
        }
      });
    }
  }

  Widget _buildLinhaHorario(int index) {
    final h = horarios[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: h.dia == "Adicione" ? null : h.dia,
              hint: Text("Adicione", style: TextStyle(color: AppColors.textVerde)),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    h.dia = value;
                    _verificarDiasEAtualizar();
                  });
                }
              },
              items: diasDisponiveis
                  .where((d) =>
              d == h.dia || (!horarios.any((h) => h.dia == d) && d != "Adicione"))
                  .map((d) => DropdownMenuItem(
                value: d,
                child: Text(d, style: const TextStyle(color: AppColors.textVerde)),
              ))
                  .toList(),
              decoration: InputDecoration(
                fillColor: AppColors.inputBranco,
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildHoraCampo(h.inicio, () => _selecionarHorario(index, "inicio")),
          const SizedBox(width: 8),
          _buildHoraCampo(h.fim, () => _selecionarHorario(index, "fim")),
        ],
      ),
    );
  }

  Widget _buildHoraCampo(TimeOfDay hora, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.inputBranco,
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: Text(
            hora.format(context),
            style: const TextStyle(fontSize: 16, color: AppColors.textVerde),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Modo Silencioso por Dia",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textVerde),
          ),
          const SizedBox(height: 8),
          const Text(
            "Escolha horários em que o app não deve enviar alertas sonoros.",
            style: TextStyle(color: AppColors.textVerde),
          ),
          const SizedBox(height: 24),
          Row(
            children: const [
              Expanded(
                flex: 2,
                child: Text("Dia",
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textVerde)),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text("Início",
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textVerde),
                    textAlign: TextAlign.center),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text("Fim",
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textVerde),
                    textAlign: TextAlign.center),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.builder(
            itemCount: horarios.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) => _buildLinhaHorario(index),
          ),
        ],
      ),
    );
  }
}
