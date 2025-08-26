import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/horarios_model.dart';


class HorariosRefeicaoService {
  final FirebaseFirestore _db;
  HorariosRefeicaoService([FirebaseFirestore? instance])
      : _db = instance ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _db.collection('usuarios').doc(userId);

  Future<List<HorarioRefeicaoModel>> load(String userId) async {
    final snap = await _userDoc(userId).get();
    final data = snap.data() ?? {};
    final list = (data['horariosRefeicoes'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>() ??
        [];
    if (list.isEmpty) return defaultHorarios();
    return list.map(HorarioRefeicaoModel.fromMap).toList();
  }

  /// Persiste a lista inteira (simples e transacional no nível do doc)
  Future<void> save(String userId, List<HorarioRefeicaoModel> horarios) async {
    await _userDoc(userId).set({
      'horariosRefeicoes': horarios.map((e) => e.toMap()).toList(),
    }, SetOptions(merge: true));
  }
}
