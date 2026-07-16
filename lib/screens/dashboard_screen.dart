//dashboard_screen.dart

import 'package:flutter/material.dart';

import '../models/chat_category.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/error_banner.dart';
import 'history_screen.dart';
import 'intake_flow_screen.dart';

/// Home for a signed-in user with a finished profile: pick a category, or go
/// look at what you have already thought through.
///
/// Rendered directly by `AuthGate` — it is the first route, so everything else
/// stacks on top and `popUntil((r) => r.isFirst)` comes back here.
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
      // asked — per the spec, and it is also what lets the intake screens write
      // messages against a real chat_id from their first answer. The cost is
      // that abandoning the flow leaves an empty in-progress chat; history
      // already renders those honestly as "Unfinished".
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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final name = (session.profile.displayName ?? '').trim();
    final greeting = name.isEmpty ? 'Hello' : 'Hello, $name';

    return AppBackground(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: screenHeight * 0.025),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: screenWidth * 0.08,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                          height: 1.2,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.008),
                      Text(
                        'What is on your mind?',
                        style: TextStyle(
                          fontSize: screenWidth * 0.038,
                          color: AppTheme.textLight,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                _HistoryButton(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      // Handed down rather than read from SessionScope inside:
                      // a pushed route is not below the scope. See HistoryScreen.
                      builder: (_) => HistoryScreen(userId: session.user.id),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: screenHeight * 0.03),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              SizedBox(height: screenHeight * 0.02),
            ],
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    for (final category in ChatCategory.values)
                      _CategoryCard(
                        category: category,
                        busy: _starting == category,
                        // Null while any card is starting, which disables all
                        // four rather than only the one that was tapped.
                        onTap: _starting == null
                            ? () => _start(category)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            Center(
              child: TextButton(
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
            ),
            SizedBox(height: screenHeight * 0.01),
          ],
        ),
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

/// One tappable topic, in the cream card the option rows use.
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
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final presentation = _presentation(category);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: screenHeight * 0.018),
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.05,
          vertical: screenHeight * 0.022,
        ),
        decoration: BoxDecoration(
          color: busy
              ? AppTheme.selected
              : AppTheme.cardBg.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: busy ? 0.1 : 0.4),
              offset: const Offset(0, -1),
              blurRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: screenWidth * 0.07,
              height: screenWidth * 0.07,
              child: busy
                  ? Padding(
                      padding: EdgeInsets.all(screenWidth * 0.008),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      presentation.icon,
                      size: screenWidth * 0.065,
                      color: AppTheme.textOnCard,
                    ),
            ),
            SizedBox(width: screenWidth * 0.04),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: screenWidth * 0.045,
                      color: busy ? Colors.white : AppTheme.textOnCard,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.008),
                  Text(
                    presentation.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: screenWidth * 0.033,
                      color: busy
                          ? Colors.white.withValues(alpha: 0.85)
                          : AppTheme.textLight,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward,
              size: screenWidth * 0.045,
              color: busy
                  ? Colors.white
                  : AppTheme.textLight.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// The way into history. A card would compete with the four topics for the eye,
/// so it sits up in the header as an affordance rather than an option.
class _HistoryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HistoryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.04,
          vertical: screenWidth * 0.025,
        ),
        decoration: BoxDecoration(
          color: AppTheme.cardBg.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: screenWidth * 0.045,
              color: AppTheme.textOnCard,
            ),
            SizedBox(width: screenWidth * 0.015),
            Text(
              'Past',
              style: TextStyle(
                fontSize: screenWidth * 0.034,
                color: AppTheme.textOnCard,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
