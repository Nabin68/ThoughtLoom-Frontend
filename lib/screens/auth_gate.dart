//auth_gate.dart

import 'package:flutter/material.dart';

import '../models/auth_user.dart';
import '../models/user_profile.dart';
import '../services/backend.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/primary_button.dart';
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

class _SignedInState extends State<_SignedIn> {
  late Future<UserProfile> _profile;

  @override
  void initState() {
    super.initState();
    _profile = Backend.data.ensureProfile(widget.user.id);
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
          // The single rule for what a signed-in user sees. A first
          // registration arrives with the flag false and gets the questions; a
          // returning user arrives with it true and never sees them again.
          // OnboardingScreen resumes from the first unanswered question, so an
          // interrupted run picks up rather than restarts.
          child: profile.onboardingCompleted
              ? const DashboardScreen()
              : const OnboardingScreen(),
        );
      },
    );
  }
}

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
            SizedBox(
              width: screenWidth * 0.1,
              height: screenWidth * 0.1,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return AppBackground(
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "We couldn't load your account",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: screenWidth * 0.06,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: screenHeight * 0.015),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: screenWidth * 0.038,
                  color: AppTheme.textLight,
                  height: 1.4,
                ),
              ),
              SizedBox(height: screenHeight * 0.04),
              PrimaryButton(label: 'Try again', onPressed: onRetry),
              SizedBox(height: screenHeight * 0.015),
              TextButton(
                // Sign-out is the escape hatch from a profile that will not
                // load; if it throws too there is nothing useful left to say, so
                // swallow rather than let it reach the zone unhandled.
                onPressed: () => Backend.auth.signOut().catchError((_) {}),
                child: Text(
                  'Sign out',
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    color: AppTheme.textLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
