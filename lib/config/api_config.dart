//api_config.dart

class ApiConfig {
  /// Override per environment at build time:
  ///   flutter run --dart-define=API_BASE_URL=http://localhost:8000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://thoughtloom-backend-6wmm.onrender.com',
  );

  static Uri get analyzeUrl => Uri.parse('$baseUrl/api/analyze');

  static Uri get adaptiveQuestionUrl => Uri.parse('$baseUrl/api/adaptive-question');
  static Uri get recommendationUrl => Uri.parse('$baseUrl/api/recommendation');
  static Uri get followUpUrl => Uri.parse('$baseUrl/api/follow-up');
  static Uri get completeChatUrl => Uri.parse('$baseUrl/api/complete-chat');

  /// The backend sleeps on Render's free tier, so a cold start plus the LLM call
  /// can legitimately take a minute.
  static const Duration requestTimeout = Duration(seconds: 90);

  /// The recommendation gets longer: a search decision, up to three web
  /// lookups, and a much longer generation — any of which can land behind the
  /// same cold start.
  static const Duration recommendationTimeout = Duration(seconds: 150);
}
