//validators.dart

class Validators {
  Validators._();

  /// Deliberately permissive. The address is verified by a confirmation mail,
  /// not by a regex — this only catches obvious typos before a round trip.
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Matches Supabase's own minimum, so the client and the server agree on what
  /// counts as too short.
  static const minPasswordLength = 6;

  static String? email(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(input)) return 'That does not look like an email';
    return null;
  }

  static String? password(String? value) {
    final input = value ?? '';
    if (input.isEmpty) return 'Enter a password';
    if (input.length < minPasswordLength) {
      return 'At least $minPasswordLength characters';
    }
    return null;
  }

  /// Used on sign-in, where any non-empty password should reach the server —
  /// an existing account may predate a rule change.
  static String? requiredPassword(String? value) =>
      (value ?? '').isEmpty ? 'Enter your password' : null;

  static String? Function(String?) confirmPassword(String Function() original) =>
      (value) => value != original() ? 'Passwords do not match' : null;
}
