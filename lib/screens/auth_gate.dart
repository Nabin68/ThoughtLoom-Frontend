//auth_gate.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/onboarding_questions.dart';
import '../models/auth_user.dart';
import '../models/user_profile.dart';
import '../services/ai_service.dart';
import '../services/backend.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_loader.dart';
import 'dashboard_screen.dart';
import 'landing_screen.dart';
import 'onboarding_screen.dart';

/// Decides what a launch shows: the signed-out landing page, or the app.
///
/// Sits at the root of the navigator, so pushed routes stack on top of it and
/// `popUntil((r) => r.isFirst)` after sign-in lands back here.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: Backend.auth.authStateChanges,
      // Backend.init() has already restored any session, so the first frame is
      // correct and a signed-in user never sees the landing page flash past.
      initialData: Backend.auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) return const LandingScreen();
        return _SignedIn(user: user);
      },
    );
  }
}

/// Resolves the profile before showing the app.
///
/// Supabase provisions it by trigger at sign-up, but reading it through
/// [DataService.ensureProfile] means the app is also correct against a database
/// where that trigger was never applied.
class _SignedIn extends StatefulWidget {
  final AuthUser user;

  const _SignedIn({required this.user});

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> with WidgetsBindingObserver {
  late Future<UserProfile> _profile;

  @override
  void initState() {
    super.initState();
    _profile = Backend.data.ensureProfile(widget.user.id);
    WidgetsBinding.instance.addObserver(this);
    _warmUpBackend();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back to the foreground is the second moment worth a warm-up.
  ///
  /// Render sleeps a free service fifteen minutes after its last request, and
  /// nothing about the app being open keeps it awake. So someone who signs in,
  /// waits out the cold start, then leaves the app sitting for twenty minutes
  /// and comes back to start a chat meets a *sleeping* server — while
  /// [backendWarm] still says true, which is worse than not knowing: the wait
  /// then reads as "thinking" rather than as a server starting up.
  ///
  /// [_warmUpBackend] decides whether it is actually worth a ping, so this can
  /// fire on every resume without turning an app-switch into a network call.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _warmUpBackend();
  }

  /// Fired when someone is found signed in — a fresh login and a launch into a
  /// restored session both land here — and again on every foreground resume.
  /// See [AiService.warmUp].
  ///
  /// Skipped on the on-device backend: there is no Render service behind it to
  /// wake, so the ping would just be a network call that always fails.
  ///
  /// [backendMayHaveSlept] is what makes this safe to call as often as it is.
  /// At sign-in nothing has answered yet, so it is always true; on a resume it
  /// is true only if the backend has been quiet long enough to have been put
  /// back to sleep.
  void _warmUpBackend() {
    if (!Backend.usingSupabase) return;
    if (!backendMayHaveSlept()) return;
    unawaited(Backend.ai.warmUp());
  }

  @override
  void didUpdateWidget(_SignedIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Signing out and back in as someone else must not keep the old profile.
    if (oldWidget.user.id != widget.user.id) {
      _profile = Backend.data.ensureProfile(widget.user.id);
    }
  }

  Future<void> _reload() async {
    final next = Backend.data.ensureProfile(widget.user.id);
    // Block body, not an arrow: `() => _profile = next` evaluates to the
    // assigned Future, and setState rejects a callback that returns one.
    setState(() {
      _profile = next;
    });
    // The FutureBuilder below renders any failure. Awaiting the raw future here
    // as well would give the same error a second, unhandled path into the zone
    // every time a retry fails; callers only need to know the attempt finished.
    await next.then<void>((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        if (snapshot.hasError) {
          return _ProfileError(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }

        final profile = snapshot.data!;

        return SessionScope(
          user: widget.user,
          profile: profile,
          reload: _reload,
          child: _needsOnboarding(profile)
              ? const OnboardingScreen()
              : const DashboardScreen(),
        );
      },
    );
  }
}

/// The single rule for what a signed-in user sees.
///
/// It used to be `profile.onboardingCompleted` alone, and the flag short-circuited
/// before the question list was ever consulted — so adding a question to
/// [onboardingQuestions] reached new users and nobody else, forever. Everyone
/// who had already signed up simply never got asked, and the feature that needed
/// the answer had to cope with it being permanently absent. The build notes said
/// as much: "a migration would have to clear the flag."
///
/// This is that migration, without the migration. [firstUnansweredIndex] tests
/// for a key's *presence*, and a skipped question is stored as an explicit null —
/// so a returning user whose profile is missing only the two questions added
/// after they signed up is asked exactly those two and then handed straight back
/// to the dashboard. Someone who has answered everything never sees the screen,
/// which is the rule that mattered all along.
bool _needsOnboarding(UserProfile profile) =>
    !profile.onboardingCompleted ||
    firstUnansweredIndex(profile.onboardingAnswers) < onboardingQuestions.length;

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return AppBackground(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: screenWidth * 0.25,
              height: screenWidth * 0.25,
              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
            ),
            SizedBox(height: screenWidth * 0.1),
            AppLoader(size: (screenWidth * 0.1).clamp(30.0, 46.0)),
          ],
        ),
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ProfileError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: AppTheme.s6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "We couldn't load your account",
                textAlign: TextAlign.center,
                style: AppTheme.title(context),
              ),
              SizedBox(height: AppTheme.s3),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTheme.secondary(context),
              ),
              SizedBox(height: AppTheme.s6),
              AppButton(label: 'Try again', onPressed: onRetry),
              SizedBox(height: AppTheme.s2),
              AppButton.quiet(
                label: 'Sign out',
                // Sign-out is the escape hatch from a profile that will not
                // load; if it throws too there is nothing useful left to say, so
                // swallow rather than let it reach the zone unhandled.
                onPressed: () => Backend.auth.signOut().catchError((_) {}),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
