import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VinculoService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _me => _auth.currentUser!.uid;

  /// Busca um usuário pelo e-mail em /usuarios_publicos
  Future<DocumentSnapshot<Map<String, dynamic>>?> buscarUsuarioPorEmail(String email) async {
    final emailLower = email.trim().toLowerCase();
    final q = await _db.collection('usuarios_publicos')
        .where('emailLower', isEqualTo: emailLower)
        .limit(1).get();
    if (q.docs.isEmpty) return null;
    return q.docs.first;
  }

  /// Envia solicitação de vínculo. Quem chama decide se quer "cuidar de" (solicitante=cuidador)
  /// ou "ser cuidado" (solicitante=paciente). Aqui implemento o fluxo: cuidador -> paciente.
  Future<String> solicitarComoCuidador({
    required String pacienteUid,
    List<String>? scopes,
    Map<String, dynamic>? meta, // NEW
  }) async {
    if (pacienteUid == _me) {
      throw Exception('Você não pode solicitar vínculo com você mesmo.');
    }
    final ref = _db.collection('solicitacoesVinculo').doc();
    await ref.set({
      'solicitanteId': _me,
      'cuidadorId': _me,
      'pacienteId': pacienteUid,
      'scopesSugeridos': scopes ?? ['leitura','lembretes'],
      'status': 'pendente',
      'criadoEm': FieldValue.serverTimestamp(),
      'decididoEm': null,
      if (meta != null) 'meta': meta, // NEW
    });
    return ref.id;
  }


  /// Alternativamente: paciente -> cuidador
  Future<String> solicitarComoPaciente({required String cuidadorUid, List<String>? scopesDesejados}) async {
    if (cuidadorUid == _me) {
      throw Exception('Você não pode solicitar vínculo com você mesmo.');
    }
    final ref = _db.collection('solicitacoesVinculo').doc();
    await ref.set({
      'solicitanteId': _me,
      'cuidadorId': cuidadorUid,
      'pacienteId': _me,
      'scopesSugeridos': scopesDesejados ?? ['leitura','lembretes'],
      'status': 'pendente',
      'criadoEm': FieldValue.serverTimestamp(),
      'decididoEm': null,
    });
    return ref.id;
  }

  /// Aprovar solicitação (só o "outro" lado pode aprovar, as regras garantem)
  Future<void> aprovarSolicitacao(String solicId,
      {List<String>? scopesAprovados, String? nivel}) async {
    await _db.runTransaction((tx) async {
      final sRef = _db.collection('solicitacoesVinculo').doc(solicId);
      final sSnap = await tx.get(sRef);
      if (!sSnap.exists) throw Exception('Solicitação não encontrada');
      final s = sSnap.data()!;
      if (s['status'] != 'pendente') throw Exception('Solicitação já processada');

      final cuidadorId = s['cuidadorId'] as String;
      final pacienteId = s['pacienteId'] as String;
      final suggested = List<String>.from(s['scopesSugeridos'] ?? const ['leitura','lembretes']);
      final scopes = (scopesAprovados == null || scopesAprovados.isEmpty) ? suggested : scopesAprovados;

      String nivelFromScopes(List<String> scopes) {
        final st = scopes.toSet();
        if (st.contains('bloquear_paciente_editar')) return 'acesso_completo';
        if (st.contains('edicao_tratamentos')) return 'gerenciamento_restrito';
        return 'visualizacao_basica';
      }

      final nivelFinal = nivel ?? nivelFromScopes(scopes);

      final pVinc = _db.collection('usuarios').doc(pacienteId).collection('vinculos').doc(cuidadorId);
      final cVinc = _db.collection('usuarios').doc(cuidadorId).collection('vinculos').doc(pacienteId);

      tx.set(pVinc, {
        'meuPapel': 'paciente',
        'roleDoOutro': 'cuidador',
        'scopes': scopes,
        'nivel': nivelFinal, // NEW
        'status': 'ativo',
        'criadoEm': FieldValue.serverTimestamp(),
        'criadoPor': _me,
        'solicId': solicId,
      });

      tx.set(cVinc, {
        'meuPapel': 'cuidador',
        'roleDoOutro': 'paciente',
        'scopes': [],
        'nivel': nivelFinal, // NEW
        'status': 'ativo',
        'criadoEm': FieldValue.serverTimestamp(),
        'criadoPor': _me,
        'solicId': solicId,
      });

      tx.update(sRef, {
        'status': 'aprovado',
        'decididoEm': FieldValue.serverTimestamp(),
        'nivelAprovado': nivelFinal,   // opcional: histórico
        'scopesAprovados': scopes,     // opcional: histórico
      });

      // OPCIONAL: flag agregada para bloquear edição do paciente
      final bloqueia = scopes.contains('bloquear_paciente_editar');
      final flagRef = _db.collection('usuarios').doc(pacienteId).collection('flags').doc('bloqueio_edicao');
      tx.set(flagRef, {'ativo': bloqueia}, SetOptions(merge: true));
    });
  }

// Helper simples
  String _nivelFromScopes(List<String> scopes) {
    final s = scopes.toSet();
    if (s.contains('bloquear_paciente_editar')) return 'acesso_completo';
    if (s.contains('edicao_tratamentos')) return 'gerenciamento_restrito';
    return 'visualizacao_basica';
  }


  /// Negar/cancelar
  Future<void> atualizarStatusSolicitacao(String solicId, String novoStatus) async {
    await _db.collection('solicitacoesVinculo').doc(solicId).update({
      'status': novoStatus, // "negado" ou "cancelado"
      'decididoEm': FieldValue.serverTimestamp(),
    });
  }

  /// Revogar vínculo (marca "revogado" nos dois lados)
  Future<void> revogarVinculo(String otherUid) async {
    final meVincRef = _db.collection('usuarios').doc(_me)
        .collection('vinculos').doc(otherUid);
    final otherVincRef = _db.collection('usuarios').doc(otherUid)
        .collection('vinculos').doc(_me);

    await _db.runTransaction((tx) async {
      final meSnap = await tx.get(meVincRef);
      final otherSnap = await tx.get(otherVincRef);
      if (!meSnap.exists || !otherSnap.exists) {
        throw Exception('Vínculo não encontrado.');
      }
      tx.update(meVincRef, {'status': 'revogado'});
      tx.update(otherVincRef, {'status': 'revogado'});
    });
  }

  /// Stream de vínculos do usuário corrente
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamVinculos() {
    return _db.collection('usuarios').doc(_me)
        .collection('vinculos')
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((s) => s.docs);
  }

  /// Solicitações recebidas (onde eu sou o "aprovador")
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamSolicitacoesPendentes() {
    final uid = _me;
    return _db.collection('solicitacoesVinculo')
        .where('status', isEqualTo: 'pendente')
        .where('pacienteId', isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs);
  }
}
