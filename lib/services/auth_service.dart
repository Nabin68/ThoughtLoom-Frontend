//auth_service.dart

import '../models/auth_user.dart';

/// A failure worth showing the user. [message] is already user-facing.
class AuthFailure implements Exception {
  final String message;

  const AuthFailure(this.message);

  @override
  String toString() => message;
}

/// Outcome of a successful registration.
///
/// With Supabase's "Confirm email" setting on, sign-up creates the account but
/// returns no session — the user is registered and *not* signed in. That is a
/// success, not an error, so it is reported rather than thrown.
class SignUpResult {
  final AuthUser user;
  final bool needsEmailConfirmation;

  const SignUpResult({required this.user, required this.needsEmailConfirmation});
}

/// Email + password authentication.
///
/// The app depends only on this. [SupabaseAuthService] and [LocalAuthService]
/// are interchangeable behind it, and any future provider only has to satisfy
/// these members.
abstract class AuthService {
  /// Emits on sign-in and sign-out. Broadcast, so any number of listeners can
  /// subscribe; listening late never misses state because [currentUser] is
  /// readable synchronously.
  Stream<AuthUser?> get authStateChanges;

  /// The session restored at startup, or null. Safe to read on the first frame
  /// — [Backend.init] finishes restoring before the app builds.
  AuthUser? get currentUser;

  bool get isSignedIn => currentUser != null;

  /// The bearer token for calls to our own API, refreshed if it is about to
  /// expire. Null when signed out, and always null on the on-device backend —
  /// which has no server to prove anything to.
  ///
  /// The API uses this to check a chat belongs to the caller before it touches
  /// the database with a key that bypasses Row Level Security. See
  /// `thoughtloom_backend/app/core/auth.py`.
  Future<String?> accessToken();

  Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthUser> signIn({required String email, required String password});

  Future<void> signOut();
}
