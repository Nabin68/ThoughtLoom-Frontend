//memory_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_memory.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/error_banner.dart';

/// What the app has concluded about the user, in the words it wrote them in.
///
/// ### Why this is a screen and not a debug tool
///
/// The app quietly builds a dossier: every finished chat is folded into
/// `user_memory` by a model, and every later conversation is silently primed
/// with it. That is the feature — a session months from now starts warm instead
/// of cold — and it is also the thing most worth being uneasy about, because
/// until now the user had no way to know it existed, let alone read it or
/// disagree with it.
///
/// So this shows the rows verbatim. Not a summary of the summary, not a
/// friendlier paraphrase: the actual sentences that go into the prompt. If the
/// app has decided something wrong or unkind about someone, they are entitled to
/// see it in the form it will be used, and to delete it.
///
/// [userId] is passed in for the usual reason: this is a pushed route and cannot
/// reach `SessionScope`.
class MemoryScreen extends StatefulWidget {
  final String userId;

  const MemoryScreen({super.key, required this.userId});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<UserMemory>? _memories;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final memories = await Backend.data.fetchAllMemory(widget.userId);
      if (!mounted) return;
      setState(() {
        // The global row first, then the topics — the same order the prompt
        // assembles them in, because the point of this screen is to show what is
        // actually being sent.
        _memories = memories
          ..sort((a, b) {
            if (a.isGlobal != b.isGlobal) return a.isGlobal ? -1 : 1;
            return (a.category?.label ?? '').compareTo(b.category?.label ?? '');
          });
        _error = null;
      });
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  /// Everything that is actually written down, as one block of text.
  ///
  /// A row whose summary and facts are both empty is a provisioned placeholder —
  /// the sign-up trigger creates the global row immediately — and it is not
  /// something anyone remembers about anyone.
  List<UserMemory> get _written =>
      (_memories ?? const []).where((m) => !_isEmpty(m)).toList();

  static bool _isEmpty(UserMemory memory) =>
      memory.summary.trim().isEmpty && _factsOf(memory).isEmpty;

  static List<String> _factsOf(UserMemory memory) => memory.facts
      .whereType<String>()
      .map((f) => f.trim())
      .where((f) => f.isNotEmpty)
      .toList();

