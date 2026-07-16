//supabase_config.dart

class SupabaseConfig {
  /// Supply at build time:
  ///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  ///               --dart-define=SUPABASE_ANON_KEY=your-key-here
  ///
  /// This key is designed to ship inside clients — Row Level Security, not key
  /// secrecy, is what protects the data. Never put the service_role key here.
  static const String url = String.fromEnvironment('SUPABASE_URL');

  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Supabase renamed this key: newer projects show a `sb_publishable_...`
  /// value where older ones show a JWT "anon key". They occupy the same slot,
  /// so either variable name works and neither project vintage needs special
  /// handling.
  static const String _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static String get publishableKey =>
      _publishableKey.isNotEmpty ? _publishableKey : _anonKey;

  /// When false the app falls back to on-device persistence so it still runs
  /// end to end. See [Backend.init].
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
