import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../../providers/user_data_provider.dart';
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
    required String dataNascimentoTexto,
    bool enviarEmailVerificacao = true,
  }) async {
    try {
      // 1) Criar usuário no Auth
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: senha,
      );
      final user = cred.user!;
      await user.updateDisplayName(nome.trim());

      // 2) Normalizações
      final userId = user.uid;
      final emailLower = email.trim().toLowerCase();
      final dataNascDate = DateFormat('dd/MM/yyyy').parseStrict(dataNascimentoTexto.trim());
      final dataNascTs = Timestamp.fromDate(dataNascDate);

      // 3) Escrever no Firestore (batch atômico)
      final batch = _firestore.batch();

      final usuariosRef = _firestore.collection('usuarios').doc(userId);
      batch.set(usuariosRef, {
        'nome': nome.trim(),
        'email': email.trim(),
        'sexo': sexo.trim(),
        'dataNascimento': dataNascTs, // Timestamp
        'criadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final publicRef = _firestore.collection('usuarios_publicos').doc(userId);
      batch.set(publicRef, {
        'displayName': nome.trim(),
        'emailLower': emailLower,
        'criadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      // 4) (Opcional) Verificação de e-mail
      if (enviarEmailVerificacao && !user.emailVerified) {
        await user.sendEmailVerification();
      }

      // 5) Navega para home
      if (context.mounted) {
        context.read<UsuarioProvider>().fetchData();
        Navigator.pushReplacementNamed(context, Routes.home);
      }
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
        case 'invalid-email':
          mensagemErro = RegisterTexts.emailInvalid;
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
