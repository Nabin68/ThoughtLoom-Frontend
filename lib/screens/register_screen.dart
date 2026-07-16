//register_screen.dart

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/app_background.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/error_banner.dart';
import '../widgets/primary_button.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final result = await Backend.auth.signUp(
        email: _email.text,
        password: _password.text,
        displayName: _name.text,
      );

      if (!mounted) return;

      if (result.needsEmailConfirmation) {
        // The account exists but has no session. Staying put with an explanation
        // beats bouncing the user to a sign-in that would reject them.
        setState(() {
          _notice = 'Account created. Check ${result.user.email} for a '
              'confirmation link, then sign in.';
        });
        return;
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;

    return AppBackground(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: screenHeight * 0.02,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  color: AppTheme.textOnCard,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: screenHeight * 0.01),
                      Text(
                        "Create your\naccount",
                        style: TextStyle(
                          fontSize: screenWidth * 0.08,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.015),
                      Text(
                        "So your thinking stays with you,\nchat after chat.",
                        style: TextStyle(
                          fontSize: screenWidth * 0.038,
                          color: AppTheme.textLight,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.04),
                      AuthTextField(
                        controller: _name,
                        hintText: 'Your name',
                        icon: Icons.person_outline,
                        keyboardType: TextInputType.name,
                        enabled: !_busy,
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      AuthTextField(
                        controller: _email,
                        hintText: 'you@example.com',
                        icon: Icons.mail_outline,
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_busy,
                        validator: Validators.email,
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      AuthTextField(
                        controller: _password,
                        hintText:
                            'Password (${Validators.minPasswordLength}+ characters)',
                        icon: Icons.lock_outline,
                        obscureText: _obscure,
                        enabled: !_busy,
                        validator: Validators.password,
                        onToggleObscure: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      AuthTextField(
                        controller: _confirm,
                        hintText: 'Confirm password',
                        icon: Icons.lock_outline,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        enabled: !_busy,
                        validator:
                            Validators.confirmPassword(() => _password.text),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        SizedBox(height: screenHeight * 0.02),
                        ErrorBanner(message: _error!),
                      ],
                      if (_notice != null) ...[
                        SizedBox(height: screenHeight * 0.02),
                        InfoBanner(message: _notice!),
                      ],
                      SizedBox(height: screenHeight * 0.04),
                      Center(
                        child: PrimaryButton(
                          label: 'Create Account',
                          busy: _busy,
                          onPressed: _submit,
                          icon: Icons.arrow_forward,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      Center(
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(),
                                    ),
                                  ),
                          child: RichText(
                            text: TextSpan(
                              text: "Already have an account? ",
                              style: TextStyle(
                                fontSize: screenWidth * 0.038,
                                color: AppTheme.textLight,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Sign in',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.03),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
