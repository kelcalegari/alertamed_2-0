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

  /// Cria a conta, envia e-mail de verificação e redireciona para a tela de verificação.
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
      final dataNascDate = DateFormat('dd/MM/yyyy')
          .parseStrict(dataNascimentoTexto.trim());
      final dataNascTs = Timestamp.fromDate(dataNascDate);

      // 3) Escrever no Firestore (status pendente e emailVerified=false)
      final batch = _firestore.batch();

      final usuariosRef = _firestore.collection('usuarios').doc(userId);
      batch.set(usuariosRef, {
        'nome': nome.trim(),
        'email': email.trim(),
        'emailLower': emailLower,
        'sexo': sexo.trim(),
        'dataNascimento': dataNascTs,
        'emailVerified': false,
        'status': 'pending_verification',
        'criadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final publicRef = _firestore.collection('usuarios_publicos').doc(userId);
      batch.set(publicRef, {
        'displayName': nome.trim(),
        'emailLower': emailLower,
        'criadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      // 4) Verificação de e-mail
      if (enviarEmailVerificacao && !user.emailVerified) {
        await user.sendEmailVerification();
      }

      // 5) NÃO libera a home ainda. Leva para a tela/portão de verificação.
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, Routes.verifyEmail);
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

  /// Reenvia o e-mail de verificação para o usuário atual.
  Future<void> reenviarEmailVerificacao(BuildContext context) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Usuário não autenticado.');
      await user.sendEmailVerification();
      CustomPopup.show(
        context: context,
        title: RegisterTexts.dialogTitle,
        message: 'E-mail de verificação reenviado. Verifique sua caixa de entrada.',
      );
    } catch (e) {
      CustomPopup.show(
        context: context,
        title: RegisterTexts.dialogTitle,
        message: 'Falha ao reenviar: $e',
      );
    }
  }

  /// Recarrega o usuário e força refresh do token (para propagar email_verified).
  Future<User?> checarVerificacaoAtualizarToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed != null) {
      // Garante que o claim email_verified seja atualizado nas regras
      await refreshed.getIdToken(true);
    }
    return _auth.currentUser;
  }

  /// Chame isso após detectar que o e-mail foi verificado (na tela "Já verifiquei").
  /// Atualiza o Firestore e libera a navegação para a Home + carrega o provider.
  Future<void> finalizarOnboardingPosVerificacao(BuildContext context) async {
    try {
      final user = await checarVerificacaoAtualizarToken();
      if (user == null) throw Exception('Usuário não autenticado.');
      if (!user.emailVerified) {
        CustomPopup.show(
          context: context,
          title: RegisterTexts.dialogTitle,
          message:
          'Ainda não detectei a verificação do e-mail. Aguarde alguns segundos e tente novamente.',
        );
        return;
      }

      // Marca verificado no Firestore
      await _firestore.collection('usuarios').doc(user.uid).set({
        'emailVerified': true,
        'status': 'active',
        'verificadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        // Agora sim carregue dados e vá para a Home
        await context.read<UsuarioProvider>().fetchData();
        Navigator.pushNamedAndRemoveUntil(context, Routes.home, (_) => false);
      }
    } catch (e) {
      CustomPopup.show(
        context: context,
        title: RegisterTexts.dialogTitle,
        message: 'Erro ao finalizar verificação: $e',
      );
    }
  }
}
