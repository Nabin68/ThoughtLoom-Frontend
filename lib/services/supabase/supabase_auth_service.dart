//supabase_auth_service.dart

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../models/auth_user.dart';
import '../auth_service.dart';

class SupabaseAuthService extends AuthService {
  final sb.SupabaseClient _client;

  SupabaseAuthService(this._client);

  AuthUser? _toAuthUser(sb.User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email ?? '');

  @override
  Stream<AuthUser?> get authStateChanges =>
      _client.auth.onAuthStateChange.map((e) => _toAuthUser(e.session?.user));

  @override
  AuthUser? get currentUser => _toAuthUser(_client.auth.currentUser);

  @override
  Future<String?> accessToken() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;

    // A recommendation call can outlive a token that was nearly expired when it
    // started — Render's cold start alone can eat a minute. Refreshing on the
    // near-expiry margin costs one round trip and avoids a 401 on the far side
    // of a ninety-second wait, which the user would experience as the app
    // losing their conversation.
    if (session.isExpired ||
        (session.expiresAt != null &&
            DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)
                    .difference(DateTime.now())
                    .inSeconds <
                120)) {
      try {
        final refreshed = await _client.auth.refreshSession();
        return refreshed.session?.accessToken ?? session.accessToken;
      } on sb.AuthException {
        // Let the call go out with what we have. If it really is dead the API
        // says 401 and the screen offers a retry, which is a better place to
        // find out than a thrown exception here.
        return session.accessToken;
      }
    }
    return session.accessToken;
  }

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final name = displayName?.trim();
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        // Read back by the handle_new_user trigger to seed user_profiles.
        data: (name == null || name.isEmpty) ? null : {'display_name': name},
      );

      final user = _toAuthUser(res.user);
      if (user == null) {
        throw const AuthFailure('Could not create your account. Please try again.');
      }
      return SignUpResult(
        user: user,
        needsEmailConfirmation: res.session == null,
      );
    } on sb.AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = _toAuthUser(res.user);
      if (user == null) {
        throw const AuthFailure('Could not sign you in. Please try again.');
      }
      return user;
    } on sb.AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on sb.AuthException catch (e) {
      throw AuthFailure(_readable(e));
    }
  }

  /// Supabase phrases errors for developers. These are the ones a user can
  /// actually act on; anything else passes through as-is.
  String _readable(sb.AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'That email and password do not match.';
    }
    if (message.contains('email not confirmed')) {
      return 'Please confirm your email first — check your inbox.';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'An account with that email already exists.';
    }
    if (message.contains('password should be')) {
      return 'Password must be at least 6 characters.';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return e.message;
  }
}
