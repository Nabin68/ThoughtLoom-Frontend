//api_config.dart

class ApiConfig {
  /// Override per environment at build time:
  ///   flutter run --dart-define=API_BASE_URL=http://localhost:8000
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://thoughtloom-backend-6wmm.onrender.com',
  );

  static Uri get healthUrl => Uri.parse('$baseUrl/health');

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

  /// How long to keep trying to wake the backend after sign-in.
  ///
  /// Generous because it costs nothing: this runs in the background while the
  /// user answers the setup questions, and a cold start of 30-50 seconds is
  /// normal on the free tier. Giving up at the first timeout — which is what a
  /// single 15-second ping did — meant the user paid the rest of that boot
  /// themselves at the first question.
  static const Duration warmUpBudget = Duration(minutes: 2);

  /// One attempt. Shorter than the budget on purpose: a request left hanging
  /// on a dead socket learns nothing, where a fresh one at least re-triggers
  /// the wake-up.
  static const Duration warmUpAttemptTimeout = Duration(seconds: 25);

  /// How long "the backend answered us" stays worth believing.
  ///
  /// Render sleeps a free service fifteen minutes after its last request, so
  /// what makes our knowledge stale is not how long the app was backgrounded —
  /// it is how long since the backend last said anything. Ten minutes keeps a
  /// safe margin under the fifteen.
  ///
  /// This one number is also what stops a re-warm on every app-switch flicker:
  /// a three-second trip to another app cannot make the last reply ten minutes
  /// old, so nothing fires. Twenty minutes sat on the dashboard can, and does.
  static const Duration warmthGoesStaleAfter = Duration(minutes: 10);
}
