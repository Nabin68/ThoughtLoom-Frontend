//login_screen.dart

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_header.dart';
import '../widgets/app_text_field.dart';
import '../widgets/error_banner.dart';
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
      await Backend.auth.signIn(email: _email.text, password: _password.text);
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
    return AppBackground(
      child: Column(
        children: [
          AppHeader(title: '', onBack: () => Navigator.pop(context)),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppTheme.s6,
                AppTheme.s2,
                AppTheme.s6,
                AppTheme.s8,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome back', style: AppTheme.display(context)),
                    SizedBox(height: AppTheme.s3),
                    Text(
                      'Sign in to pick up where you left off.',
                      style: AppTheme.secondary(context),
                    ),
                    SizedBox(height: AppTheme.s6),
                    AppTextField(
                      controller: _email,
                      hintText: 'you@example.com',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_busy,
                      validator: Validators.email,
                    ),
                    SizedBox(height: AppTheme.s3),
                    AppTextField(
                      controller: _password,
                      hintText: 'Your password',
                      icon: Icons.lock_outline,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      enabled: !_busy,
                      validator: Validators.requiredPassword,
                      onToggleObscure: () => setState(() => _obscure = !_obscure),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      SizedBox(height: AppTheme.s4),
                      ErrorBanner(message: _error!),
                    ],
                    SizedBox(height: AppTheme.s6),
                    AppButton(
                      label: 'Sign in',
                      busy: _busy,
                      onPressed: _submit,
                      icon: Icons.arrow_forward_rounded,
                    ),
                    SizedBox(height: AppTheme.s3),
                    AppButton.secondary(
                      label: 'New here? Create an account',
                      onPressed: _busy
                          ? null
                          : () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
