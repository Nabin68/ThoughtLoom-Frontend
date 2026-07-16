//profile_screen.dart

import 'package:flutter/material.dart';

import '../data/onboarding_questions.dart';
import '../models/auth_user.dart';
import '../models/onboarding_question.dart';
import '../models/user_profile.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/app_text_field.dart';
import '../widgets/error_banner.dart';
import '../widgets/option_tile.dart';
import 'memory_screen.dart';

/// Everything the app holds about the user, in one place, editable.
///
/// The app had nowhere to see or change any of this. Onboarding asked twelve
/// questions once and then buried the answers in a jsonb column forever — so a
/// user who moved city, finished their degree, or ended a relationship had no way
/// to say so, and every recommendation afterwards was quietly grounded in facts
/// that had stopped being true. That is worse than not having asked.
///
/// Sign-out lives here too, rather than as a bare word at the bottom of the
/// dashboard. It is an account action, and this is the account screen.
///
/// ### The name is the only thing that is its own field
///
/// Everything else is an onboarding answer, rendered straight off
/// [onboardingQuestions] and written back through the same [_applyAnswers] rule
/// the onboarding screen uses — so the blob and the promoted columns cannot
/// disagree, and adding a question to that list makes it editable here for free.
/// The email is the account's and is not editable at all: changing it is an auth
/// operation with a confirmation round trip, not a profile edit.
class ProfileScreen extends StatefulWidget {
  final AuthUser user;
  final UserProfile profile;

  /// Called after a successful write so the tree above picks the change up —
  /// `SessionScope.reload`. This is a pushed route and cannot reach the scope
  /// itself.
  final Future<void> Function() onSaved;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.profile,
    required this.onSaved,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserProfile _profile = widget.profile;
  String? _error;
  bool _saving = false;

  Map<String, dynamic> get _answers => _profile.onboardingAnswers;

