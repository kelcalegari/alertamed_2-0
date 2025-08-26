import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UsuarioProvider extends ChangeNotifier {
  Map<String, dynamic> dadosUsuario = {};

  // NOVO: horários
  List<Map<String, dynamic>> horariosRefeicoes = [];
  List<Map<String, dynamic>> horariosSilenciosos = [];

  List<Map<String, dynamic>> sintomas = [];
  List<Map<String, dynamic>> lembretes = [];
  Map<String, dynamic> tratamentosMap = {};
  Map<String, dynamic> estoqueMap = {};
  Map<String, dynamic> infoMedica = {};

  bool isLoading = true;
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? "";

  UsuarioProvider() {
    fetchData();
  }

  Future<void> fetchData() async {
    if (userId.isEmpty) {
      isLoading = false;
      notifyListeners();
      return;
    }

    final usuarioRef = FirebaseFirestore.instance.collection('usuarios').doc(userId);

    await Future.wait([
      _loadDadosUsuario(usuarioRef),
      _loadHorariosRefeicoes(usuarioRef),
      _loadHorariosSilenciosos(usuarioRef),
      _loadSintomas(usuarioRef),
      _loadLembretes(usuarioRef),
      _loadTratamentos(usuarioRef),
      _loadEstoque(usuarioRef),
      _loadInfoMedicaDireto(usuarioRef),
    ]);

    isLoading = false;
    notifyListeners();
  }

  Future<void> _loadDadosUsuario(DocumentReference usuarioRef) async {
    try {
      final doc = await usuarioRef.get();
      if (doc.exists && doc.data() != null) {
        dadosUsuario = doc.data() as Map<String, dynamic>;
      } else {
        dadosUsuario = {};
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do usuário: $e');
      dadosUsuario = {};
    }
  }

  // ---------- NOVOS MÉTODOS (Horários) ----------

  List<Map<String, dynamic>> _defaultHorariosRefeicoes() => [
    {
      'dia': 'Padrão',
      'horaCafe': '07:30',
      'horaAlmoco': '12:00',
      'horaJanta': '19:00',
    }
  ];

  List<Map<String, dynamic>> _defaultHorariosSilenciosos() => [
    {
      'dia': 'Todos',
      'horaInicio': '22:00',
      'horaFim': '06:00',
    }
  ];

  Future<void> _loadHorariosRefeicoes(DocumentReference usuarioRef) async {
    try {
      final doc = await usuarioRef.get();
      final data = (doc.data() as Map<String, dynamic>?) ?? {};
      final list = (data['horariosRefeicoes'] as List?)?.cast<Map<String, dynamic>>();
      horariosRefeicoes = (list == null || list.isEmpty)
          ? _defaultHorariosRefeicoes()
          : list;
    } catch (e) {
      debugPrint('Erro ao carregar horariosRefeicoes: $e');
      horariosRefeicoes = _defaultHorariosRefeicoes();
    }
  }

  Future<void> _loadHorariosSilenciosos(DocumentReference usuarioRef) async {
    try {
      final doc = await usuarioRef.get();
      final data = (doc.data() as Map<String, dynamic>?) ?? {};
      final list = (data['horariosSilenciosos'] as List?)?.cast<Map<String, dynamic>>();
      horariosSilenciosos = (list == null || list.isEmpty)
          ? _defaultHorariosSilenciosos()
          : list;
    } catch (e) {
      debugPrint('Erro ao carregar horariosSilenciosos: $e');
      horariosSilenciosos = _defaultHorariosSilenciosos();
    }
  }

  Future<void> salvarHorariosRefeicoes(List<Map<String, dynamic>> novos) async {
    if (userId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(userId).set(
        {'horariosRefeicoes': novos},
        SetOptions(merge: true),
      );
      horariosRefeicoes = novos;
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao salvar horariosRefeicoes: $e');
    }
  }

  Future<void> salvarHorariosSilenciosos(List<Map<String, dynamic>> novos) async {
    if (userId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(userId).set(
        {'horariosSilenciosos': novos},
        SetOptions(merge: true),
      );
      horariosSilenciosos = novos;
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao salvar horariosSilenciosos: $e');
    }
  }

  /// Helper: retorna o registro de horários de refeição para um dia
  /// (aceita 'Dom', 'Seg', ..., 'Sáb' ou 'Padrão' se não encontrar).
  Map<String, dynamic> horarioRefeicaoParaDia(String dia) {
    final item = horariosRefeicoes.firstWhere(
          (h) => (h['dia'] as String).toLowerCase() == dia.toLowerCase(),
      orElse: () => const {},
    );
    if (item.isNotEmpty) return item;

    // fallback para 'Padrão'
    return horariosRefeicoes.firstWhere(
          (h) => (h['dia'] as String).toLowerCase() == 'padrão' || (h['dia'] as String).toLowerCase() == 'padrao',
      orElse: () => _defaultHorariosRefeicoes().first,
    );
    // Obs: aceita 'Padrão' e 'Padrao' para evitar problemas de acentuação.
  }

  // ---------- Já existentes ----------

  Future<void> _loadSintomas(DocumentReference usuarioRef) async {
    try {
      final snapshot = await usuarioRef.collection('sintomas').get();
      sintomas = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar sintomas: $e');
      sintomas = [];
    }
  }
  Future<void> refreshSintomas() async {
    if (userId.isEmpty) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('usuarios').doc(userId)
          .collection('sintomas')
          .orderBy('dataHora', descending: true)
          .get();

      sintomas = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao atualizar sintomas: $e');
    }
  }
  Future<void> _loadLembretes(DocumentReference usuarioRef) async {
    try {
      final snapshot = await usuarioRef.collection('lembretes').get();
      lembretes = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('Erro ao carregar lembretes: $e');
      lembretes = [];
    }
  }

  Future<void> _loadTratamentos(DocumentReference usuarioRef) async {
    try {
      final tratamentosSnapshot = await usuarioRef.collection('tratamentos').get();
      final tratamentos = tratamentosSnapshot.docs.map((doc) {
        final data = doc.data();
        data['idTratamento'] = doc.id;
        return data;
      }).toList();

      tratamentosMap = {
        for (var tratamento in tratamentos) tratamento['idTratamento']: tratamento,
      };
    } catch (e) {
      debugPrint('Erro ao carregar tratamentoss: $e');
      tratamentosMap = {};
    }
  }

  Future<void> _loadEstoque(DocumentReference usuarioRef) async {
    try {
      final snapshot = await usuarioRef.collection('estoque').get();
      estoqueMap = {for (var doc in snapshot.docs) doc.id: doc.data()};
    } catch (e) {
      debugPrint('Erro ao carregar estoque: $e');
      estoqueMap = {};
    }
  }

  Future<void> _loadInfoMedicaDireto(DocumentReference usuarioRef) async {
    try {
      final doc = await usuarioRef
          .collection('informacoesmedicas')
          .doc('perfil')
          .get();

      infoMedica = (doc.exists && doc.data() != null) ? doc.data()! : {};
    } catch (e) {
      debugPrint('Erro ao carregar informacoesmedicas: $e');
      infoMedica = {};
    }
  }
  Future<void> refreshInfoMedica() async {
    final usuarioRef = FirebaseFirestore.instance.collection('usuarios').doc(userId);
    await _loadInfoMedicaDireto(usuarioRef);
    notifyListeners();
  }
}
