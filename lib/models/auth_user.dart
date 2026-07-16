//auth_user.dart

/// The signed-in account, independent of which backend produced it.
///
/// Screens depend on this rather than on Supabase's `User`, so swapping the
/// auth backend never reaches the UI layer.
class AuthUser {
  final String id;
  final String email;

  const AuthUser({required this.id, required this.email});

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}
