//login_screen.dart

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/app_background.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/error_banner.dart';
import '../widgets/primary_button.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await Backend.auth.signIn(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      // AuthGate has already rebuilt underneath from the auth stream; unwinding
      // to the root route reveals it.
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
                        "Welcome back",
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
                        "Sign in to pick up where you left off.",
                        style: TextStyle(
                          fontSize: screenWidth * 0.038,
                          color: AppTheme.textLight,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.04),
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
                        hintText: 'Your password',
                        icon: Icons.lock_outline,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        enabled: !_busy,
                        validator: Validators.requiredPassword,
                        onToggleObscure: () =>
                            setState(() => _obscure = !_obscure),
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        SizedBox(height: screenHeight * 0.02),
                        ErrorBanner(message: _error!),
                      ],
                      SizedBox(height: screenHeight * 0.04),
                      Center(
                        child: PrimaryButton(
                          label: 'Sign In',
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
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  ),
                          child: RichText(
                            text: TextSpan(
                              text: "New here? ",
                              style: TextStyle(
                                fontSize: screenWidth * 0.038,
                                color: AppTheme.textLight,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Create an account',
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