  /// The whole memory as plain text — what the user asked to be able to see.
  String get _asText {
    final buffer = StringBuffer();
    for (final memory in _written) {
      buffer.writeln(memory.isGlobal
          ? 'IN GENERAL'
          : (memory.category?.label ?? '').toUpperCase());
      if (memory.summary.trim().isNotEmpty) {
        buffer.writeln(memory.summary.trim());
      }
      for (final fact in _factsOf(memory)) {
        buffer.writeln('- $fact');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  Future<void> _forget(UserMemory memory) async {
    final label =
        memory.isGlobal ? 'everything general' : (memory.category?.label ?? '');
    final confirmed = await _confirm(
      title: memory.isGlobal ? 'Forget the general notes?' : 'Forget $label?',
      body: 'ThoughtLoom will stop carrying this into new chats. Your actual '
          'conversations are not touched — and it will start noticing things '
          'again from the next chat you finish.',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // Emptied rather than deleted. The row is provisioned at sign-up and is
      // keyed (user_id, category) by a partial unique index — clearing it is the
      // same end state and avoids racing the next merge to recreate it.
      await Backend.data.saveMemory(
        userId: widget.userId,
        category: memory.category,
        summary: '',
        facts: const [],
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _forgetAll() async {
    final confirmed = await _confirm(
      title: 'Forget everything?',
      body: 'Every note ThoughtLoom has made about you, across all topics. Your '
          'chats stay exactly as they are. This cannot be undone.',
      danger: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      for (final memory in _written) {
        await Backend.data.saveMemory(
          userId: widget.userId,
          category: memory.category,
          summary: '',
          facts: const [],
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    bool danger = false,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rLg),
          ),
          title: Text(title, style: AppTheme.heading(context)),
          content: Text(body, style: AppTheme.secondary(context)),
          actionsPadding: EdgeInsets.fromLTRB(
            AppTheme.s4,
            0,
            AppTheme.s4,
            AppTheme.s4,
          ),
          actions: [
            AppButton.quiet(
              label: 'Cancel',
              onPressed: () => Navigator.pop(context, false),
            ),
            SizedBox(width: AppTheme.s2),
            AppButton.danger(
              label: danger ? 'Forget everything' : 'Forget it',
              expand: false,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final loaded = _memories != null;
    final written = _written;

    return AppBackground(
      child: Column(
        children: [
          AppHeader(
            title: 'What ThoughtLoom remembers',
            subtitle: 'In its own words',
            onBack: () => Navigator.pop(context),
            actions: [
              if (loaded && written.isNotEmpty)
                HeaderIconButton(
                  icon: Icons.copy_all_outlined,
                  tooltip: 'Copy it all',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _asText));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied.')),
                    );
                  },
                ),
            ],
          ),
          Expanded(
            child: !loaded
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  )
                : ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      AppTheme.s5,
                      AppTheme.s2,
                      AppTheme.s5,
                      AppTheme.s8,
                    ),
                    children: [
                      if (_error != null) ...[
                        ErrorBanner(message: _error!),
                        SizedBox(height: AppTheme.s4),
                      ],
                      if (written.isEmpty)
                        const _NothingRemembered()
                      else ...[
                        Text(
                          'These notes are built from your finished chats, and '
                          'they are read back into every new one. This is the '
                          'text itself — not a summary of it.',
                          style: AppTheme.secondary(context),
                        ),
                        SizedBox(height: AppTheme.s5),
                        for (final memory in written) ...[
                          _MemoryCard(
                            memory: memory,
                            facts: _factsOf(memory),
                            onForget: _busy ? null : () => _forget(memory),
                          ),
                          SizedBox(height: AppTheme.s4),
                        ],
                        SizedBox(height: AppTheme.s2),
                        AppButton.secondary(
                          label: 'Forget everything',
                          icon: Icons.delete_sweep_outlined,
                          busy: _busy,
                          onPressed: _forgetAll,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NothingRemembered extends StatelessWidget {
  const _NothingRemembered();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: AppTheme.s10),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 44,
            color: AppTheme.textFaint.withValues(alpha: 0.5),
          ),
          SizedBox(height: AppTheme.s4),
          Text('Nothing yet', style: AppTheme.title(context)),
          SizedBox(height: AppTheme.s2),
          Text(
            'ThoughtLoom starts noticing things once you finish a chat. '
            'Whatever it works out will appear here, and you can delete any of '
            'it.',
            textAlign: TextAlign.center,
            style: AppTheme.secondary(context),
          ),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final UserMemory memory;
  final List<String> facts;
  final VoidCallback? onForget;

  const _MemoryCard({
    required this.memory,
    required this.facts,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final label = memory.isGlobal
        ? 'In general'
        : 'On ${(memory.category?.label ?? '').toLowerCase()}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionLabel(
                  label,
                  icon: memory.isGlobal
                      ? Icons.person_outline
                      : Icons.topic_outlined,
                ),
              ),
              HeaderIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Forget this',
                color: AppTheme.textFaint,
                onPressed: onForget,
              ),
            ],
          ),
          if (memory.summary.trim().isNotEmpty) ...[
            SizedBox(height: AppTheme.s2),
            Text(memory.summary.trim(), style: AppTheme.body(context)),
          ],
          if (facts.isNotEmpty) ...[
            SizedBox(height: AppTheme.s3),
            for (final fact in facts)
              Padding(
                padding: EdgeInsets.only(bottom: AppTheme.s2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AppTheme.accentDeep,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: AppTheme.s3),
                    Expanded(child: Text(fact, style: AppTheme.body(context))),
                  ],
                ),
              ),
          ],
          SizedBox(height: AppTheme.s1),
          Text(
            'Last updated ${_when(memory.updatedAt)}',
            style: AppTheme.meta(context),
          ),
        ],
      ),
    );
  }

  static String _when(DateTime at) {
    final age = DateTime.now().difference(at.toLocal());
    if (age.inDays < 1) return 'today';
    if (age.inDays == 1) return 'yesterday';
    if (age.inDays < 30) return '${age.inDays} days ago';
    return '${at.toLocal().day}/${at.toLocal().month}/${at.toLocal().year}';
  }
}
