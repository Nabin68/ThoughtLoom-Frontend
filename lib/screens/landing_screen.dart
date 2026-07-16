//landing_screen.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// The signed-out front door.
///
/// ### Signing in is the primary action now
///
/// It used to offer exactly one button — "Start Thinking Clearly" — and it went
/// to the register screen. So every returning user whose session had expired was
/// shown a sign-up form and had to work out that the way back into their own
/// account was a link at the bottom of it. Registering is the thing you do once;
/// signing in is the thing you do forever after, and it should be the button.
///
/// Creating an account is still one tap, and still says what it is.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  bool _showContent = false;

  @override
  void initState() {
    super.initState();
    // Lets the logo land before the words arrive under it.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _showContent = true);
    });
  }

  void _go(Widget screen) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => screen),
      );

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.s6),
        child: Column(
          children: [
            const Spacer(flex: 3),
            AnimatedSlide(
              offset: _showContent ? const Offset(0, -0.1) : Offset.zero,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              child: Image.asset('assets/logo.png', height: 92),
            ),
            SizedBox(height: AppTheme.s5),
            AnimatedOpacity(
              opacity: _showContent ? 1 : 0,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              child: Column(
                children: [
                  Text(
                    'ThoughtLoom',
                    style: AppTheme.display(context).copyWith(fontSize: 32),
                  ),
                  SizedBox(height: AppTheme.s2),
                  Text(
                    'Weave clarity into your decisions.',
                    textAlign: TextAlign.center,
                    style: AppTheme.secondary(context),
                  ),
                  SizedBox(height: AppTheme.s10),
                  AppButton(
                    label: 'Sign in',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: () => _go(const LoginScreen()),
                  ),
                  SizedBox(height: AppTheme.s3),
                  AppButton.secondary(
                    label: 'Create an account',
                    onPressed: () => _go(const RegisterScreen()),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 4),
          ],
        ),
      ),
    );
  }
}
