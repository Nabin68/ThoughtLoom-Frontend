//session.dart

import 'package:flutter/widgets.dart';

import '../models/auth_user.dart';
import '../models/user_profile.dart';

/// The signed-in user and their profile, readable from anywhere below
/// [AuthGate].
///
/// Screens that need to know who is signed in read this rather than hitting the
/// backend again:
///
///   final session = SessionScope.of(context);
///   if (!session.profile.onboardingCompleted) { ... }
///
/// Call [reload] after writing to the profile so the tree picks the change up.
class SessionScope extends InheritedWidget {
  final AuthUser user;
  final UserProfile profile;
  final Future<void> Function() reload;

  const SessionScope({
    super.key,
    required this.user,
    required this.profile,
    required this.reload,
    required super.child,
  });

  static SessionScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope above this widget. Is it under AuthGate?');
    return scope!;
  }

  /// Null above [AuthGate], or when signed out.
  static SessionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>();

  @override
  bool updateShouldNotify(SessionScope oldWidget) =>
      oldWidget.user != user ||
      oldWidget.profile.updatedAt != profile.updatedAt ||
      oldWidget.profile.onboardingCompleted != profile.onboardingCompleted;
}
