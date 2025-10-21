// lib/presentation/pages/auth/login/service/login_service.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../providers/user_data_provider.dart';
import '../../../../routes/routes.dart';
import '../../../home/service/alterar_lembrete.dart';
import '../../../../shared/modals/custom_popup.dart';
import 'login_service.dart';

extension LoginComGoogle on LoginService {
  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      // 1) Fluxo Google
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // usuário cancelou

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 2) Firebase Auth
      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = cred.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'user-null', message: 'Falha na autenticação Google.');
      }

      // 3) Provisionar perfil no Firestore (idempotente)
      final db = FirebaseFirestore.instance;
      final docRef = db.collection('usuarios').doc(user.uid);
      final snap = await docRef.get();
      if (!snap.exists) {
        await db.runTransaction((tx) async {
          tx.set(docRef, {
            'nome': user.displayName ?? '',
            'email': user.email ?? '',
            'emailLower': (user.email ?? '').toLowerCase(),
            'emailVerified': true, // Google já vem verificado
            'status': 'active',
            'criadoEm': FieldValue.serverTimestamp(),
            'verificadoEm': FieldValue.serverTimestamp(),
            'provedor': 'google',
          }, SetOptions(merge: true));

          tx.set(db.collection('usuarios_publicos').doc(user.uid), {
            'displayName': user.displayName ?? '',
            'emailLower': (user.email ?? '').toLowerCase(),
            'criadoEm': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });
      }

      // 4) Pós-login (carregar provider, reagendar notificações)
      if (context.mounted) {
        await context.read<UsuarioProvider>().onLogin();
        await LembreteService().criarNotificacoesPosLogin(
          context: context,
          idUsuario: user.uid,
        );
        Navigator.pushReplacementNamed(context, Routes.home);
      }
    } on FirebaseAuthException catch (e) {
      // Tratamento de casos comuns
      String msg;
      switch (e.code) {
        case 'account-exists-with-different-credential':
        case 'credential-already-in-use':
          msg = 'Já existe uma conta com este e-mail. Faça login pelo método original (e-mail/senha).';
          break;
        case 'network-request-failed':
          msg = 'Sem conexão com a internet.';
          break;
        default:
          msg = 'Não foi possível entrar com o Google. (${e.code})';
      }
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: 'Login',
          message: msg,
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomPopup.show(
          context: context,
          title: 'Login',
          message: 'Falha ao entrar com o Google: $e',
        );
      }
    }
  }
}
