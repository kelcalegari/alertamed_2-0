import 'package:flutter/material.dart';

import '../model/horarios_model.dart';
import '../service/gerenciar_horarios.dart';


class HorariosRefeicaoController extends ChangeNotifier {
  final HorariosRefeicaoService repo;
  final String userId;

  /// Lista editável (não usa "Adicione" internamente; a UI decide como renderizar)
  final List<HorarioRefeicaoModel> _horarios = [];

  List<HorarioRefeicaoModel> get horarios => List.unmodifiable(_horarios);

  HorariosRefeicaoController({
    required this.repo,
    required this.userId,
    List<HorarioRefeicaoModel>? initial,
  }) {
    if (initial != null && initial.isNotEmpty) {
      _horarios.addAll(_sanitize(initial));
    } else {
      _horarios.addAll(defaultHorarios());
    }
  }

  /// Carrega do Firestore
  static Future<HorariosRefeicaoController> load({
    required String userId,
    required HorariosRefeicaoService repo,
  }) async {
    final loaded = await repo.load(userId);
    return HorariosRefeicaoController(userId: userId, repo: repo, initial: loaded);
  }

  /// Garante "Padrão" quando a semana não está completa de dias específicos
  List<HorarioRefeicaoModel> _sanitize(List<HorarioRefeicaoModel> list) {
    final hasAllWeek = diasSemanaSemPadrao
        .every((d) => list.any((h) => h.dia == d));
    final filtered = <HorarioRefeicaoModel>[
      ...list.where((h) => h.dia != DiaSemana.padrao),
    ];

    if (!hasAllWeek) {
      // Insere Padrão no início, se não existir
      final padrao = list.firstWhere(
            (h) => h.dia == DiaSemana.padrao,
        orElse: () => defaultHorarios().first,
      );
      filtered.insert(0, padrao);
    }
    return filtered;
  }

  bool _diaEmUso(DiaSemana dia) => _horarios.any((h) => h.dia == dia);

  /// Cria novo item para um dia específico
  bool addDia({
    required DiaSemana dia,
    TimeOfDay cafe = const TimeOfDay(hour: 7, minute: 30),
    TimeOfDay almoco = const TimeOfDay(hour: 12, minute: 0),
    TimeOfDay janta = const TimeOfDay(hour: 19, minute: 0),
  }) {
    if (dia == DiaSemana.padrao) return false; // Padrão é gerenciado automaticamente
    if (_diaEmUso(dia)) return false;
    _horarios.add(HorarioRefeicaoModel(dia: dia, cafe: cafe, almoco: almoco, janta: janta));
    _reorganizar();
    notifyListeners();
    return true;
  }

  /// Edita os horários de um dia (inclui "Padrão")
  void editTimes(DiaSemana dia, {TimeOfDay? cafe, TimeOfDay? almoco, TimeOfDay? janta}) {
    final idx = _horarios.indexWhere((h) => h.dia == dia);
    if (idx < 0) return;
    _horarios[idx] = _horarios[idx].copyWith(cafe: cafe, almoco: almoco, janta: janta);
    notifyListeners();
  }

  /// Troca o dia (ex.: usuário escolheu outro dia no dropdown)
  bool changeDia(DiaSemana from, DiaSemana to) {
    if (to == DiaSemana.padrao || _diaEmUso(to)) return false;
    final idx = _horarios.indexWhere((h) => h.dia == from);
    if (idx < 0) return false;
    _horarios[idx] = _horarios[idx].copyWith(dia: to);
    _reorganizar();
    notifyListeners();
    return true;
  }

  /// Remove um dia específico (não remove Padrão diretamente; ele pode voltar)
  void removeDia(DiaSemana dia) {
    if (dia == DiaSemana.padrao) return;
    _horarios.removeWhere((h) => h.dia == dia);
    _reorganizar();
    notifyListeners();
  }

  void _reorganizar() {
    final sanitized = _sanitize(_horarios);
    _horarios
      ..clear()
      ..addAll(sanitized);
    // Ordena: Padrão (se existir) primeiro, seguido de Dom..Sáb
    _horarios.sort((a, b) {
      if (a.dia == DiaSemana.padrao && b.dia != DiaSemana.padrao) return -1;
      if (b.dia == DiaSemana.padrao && a.dia != DiaSemana.padrao) return 1;
      return diasSemanaSemPadrao.indexOf(a.dia).compareTo(diasSemanaSemPadrao.indexOf(b.dia));
    });
  }

  /// Salva no Firestore
  Future<void> save() => repo.save(userId, _horarios);
}