  /// Writes one change, whatever it was.
  ///
  /// Every edit on this screen is "a new value for one key", so they all land
  /// here: one write path, one error path, one reload.
  Future<void> _save(UserProfile next) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await Backend.data.saveProfile(next);
      if (!mounted) return;
      setState(() {
        _profile = saved;
        _saving = false;
      });
      await widget.onSaved();
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  Future<void> _editName() async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TextEditSheet(
        title: 'Your name',
        helper: 'What ThoughtLoom calls you.',
        initial: _profile.displayName ?? '',
        hint: 'e.g. Aarav',
      ),
    );
    if (name == null || !mounted) return;
    await _save(_profile.copyWith(displayName: name.trim()));
  }

  Future<void> _editAnswer(OnboardingQuestion question) async {
    final stored = _answers[question.id];

    final String? value;
    if (question.kind == OnboardingAnswerKind.text) {
      value = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _TextEditSheet(
          title: question.text,
          helper: question.helper,
          initial: stored is String ? stored : '',
          hint: question.hint ?? '',
          maxLines: question.maxLines,
        ),
      );
    } else {
      value = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ChoiceEditSheet(
          question: question,
          selected: stored is String ? stored : null,
        ),
      );
    }

    if (value == null || !mounted) return;
    // An empty string from a sheet means "clear this", which is only meaningful
    // for an optional question — and is stored as an explicit null, the same way
    // a skip is, so nothing later mistakes it for never-asked.
    final next = value.trim().isEmpty ? null : value.trim();
    await _save(_applyAnswers(_profile, {..._answers, question.id: next}));
  }

  /// The onboarding screen's rule, verbatim in intent: recompute the promoted
  /// columns from the blob on every write rather than patching whichever one
  /// changed, so the two can never disagree.
  UserProfile _applyAnswers(UserProfile profile, Map<String, dynamic> answers) {
    String? column(ProfileColumn which) {
      for (final q in onboardingQuestions) {
        if (q.column != which) continue;
        final value = answers[q.id];
        return value is String && value.isNotEmpty ? value : null;
      }
      return null;
    }

    return profile.copyWith(
      location: column(ProfileColumn.location),
      ageRange: column(ProfileColumn.ageRange),
      occupation: column(ProfileColumn.occupation),
      onboardingAnswers: answers,
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
        ),
        title: Text('Sign out?', style: AppTheme.heading(context)),
        content: Text(
          'Your chats and everything ThoughtLoom remembers stay where they are. '
          'Signing back in picks up exactly here.',
          style: AppTheme.secondary(context),
        ),
        actionsPadding: EdgeInsets.fromLTRB(
          AppTheme.s4,
          0,
          AppTheme.s4,
          AppTheme.s4,
        ),
        actions: [
          AppButton.quiet(
            label: 'Stay',
            onPressed: () => Navigator.pop(context, false),
          ),
          SizedBox(width: AppTheme.s2),
          AppButton(
            label: 'Sign out',
            expand: false,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // AuthGate rebuilds off the auth stream and swaps the whole tree for the
    // landing page, so this route goes with it — no pop needed, and popping
    // first would only show the dashboard mid-teardown.
    await Backend.auth.signOut().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final name = (_profile.displayName ?? '').trim();

    return AppBackground(
      child: Column(
        children: [
          AppHeader(
            title: 'Profile',
            subtitle: 'What ThoughtLoom knows, and can be told',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppTheme.s5,
                AppTheme.s2,
                AppTheme.s5,
                AppTheme.s8,
              ),
              children: [
                _Identity(
                  name: name.isEmpty ? 'No name yet' : name,
                  email: widget.user.email,
                  onEditName: _saving ? null : _editName,
                ),
                if (_error != null) ...[
                  SizedBox(height: AppTheme.s4),
                  ErrorBanner(message: _error!),
                ],
                SizedBox(height: AppTheme.s5),

                // The one thing on this screen that is not a fact about the user
                // but a window into what the app concluded about them. It sits
                // above the form because it is the more interesting half.
                AppCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MemoryScreen(userId: widget.user.id),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.accentSoft,
                          borderRadius: BorderRadius.circular(AppTheme.rSm),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_outlined,
                          size: 19,
                          color: AppTheme.accentDeep,
                        ),
                      ),
                      SizedBox(width: AppTheme.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'What ThoughtLoom remembers',
                              style: AppTheme.label(context),
                            ),
                            SizedBox(height: AppTheme.s1),
                            Text(
                              'Everything it has worked out about you, in plain '
                              'words. Yours to read or erase.',
                              style: AppTheme.meta(context),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: AppTheme.s2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppTheme.textFaint,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: AppTheme.s6),
                const SectionLabel('About you', icon: Icons.person_outline),
                SizedBox(height: AppTheme.s3),
                Text(
                  'This is what grounds every answer you get. Keep it true and '
                  'the advice stays true.',
                  style: AppTheme.secondary(context),
                ),
                SizedBox(height: AppTheme.s4),

                // Rendered straight off the question list, so a question added to
                // onboarding becomes editable here without touching this screen.
                for (final question in onboardingQuestions)
                  _AnswerRow(
                    question: question,
                    // Distinguishes "declined" from "never asked": onboarding
                    // stores a skip as an explicit null, and the two deserve
                    // different words.
                    value: _answers[question.id] is String
                        ? _answers[question.id] as String
                        : null,
                    answered: _answers.containsKey(question.id),
                    onTap: _saving ? null : () => _editAnswer(question),
                  ),

                SizedBox(height: AppTheme.s6),
                AppButton.secondary(
                  label: 'Sign out',
                  icon: Icons.logout_rounded,
                  onPressed: _confirmSignOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Name, email, and the logo — who this account is.
class _Identity extends StatelessWidget {
  final String name;
  final String email;
  final VoidCallback? onEditName;

  const _Identity({
    required this.name,
    required this.email,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: Image.asset('assets/logo.png', fit: BoxFit.contain),
          ),
          SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(context),
                ),
                SizedBox(height: AppTheme.s1),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.meta(context),
                ),
              ],
            ),
          ),
          HeaderIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Change your name',
            onPressed: onEditName,
          ),
        ],
      ),
    );
  }
}

