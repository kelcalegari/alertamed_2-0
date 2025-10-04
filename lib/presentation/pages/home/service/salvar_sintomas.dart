import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../providers/user_data_provider.dart';

/// ===== Helpers base (timeout + net error) =====
bool _isNetworkError(Object e) {
  if (e is FirebaseException) {
    return e.code == 'unavailable' ||
        e.code == 'network-request-failed' ||
        e.code == 'deadline-exceeded';
  }
  return false;
}

Future<bool> _tryWrite(Future<void> Function() op, {Duration timeout = const Duration(seconds: 2)}) async {
  try {
    await op().timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  } catch (e) {
    if (_isNetworkError(e)) return false;
    rethrow;
  }
}

/// ===== Regras de alvo =====
/// Somente o usuário local pode registrar/editar sintomas.
/// Se vier provider em contexto "paciente" (caregiver), bloqueia.
String _resolveTargetUid(UsuarioProvider? p, User? authUser) {
  if (authUser == null) throw Exception('Usuário não autenticado');
  if (p != null && !p.isContextoSouEu) {
    throw Exception('Apenas o usuário local pode registrar sintomas.');
  }
  return authUser.uid;
}

/// Metadados simples (sempre paciente/local)
Map<String, dynamic> _updatedBy(User? authUser) {
  final uid = authUser?.uid ?? '';
  return {'uid': uid, 'role': 'patient'};
}

/// ===== SALVAR =====
Future<void> salvarSintomas({
  required String nome,
  required String intensidade,
  required String observacoes,
  UsuarioProvider? usuarioProvider,
  Duration writeTimeout = const Duration(seconds: 2),
}) async {
  final authUser = FirebaseAuth.instance.currentUser;
  final idUsuario = _resolveTargetUid(usuarioProvider, authUser);

  final sintomasRef = FirebaseFirestore.instance
      .collection('usuarios')
      .doc(idUsuario)
      .collection('sintomas')
      .doc(); // id “online”

  final agoraLocal = Timestamp.now();

  // Mantém 'dataHoraLocal' para a janela offline; 'dataHora' como serverTimestamp.
  final baseDoc = <String, dynamic>{
    'nome': nome,
    'intensidade': intensidade.toLowerCase(),
    'observacoes': observacoes,
    'dataHora': FieldValue.serverTimestamp(),
    'dataHoraLocal': agoraLocal,
    'ultimaEdicao': null,
    'historicoEdicoes': <Map<String, dynamic>>[],
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': _updatedBy(authUser),
    'status': 'ativo',
  };

  final wroteOnline = await _tryWrite(
        () async => await sintomasRef.set(baseDoc),
    timeout: writeTimeout,
  );

  if (!wroteOnline) {
    // Offline: garante 'dataHora' já preenchido para a janela
    final localDoc = Map<String, dynamic>.from(baseDoc)
      ..['dataHora'] = agoraLocal
      ..['__localId'] = 'local_${sintomasRef.id}';

    // Coloca no cache (merge) sem travar
    unawaited(sintomasRef.set(localDoc, SetOptions(merge: true)));

    // Atualiza provider para refletir na UI (se foi passado)
    if (usuarioProvider != null) {
      usuarioProvider.sintomas.add(localDoc);
      usuarioProvider.notifyListeners();
    }
  }
}

/// ===== PODE EDITAR =====
Future<bool> podeEditarSintoma(String sintomaId, {UsuarioProvider? usuarioProvider}) async {
  final authUser = FirebaseAuth.instance.currentUser;
  final idUsuario = _resolveTargetUid(usuarioProvider, authUser);

  final snap = await FirebaseFirestore.instance
      .collection('usuarios').doc(idUsuario)
      .collection('sintomas').doc(sintomaId)
      .get(const GetOptions(source: Source.serverAndCache));

  if (!snap.exists) return false;
  final data = snap.data()!;
  final Timestamp? criadoServer = data['dataHora'] as Timestamp?;
  final Timestamp? criadoLocal  = data['dataHoraLocal'] as Timestamp?;

  final criadoEm = (criadoServer ?? criadoLocal)?.toDate();
  if (criadoEm == null) return false;

  final limite = criadoEm.add(const Duration(minutes: 15));
  return DateTime.now().isBefore(limite);
}

