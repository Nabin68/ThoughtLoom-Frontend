//user_profile.dart

/// One row per account. Created automatically at sign-up (empty), then filled
/// in by onboarding.
class UserProfile {
  final String id;
  final String? displayName;
  final String? ageRange;
  final String? occupation;
  final String? location;

  /// Free-form onboarding answers. Kept loose so the intake questions can
  /// change without a migration.
  final Map<String, dynamic> onboardingAnswers;
  final bool onboardingCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    this.displayName,
    this.ageRange,
    this.occupation,
    this.location,
    this.onboardingAnswers = const {},
    this.onboardingCompleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.empty(String id) {
    final now = DateTime.now().toUtc();
    return UserProfile(id: id, createdAt: now, updatedAt: now);
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        displayName: json['display_name'] as String?,
        ageRange: json['age_range'] as String?,
        occupation: json['occupation'] as String?,
        location: json['location'] as String?,
        onboardingAnswers:
            Map<String, dynamic>.from(json['onboarding_answers'] as Map? ?? {}),
        onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  /// Only the client-writable columns. `created_at` and `updated_at` are the
  /// database's to set.
  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'age_range': ageRange,
        'occupation': occupation,
        'location': location,
        'onboarding_answers': onboardingAnswers,
        'onboarding_completed': onboardingCompleted,
      };

  UserProfile copyWith({
    String? displayName,
    String? ageRange,
    String? occupation,
    String? location,
    Map<String, dynamic>? onboardingAnswers,
    bool? onboardingCompleted,
  }) =>
      UserProfile(
        id: id,
        displayName: displayName ?? this.displayName,
        ageRange: ageRange ?? this.ageRange,
        occupation: occupation ?? this.occupation,
        location: location ?? this.location,
        onboardingAnswers: onboardingAnswers ?? this.onboardingAnswers,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
}
