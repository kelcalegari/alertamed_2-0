import 'package:flutter/material.dart';

enum DiaSemana { padrao, dom, seg, ter, qua, qui, sex, sab }

const _labels = {
  DiaSemana.padrao: 'Padrão',
  DiaSemana.dom: 'Dom',
  DiaSemana.seg: 'Seg',
  DiaSemana.ter: 'Ter',
  DiaSemana.qua: 'Qua',
  DiaSemana.qui: 'Qui',
  DiaSemana.sex: 'Sex',
  DiaSemana.sab: 'Sáb',
};

String diaLabel(DiaSemana d) => _labels[d]!;
DiaSemana diaFromLabel(String s) =>
    _labels.entries.firstWhere((e) => e.value == s).key;

/// Serializa TimeOfDay como "HH:mm"
String timeToStr(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay strToTime(String s) {
  final parts = s.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

class HorarioRefeicaoModel {
  final DiaSemana dia;
  final TimeOfDay cafe;
  final TimeOfDay almoco;
  final TimeOfDay janta;

  const HorarioRefeicaoModel({
    required this.dia,
    required this.cafe,
    required this.almoco,
    required this.janta,
  });

  HorarioRefeicaoModel copyWith({
    DiaSemana? dia,
    TimeOfDay? cafe,
    TimeOfDay? almoco,
    TimeOfDay? janta,
  }) {
    return HorarioRefeicaoModel(
      dia: dia ?? this.dia,
      cafe: cafe ?? this.cafe,
      almoco: almoco ?? this.almoco,
      janta: janta ?? this.janta,
    );
  }

  Map<String, dynamic> toMap() => {
    'dia': diaLabel(dia),
    'horaCafe': timeToStr(cafe),
    'horaAlmoco': timeToStr(almoco),
    'horaJanta': timeToStr(janta),
  };

  factory HorarioRefeicaoModel.fromMap(Map<String, dynamic> map) {
    return HorarioRefeicaoModel(
      dia: diaFromLabel(map['dia'] as String),
      cafe: strToTime(map['horaCafe'] as String),
      almoco: strToTime(map['horaAlmoco'] as String),
      janta: strToTime(map['horaJanta'] as String),
    );
  }
}

/// Lista padrão inicial
List<HorarioRefeicaoModel> defaultHorarios() => [
  HorarioRefeicaoModel(
    dia: DiaSemana.padrao,
    cafe: const TimeOfDay(hour: 7, minute: 30),
    almoco: const TimeOfDay(hour: 12, minute: 0),
    janta: const TimeOfDay(hour: 19, minute: 0),
  ),
];

const diasSemanaSemPadrao = [
  DiaSemana.dom,
  DiaSemana.seg,
  DiaSemana.ter,
  DiaSemana.qua,
  DiaSemana.qui,
  DiaSemana.sex,
  DiaSemana.sab,
];
