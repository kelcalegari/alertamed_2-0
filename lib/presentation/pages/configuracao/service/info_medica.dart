// info_medica_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class InfoMedicaService {
  final FirebaseFirestore _db;
  InfoMedicaService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _perfilDoc(String uid) =>
      _db.collection('usuarios').doc(uid).collection('informacoesmedicas').doc('perfil');

  /// Cria/atualiza (merge) os dados do perfil.
  Future<void> upsertPerfil(String uid, Map<String, dynamic> data) async {
    await _perfilDoc(uid).set(
      {...data, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Substitui completamente (sem merge).
  Future<void> replacePerfil(String uid, Map<String, dynamic> data) async {
    await _perfilDoc(uid).set({...data, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Atualiza campos específicos (falha se o doc não existir).
  Future<void> updateCampos(String uid, Map<String, dynamic> campos) async {
    await _perfilDoc(uid).update({...campos, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// (Opcional) Remover perfil.
  Future<void> deletarPerfil(String uid) async {
    await _perfilDoc(uid).delete();
  }
}
