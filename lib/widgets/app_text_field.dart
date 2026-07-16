//app_text_field.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's text input.
///
/// Was `AuthTextField`, named for the two screens that first needed it and then
/// used by onboarding, the intake, the adaptive questions, and the profile — so
/// the name had become a lie.
///
/// ### Focus is visible now
///
/// The old field was a cream pill with no border in any state, which meant a
/// tapped field looked exactly like an untapped one and exactly like a card. On
/// a screen with several, nothing said which one the keyboard was pointed at.
/// The border here tracks focus and error, which is the whole job of a field's
/// outline.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData? icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final String? Function(String?)? validator;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;

  /// Above 1 the field grows into a paragraph box, keeping the card styling.
  final int maxLines;
  final int? minLines;

  /// Fired when the user reaches for this field.
  ///
  /// Exists so a screen with dictation can turn the microphone off: someone
  /// tapping into a text box has decided to type, and a mic that kept
  /// overwriting what they typed from under them was the single most
  /// disorienting thing in the app.
  final VoidCallback? onTap;

  /// Draws the field as live-dictation red rather than sage. The field is where
  /// the words are landing, so it is the field that should say so.
  final bool listening;

  const AppTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.validator,
    this.onToggleObscure,
    this.onFieldSubmitted,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.onTap,
    this.listening = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
    // Focus, not just tap: a field reached by the keyboard's Next button, or by
    // any route that is not a finger, means the same thing.
    if (_focus.hasFocus) widget.onTap?.call();
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  Color get _edge {
    if (_hasError) return AppTheme.danger;
    if (widget.listening) return AppTheme.live;
    if (_focus.hasFocus) return AppTheme.primary;
    return AppTheme.border;
  }

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);
    final multiline = widget.maxLines > 1;
    final radius = multiline ? AppTheme.rLg : AppTheme.pillRadius;
    final focused = _focus.hasFocus || widget.listening;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _edge, width: focused || _hasError ? 1.8 : 1),
        boxShadow: focused ? AppTheme.shadowCard : AppTheme.shadowSoft,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        onFieldSubmitted: widget.onFieldSubmitted,
        onChanged: widget.onChanged,
        onTap: widget.onTap,
        maxLines: widget.obscureText ? 1 : widget.maxLines,
        minLines: widget.obscureText ? 1 : widget.minLines,
        validator: widget.validator == null
            ? null
            : (value) {
                final error = widget.validator!(value);
                // The border has to know, and the validator is the only thing
                // that does. Deferred a frame because validate() runs during a
                // build and setState inside one is illegal.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _hasError != (error != null)) {
                    setState(() => _hasError = error != null);
                  }
                });
                return error;
              },
        // Keeps the leading icon beside the first line rather than floating in
        // the middle of a grown paragraph box.
        textAlignVertical:
            multiline ? TextAlignVertical.top : TextAlignVertical.center,
        style: AppTheme.body(context).copyWith(fontSize: 15 * scale),
        cursorColor: widget.listening ? AppTheme.live : AppTheme.primary,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: AppTheme.body(context).copyWith(
            color: AppTheme.textFaint.withValues(alpha: 0.75),
          ),
          prefixIcon: widget.icon == null
              ? null
              : Padding(
                  padding: EdgeInsets.only(
                    left: AppTheme.s4,
                    right: AppTheme.s2,
                    // Pins the icon to the first line in a paragraph box.
                    bottom: multiline ? AppTheme.s4 * 2 : 0,
                  ),
                  child: Icon(
                    widget.icon,
                    size: 19 * scale,
                    color: _focus.hasFocus
                        ? AppTheme.primary
                        : AppTheme.textFaint,
                  ),
                ),
          prefixIconConstraints: BoxConstraints(minWidth: 44 * scale),
          suffixIcon: widget.onToggleObscure == null
              ? null
              : IconButton(
                  onPressed: widget.onToggleObscure,
                  tooltip: widget.obscureText ? 'Show password' : 'Hide password',
                  icon: Icon(
                    widget.obscureText
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19 * scale,
                    color: AppTheme.textFaint,
                  ),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          // The container above draws every border. Left to itself the field
          // would draw a second, differently-rounded one inside it.
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          // The validator message sits outside the pill; without this the error
          // text would stretch the card itself.
          errorStyle: TextStyle(
            fontSize: 12 * scale,
            height: 1.2,
            color: AppTheme.dangerText,
            fontWeight: FontWeight.w600,
          ),
          contentPadding: EdgeInsets.fromLTRB(
            widget.icon == null ? AppTheme.s5 : AppTheme.s1,
            AppTheme.s4,
            AppTheme.s5,
            AppTheme.s4,
          ),
        ),
      ),
    );
  }
}