/// One question and its answer, tappable to change.
class _AnswerRow extends StatelessWidget {
  final OnboardingQuestion question;
  final String? value;
  final bool answered;
  final VoidCallback? onTap;

  const _AnswerRow({
    required this.question,
    required this.value,
    required this.answered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.s2),
      child: AppCard(
        onTap: onTap,
        radius: AppTheme.rMd,
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.s4,
          vertical: AppTheme.s3 + 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(question.text, style: AppTheme.meta(context)),
                  SizedBox(height: AppTheme.s1 + 2),
                  Text(
                    has
                        ? value!
                        : answered
                            ? 'Skipped'
                            : 'Not answered',
                    style: AppTheme.label(context).copyWith(
                      color: has ? AppTheme.textOnCard : AppTheme.textFaint,
                      fontStyle: has ? FontStyle.normal : FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppTheme.s2),
            Icon(Icons.edit_outlined, size: 16, color: AppTheme.textFaint),
          ],
        ),
      ),
    );
  }
}

/// The sheet chrome both editors share.
class _Sheet extends StatelessWidget {
  final String title;
  final String? helper;

  /// Named [body] rather than `child` so the analyzer stops asking for it to be
  /// the last argument: it is not the sole child of a container, it is the
  /// middle of three slots, and reading title -> body -> footer in that order is
  /// the point.
  final Widget body;
  final Widget? footer;

  const _Sheet({
    required this.title,
    required this.helper,
    required this.body,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet clear of the keyboard. Without it the field being edited
      // sits underneath it, which is the exact bug this app already had once.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.rLg),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          AppTheme.s5,
          AppTheme.s3,
          AppTheme.s5,
          AppTheme.s5,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: AppTheme.s4),
              Text(title, style: AppTheme.heading(context)),
              if (helper != null) ...[
                SizedBox(height: AppTheme.s1 + 2),
                Text(helper!, style: AppTheme.meta(context)),
              ],
              SizedBox(height: AppTheme.s4),
              Flexible(child: body),
              if (footer != null) ...[
                SizedBox(height: AppTheme.s4),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TextEditSheet extends StatefulWidget {
  final String title;
  final String? helper;
  final String initial;
  final String hint;
  final int maxLines;

  const _TextEditSheet({
    required this.title,
    required this.helper,
    required this.initial,
    required this.hint,
    this.maxLines = 1,
  });

  @override
  State<_TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<_TextEditSheet> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: widget.title,
      helper: widget.helper,
      body: AppTextField(
        controller: _controller,
        hintText: widget.hint,
        autofocus: true,
        maxLines: widget.maxLines,
        keyboardType:
            widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text,
        textInputAction:
            widget.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
        onFieldSubmitted: (value) => Navigator.pop(context, value),
      ),
      footer: AppButton(
        label: 'Save',
        onPressed: () => Navigator.pop(context, _controller.text),
      ),
    );
  }
}

class _ChoiceEditSheet extends StatelessWidget {
  final OnboardingQuestion question;
  final String? selected;

  const _ChoiceEditSheet({required this.question, this.selected});

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      title: question.text,
      helper: question.helper,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in question.options)
              OptionTile(
                label: option,
                selected: selected == option,
                // Tapping an option is the whole interaction here — there is one
                // value and picking it is the edit, so a Save button underneath
                // would be a second tap that does nothing.
                onTap: () => Navigator.pop(context, option),
              ),
            if (question.optional)
              AppButton.quiet(
                label: 'Clear this answer',
                // Empty round-trips as null through _editAnswer, which is how a
                // skip is stored — so clearing here is the same state as
                // declining it during onboarding, not a new one.
                onPressed: () => Navigator.pop(context, ''),
              ),
          ],
        ),
      ),
    );
  }
}
