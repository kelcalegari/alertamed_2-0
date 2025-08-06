import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../routes/routes.dart';
import '../../../../shared/modals/custom_popup.dart';
import '../cadastro_texts.dart';



class RegisterService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  RegisterService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> criarConta({
    required BuildContext context,
    required String nome,
    required String email,
    required String senha,
    required String sexo,
    required String dataNascimentoTexto
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: senha,
      );

      final userId = cred.user!.uid;
      final dataNascimento = DateFormat('dd/MM/yyyy').parseStrict(dataNascimentoTexto);

      await _firestore.collection('usuarios').doc(userId).set({
        'nome': nome,
        'email': email,
        'sexo': sexo,
        'dataNascimento': dataNascimento,
      });

      Navigator.pushReplacementNamed(context, Routes.home);
    } on FirebaseAuthException catch (e) {
      String mensagemErro;
      switch (e.code) {
        case 'email-already-in-use':
          mensagemErro = RegisterTexts.emailInUse;
          break;
        case 'weak-password':
          mensagemErro = RegisterTexts.weakPassword;
          break;
        case 'network-request-failed':
          mensagemErro = RegisterTexts.networkRequestFailed;
          break;
        default:
          mensagemErro = '${RegisterTexts.createAccountError} ${e.code}';
      }
      CustomPopup.show(
        context: context,
        title: RegisterTexts.dialogTitle,
        message: mensagemErro,
      );

    } catch (e) {
      CustomPopup.show(
        context: context,
        title: RegisterTexts.dialogTitle,
        message: '${RegisterTexts.genericError} ${e.toString()}',
      );

    }
  }
}
