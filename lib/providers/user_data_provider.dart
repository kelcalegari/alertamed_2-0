import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UsuarioProvider extends ChangeNotifier {
  Map<String, dynamic> dadosUsuario = {};
  List<Map<String, dynamic>> sintomas = [];
  List<Map<String, dynamic>> lembretes = [];
  Map<String, dynamic> tratamentosMap = {};

  Map<String, dynamic> estoqueMap = {};
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
      _loadSintomas(usuarioRef),
      _loadLembretes(usuarioRef),
      _loadTratamentos(usuarioRef),
      _loadEstoque(usuarioRef),
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

  Future<void> _loadSintomas(DocumentReference usuarioRef) async {
    try {
      final snapshot = await usuarioRef.collection('sintomas').get();
      sintomas = snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Erro ao carregar sintomas: $e');
      sintomas = [];
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
        for (var tratamento in tratamentos)
          tratamento['idTratamento']: tratamento,
      };
    } catch (e) {
      debugPrint('Erro ao carregar tratamentoss: $e');
      tratamentosMap = {};
    }
  }

  Future<void> _loadEstoque(DocumentReference usuarioRef) async {
    try {
      final snapshot = await usuarioRef.collection('estoque').get();
      estoqueMap = {
        for (var doc in snapshot.docs) doc.id: doc.data(),
      };
    } catch (e) {
      debugPrint('Erro ao carregar estoque: $e');
      estoqueMap = {};
    }
  }
}
