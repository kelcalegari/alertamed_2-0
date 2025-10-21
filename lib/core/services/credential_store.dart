import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialStore {
  static const _kEmail = 'cred_email_v1';
  static const _kPass  = 'cred_pass_v1';

  final _storage = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked,
    ),
  );

  Future<void> save({required String email, required String password}) async {
    await _storage.write(key: _kEmail, value: email.trim());
    await _storage.write(key: _kPass,  value: password);
  }

  Future<({String? email, String? password})> read() async {
    final e = await _storage.read(key: _kEmail);
    final p = await _storage.read(key: _kPass);
    return (email: e, password: p);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kEmail);
    await _storage.delete(key: _kPass);
  }
}
