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
      .doc(); // cria id automático

  await sintomasRef.set({
    'nome': nome,
    'intensidade': intensidade.toLowerCase(),
    'observacoes': observacoes,
    'dataHora': Timestamp.now(),
  });
}
