//local_auth_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../models/auth_user.dart';
import '../auth_service.dart';
import 'local_store.dart';

/// On-device stand-in for Supabase auth, used when no credentials are
/// configured so the app still runs end to end.
///
/// Accounts live only on this device. Passwords are salted and hashed rather
/// than stored in the clear, but SHA-256 is a digest, not a password KDF — real
/// authentication is Supabase's job, and this exists so a developer without
/// keys can still click through the app.
class LocalAuthService extends AuthService {
  final LocalStore _store;
  final _controller = StreamController<AuthUser?>.broadcast();

  AuthUser? _currentUser;

  LocalAuthService(this._store) {
    final userId = _store.readSession();
    if (userId != null) {
      final record = _findById(userId);
      if (record != null) {
        _currentUser = AuthUser(id: userId, email: record['email'] as String);
      }
    }
  }

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  /// Always null: there is no server to prove anything to, and no real token to
  /// prove it with. The AI flow needs Supabase, and refuses up front rather
  /// than sending a forged one — see [Backend.usingSupabase].
  @override
  Future<String?> accessToken() async => null;

  Map<String, dynamic>? _findById(String id) {
    for (final entry in _store.readTable(LocalStore.usersKey).values) {
      final record = Map<String, dynamic>.from(entry as Map);
      if (record['id'] == id) return record;
    }
    return null;
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  String _newSalt() {
    final rnd = Random.secure();
    return List<int>.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _setUser(AuthUser? user) async {
    _currentUser = user;
    await _store.writeSession(user?.id);
    _controller.add(user);
  }

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final normalized = email.trim().toLowerCase();
    final users = _store.readTable(LocalStore.usersKey);

    if (users.containsKey(normalized)) {
      throw const AuthFailure('An account with that email already exists.');
    }
    if (password.length < 6) {
      throw const AuthFailure('Password must be at least 6 characters.');
    }

    final salt = _newSalt();
    final id = newUuidV4();
    users[normalized] = {
      'id': id,
      'email': normalized,
      'salt': salt,
      'hash': _hash(password, salt),
      'display_name': displayName?.trim(),
    };
    await _store.writeTable(LocalStore.usersKey, users);

    final user = AuthUser(id: id, email: normalized);
    await _setUser(user);
    // Nothing to confirm without a mail server; sign-up signs you straight in.
    return SignUpResult(user: user, needsEmailConfirmation: false);
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    final record = _store.readTable(LocalStore.usersKey)[normalized];

    if (record == null) {
      throw const AuthFailure('That email and password do not match.');
    }

    final stored = Map<String, dynamic>.from(record as Map);
    if (_hash(password, stored['salt'] as String) != stored['hash']) {
      throw const AuthFailure('That email and password do not match.');
    }

    final user = AuthUser(id: stored['id'] as String, email: normalized);
    await _setUser(user);
    return user;
  }

  @override
  Future<void> signOut() => _setUser(null);
}
