import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> salvarSintomas({
  required String nome,
  required String intensidade,
  required String observacoes,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Usuário não autenticado');

  final idUsuario = user.uid;
  final sintomasRef = FirebaseFirestore.instance
      .collection('usuarios')
      .doc(idUsuario)
      .collection('sintomas')
      .doc(); // id automático

  await sintomasRef.set({
    'nome': nome,
    'intensidade': intensidade.toLowerCase(),
    'observacoes': observacoes,
    'dataHora': Timestamp.now(),
    // campos auxiliares
    'ultimaEdicao': null,               // Timestamp? (nulo até 1ª edição)
    'historicoEdicoes': <Map<String, dynamic>>[], // lista de logs
  });
}

/// Retorna true se ainda está dentro da janela de 15 minutos.
Future<bool> podeEditarSintoma(String sintomaId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Usuário não autenticado');

  final doc = await FirebaseFirestore.instance
      .collection('usuarios')
      .doc(user.uid)
      .collection('sintomas')
      .doc(sintomaId)
      .get();

  if (!doc.exists) return false;

  final data = doc.data()!;
  final Timestamp criadoEm = data['dataHora'] as Timestamp;
  final limite = criadoEm.toDate().add(const Duration(minutes: 15));
  return DateTime.now().isBefore(limite);
}

/// Edita campos do sintoma apenas se estiver dentro de 15 minutos do registro.
/// Passa só os campos que quer alterar; os demais ficam como estão.
Future<void> editarSintoma({
  required String sintomaId,
  String? nome,
  String? intensidade,
  String? observacoes,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Usuário não autenticado');

  // 1) Carrega doc atual
  final docRef = FirebaseFirestore.instance
      .collection('usuarios')
      .doc(user.uid)
      .collection('sintomas')
      .doc(sintomaId);

  final snap = await docRef.get();
  if (!snap.exists) {
    throw Exception('Sintoma não encontrado');
  }

  final atual = snap.data()!;
  final criadoEm = (atual['dataHora'] as Timestamp).toDate();
  final limite = criadoEm.add(const Duration(minutes: 15));
  if (DateTime.now().isAfter(limite)) {
    throw Exception('Edição não permitida: prazo de 15 minutos expirou');
  }

  // 2) Monta atualização somente com o que veio
  final updates = <String, dynamic>{};
  if (nome != null) updates['nome'] = nome;
  if (intensidade != null) updates['intensidade'] = intensidade.toLowerCase();
  if (observacoes != null) updates['observacoes'] = observacoes;

  if (updates.isEmpty) {
    return; // nada para editar
  }

  // 3) Opcional: registra um pequeno log da edição (antes/depois)
  final logItem = {
    'em': Timestamp.now(),
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

  updates['ultimaEdicao'] = Timestamp.now();
  updates['historicoEdicoes'] = FieldValue.arrayUnion([logItem]);

  // 4) Atualiza
  await docRef.update(updates);
}
