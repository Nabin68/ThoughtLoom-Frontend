//dashboard_screen.dart

import 'package:flutter/material.dart';

import '../models/chat_category.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import '../widgets/error_banner.dart';
import 'history_screen.dart';
import 'intake_flow_screen.dart';
import 'profile_screen.dart';

/// Home for a signed-in user with a finished profile: pick a category, or go
/// look at what you have already thought through.
///
/// Rendered directly by `AuthGate` — it is the first route, so everything else
/// stacks on top and `popUntil((r) => r.isFirst)` comes back here.
///
/// ### Sign-out is not here any more
///
/// It used to be a bare `TextButton` at the bottom of this screen — a grey word
/// floating on the background, with no edge and a tap target under 30pt. It read
/// as a caption, not a control, which is exactly what it was reported as. It now
/// lives in [ProfileScreen], because it is an account action and that is the
/// account screen; the way in is the avatar in the header, where every app has
/// trained people to look for it.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Which card is mid-create, so it alone shows a spinner and the others go
  /// inert. A second tap while a chat is being created would create two.
  ChatCategory? _starting;

  String? _error;

  Future<void> _start(ChatCategory category) async {
    if (_starting != null) return;

    final session = SessionScope.of(context);
    setState(() {
      _starting = category;
      _error = null;
    });

    try {
      // The chat row is created here, on the tap, before a single question is
      // asked — which is what lets the intake screens write messages against a
      // real chat_id from their first answer. The cost is that abandoning the
      // flow leaves an empty in-progress chat; history renders those honestly as
      // "Unfinished".
      final chat = await Backend.data.createChat(
        userId: session.user.id,
        category: category,
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IntakeFlowScreen(chat: chat, profile: session.profile),
        ),
      );
      if (!mounted) return;
      // Cleared on return so the card is tappable again after the user comes
      // back from a finished or abandoned flow.
      setState(() => _starting = null);
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = null;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final name = (session.profile.displayName ?? '').trim();
    final greeting = name.isEmpty ? 'Hello' : 'Hello, $name';

    return AppBackground(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.s5,
              AppTheme.s3,
              AppTheme.s3,
              0,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
                SizedBox(width: AppTheme.s2),
                Expanded(
                  child: Text(
                    'ThoughtLoom',
                    style: AppTheme.label(context).copyWith(
                      color: AppTheme.textDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                HeaderIconButton(
                  icon: Icons.history_rounded,
                  tooltip: 'Your past chats',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      // Handed down rather than read from SessionScope inside: a
                      // pushed route is not below the scope. See HistoryScreen.
                      builder: (_) => HistoryScreen(userId: session.user.id),
                    ),
                  ),
                ),
                HeaderIconButton(
                  icon: Icons.person_outline_rounded,
                  tooltip: 'Profile and sign out',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        user: session.user,
                        profile: session.profile,
                        onSaved: session.reload,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppTheme.s5,
                AppTheme.s5,
                AppTheme.s5,
                AppTheme.s8,
              ),
              children: [
                Text(
                  greeting,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.display(context),
                ),
                SizedBox(height: AppTheme.s2),
                Text(
                  'What is on your mind?',
                  style: AppTheme.secondary(context),
                ),
                SizedBox(height: AppTheme.s6),
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  SizedBox(height: AppTheme.s4),
                ],
                for (final category in ChatCategory.values)
                  _CategoryCard(
                    category: category,
                    busy: _starting == category,
                    // Null while any card is starting, which disables all four
                    // rather than only the one that was tapped.
                    onTap: _starting == null ? () => _start(category) : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What each category is for, in the user's terms rather than the schema's.
/// "Financial" alone is a column name; "Money, and what to do about it" is a
/// door someone walks through.
({IconData icon, String blurb}) _presentation(ChatCategory category) =>
    switch (category) {
      ChatCategory.education => (
          icon: Icons.school_outlined,
          blurb: 'Studying, courses, what to learn next',
        ),
      ChatCategory.financial => (
          icon: Icons.savings_outlined,
          blurb: 'Money, spending, earning, what it costs',
        ),
      ChatCategory.relationship => (
          icon: Icons.favorite_border,
          blurb: 'Family, partners, friends, the difficult ones',
        ),
      ChatCategory.other => (
          icon: Icons.all_inclusive,
          blurb: 'Work, health, habits — anything else',
        ),
    };

/// One tappable topic.
class _CategoryCard extends StatelessWidget {
  final ChatCategory category;
  final bool busy;
  final VoidCallback? onTap;

  const _CategoryCard({
    required this.category,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);
    final presentation = _presentation(category);

    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.s3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          boxShadow: AppTheme.shadowCard,
        ),
        child: Material(
          color: busy ? AppTheme.primary : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashColor: AppTheme.primary.withValues(alpha: 0.12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.s4,
                vertical: AppTheme.s4 + 2,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rLg),
                border: Border.all(
                  color: busy ? AppTheme.primary : AppTheme.border,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42 * scale,
                    height: 42 * scale,
                    decoration: BoxDecoration(
                      // A tinted tile behind the glyph rather than a bare icon:
                      // it gives the row a fixed left edge to align to, and it is
                      // the difference between a list of cards and a list of
                      // sentences.
                      color: busy
                          ? Colors.white.withValues(alpha: 0.18)
                          : AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(AppTheme.rSm),
                    ),
                    child: busy
                        ? Padding(
                            padding: EdgeInsets.all(11 * scale),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            presentation.icon,
                            size: 21 * scale,
                            color: AppTheme.primary,
                          ),
                  ),
                  SizedBox(width: AppTheme.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.heading(context).copyWith(
                            color: busy ? Colors.white : AppTheme.textOnCard,
                          ),
                        ),
                        SizedBox(height: AppTheme.s1),
                        Text(
                          presentation.blurb,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.meta(context).copyWith(
                            color: busy
                                ? Colors.white.withValues(alpha: 0.85)
                                : AppTheme.textFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: AppTheme.s2),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18 * scale,
                    color: busy ? Colors.white : AppTheme.textFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