/// ===== EDITAR =====
Future<void> editarSintoma({
  required String sintomaId,
  String? nome,
  String? intensidade,
  String? observacoes,
  UsuarioProvider? usuarioProvider,
  Duration writeTimeout = const Duration(seconds: 2),
}) async {
  final authUser = FirebaseAuth.instance.currentUser;
  final idUsuario = _resolveTargetUid(usuarioProvider, authUser);

  final docRef = FirebaseFirestore.instance
      .collection('usuarios').doc(idUsuario)
      .collection('sintomas').doc(sintomaId);

  final snap = await docRef.get(const GetOptions(source: Source.serverAndCache));
  if (!snap.exists) throw Exception('Sintoma não encontrado');

  final atual = snap.data()!;
  final criadoServer = atual['dataHora'] as Timestamp?;
  final criadoLocal  = atual['dataHoraLocal'] as Timestamp?;
  final criadoEm = (criadoServer ?? criadoLocal)?.toDate();
  if (criadoEm == null) throw Exception('Registro inválido (sem dataHora)');

  final limite = criadoEm.add(const Duration(minutes: 15));
  if (DateTime.now().isAfter(limite)) {
    throw Exception('Edição não permitida: prazo de 15 minutos expirou');
  }

  final updates = <String, dynamic>{};
  if (nome != null) updates['nome'] = nome;
  if (intensidade != null) updates['intensidade'] = intensidade.toLowerCase();
  if (observacoes != null) updates['observacoes'] = observacoes;
  if (updates.isEmpty) return;

  // ⚠️ AQUI ESTAVA O PROBLEMA: NÃO usar FieldValue.serverTimestamp() DENTRO do arrayUnion
  final logItem = {
    'em': Timestamp.now(), // <- use Timestamp.now() no item do log
    'antes': {
      'nome': atual['nome'],
      'intensidade': atual['intensidade'],
      'observacoes': atual['observacoes'],
    },
    'depois': {
      'nome': updates['nome'] ?? atual['nome'],
      'intensidade': updates['intensidade'] ?? atual['intensidade'],
      'observacoes': updates['observacoes'] ?? atual['observacoes'],
    },
  };

  updates['ultimaEdicao'] = FieldValue.serverTimestamp(); // ok (campo de topo)
  updates['updatedAt'] = FieldValue.serverTimestamp();    // ok (campo de topo)
  updates['updatedBy'] = _updatedBy(authUser);
  updates['historicoEdicoes'] = FieldValue.arrayUnion([logItem]);

  final wroteOnline = await _tryWrite(
        () async => await docRef.update(updates),
    timeout: writeTimeout,
  );

  if (!wroteOnline) {
    // Fallback local (também SEM sentinel aninhado)
    final local = Map<String, dynamic>.from(updates)
      ..['ultimaEdicao'] = Timestamp.now()
      ..['historicoEdicoes'] = FieldValue.arrayUnion([
        {
          'em': Timestamp.now(),
          'antes': logItem['antes'],
          'depois': logItem['depois'],
        }
      ]);

    unawaited(docRef.set(local, SetOptions(merge: true)));

    if (usuarioProvider != null) {
      final lista = usuarioProvider.sintomas;
      final idx = lista.indexWhere((e) => (e['id'] ?? e['__localId'] ?? '') == sintomaId);
      if (idx >= 0) {
        final m = Map<String, dynamic>.from(lista[idx] as Map);
        m.addAll({
          'nome': updates['nome'] ?? m['nome'],
          'intensidade': updates['intensidade'] ?? m['intensidade'],
          'observacoes': updates['observacoes'] ?? m['observacoes'],
          'ultimaEdicao': Timestamp.now(),
        });
        lista[idx] = m;
      }
      usuarioProvider.notifyListeners();
    }
  }
}
