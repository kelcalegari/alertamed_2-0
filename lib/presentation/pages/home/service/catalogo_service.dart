// lib/core/services/medication_catalog_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationCatalogService {
  final _db = FirebaseFirestore.instance;

  /// Busca em /medicamentos_publicos e também em /usuarios/{uid}/medicamentos_custom (opcional)
  Future<List<Map<String, dynamic>>> searchByPrefix({
    required String query,
    String? userId,
    int limit = 8,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];

    final pubRef = _db.collection('medicamentos_publicos')
        .orderBy('nomeLower')
        .startAt([q]).endAt([q + '\uf8ff']).limit(limit);

    final futures = <Future<QuerySnapshot>>[pubRef.get()];

    if (userId != null && userId.isNotEmpty) {
      final usrRef = _db.collection('usuarios').doc(userId)
          .collection('medicamentos_custom')
          .orderBy('nomeLower')
          .startAt([q]).endAt([q + '\uf8ff']).limit(limit);
      futures.add(usrRef.get());
    }

    final snaps = await Future.wait(futures);
    final items = <Map<String, dynamic>>[];
    for (final s in snaps) {
      for (final d in s.docs) {
        final m = d.data() as Map<String, dynamic>;
        items.add({
          ...m,
          '_id': d.id,
          '_path': d.reference.path,
          '_isCustom': d.reference.parent.id == 'medicamentos_custom',
        });
      }
    }

    // Remove duplicados por "nomeLower" preferindo o custom
    final seen = <String>{};
    final dedup = <Map<String, dynamic>>[];
    for (final m in items) {
      final key = (m['nomeLower'] ?? '').toString();
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);
      dedup.add(m);
    }
    return dedup.take(limit).toList();
  }

  Future<Map<String, dynamic>?> getByIdPath(String fullPath) async {
    final doc = await _db.doc(fullPath).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    return {...data, '_id': doc.id, '_path': doc.reference.path};
  }
}
