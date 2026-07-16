//register_screen.dart

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
                    Text('Create your account',
                        style: AppTheme.display(context)),
                    SizedBox(height: AppTheme.s3),
                    Text(
                      'So your thinking stays with you, chat after chat.',
                      style: AppTheme.secondary(context),
                    ),
                    SizedBox(height: AppTheme.s6),
                    AppTextField(
                      controller: _name,
                      hintText: 'Your name',
                      icon: Icons.person_outline,
                      keyboardType: TextInputType.name,
                      enabled: !_busy,
                    ),
                    SizedBox(height: AppTheme.s3),
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
                      hintText:
                          'Password (${Validators.minPasswordLength}+ characters)',
                      icon: Icons.lock_outline,
                      obscureText: _obscure,
                      enabled: !_busy,
                      validator: Validators.password,
                      onToggleObscure: () => setState(() => _obscure = !_obscure),
                    ),
                    SizedBox(height: AppTheme.s3),
                    AppTextField(
                      controller: _confirm,
                      hintText: 'Confirm password',
                      icon: Icons.lock_outline,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      enabled: !_busy,
                      validator: Validators.confirmPassword(() => _password.text),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      SizedBox(height: AppTheme.s4),
                      ErrorBanner(message: _error!),
                    ],
                    if (_notice != null) ...[
                      SizedBox(height: AppTheme.s4),
                      InfoBanner(message: _notice!),
                    ],
                    SizedBox(height: AppTheme.s6),
                    AppButton(
                      label: 'Create account',
                      busy: _busy,
                      onPressed: _submit,
                      icon: Icons.arrow_forward_rounded,
                    ),
                    SizedBox(height: AppTheme.s3),
                    AppButton.secondary(
                      label: 'Already have an account? Sign in',
                      onPressed: _busy
                          ? null
                          : () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
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
