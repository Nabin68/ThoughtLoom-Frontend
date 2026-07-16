//chat_transcript_screen.dart

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../services/backend.dart';
import '../services/chat_completion.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/error_banner.dart';
import '../widgets/rich_body.dart';

/// A conversation, read back whole.
///
/// Unlike [ContinuedChatScreen] — which shows the recommendation onward, because
/// it is a continuation and the scripted opening would bury the answer — this
/// shows *everything*, in order. It is the other job: not "keep talking" but
/// "what did I say, and what did it tell me?". The questions are part of that.
///
/// Read-only. Re-answering a question inside a finished chat would quietly
/// change the conversation the advice was based on.
///
/// [userId] is not needed: the chat is handed in whole, and RLS scopes the
/// message read to its owner. This is a pushed route, so it cannot reach
/// `SessionScope` — see [HistoryScreen].
class ChatTranscriptScreen extends StatefulWidget {
  final Chat chat;

  /// Whether opening this counts as a second attempt at closing the chat.
  ///
  /// True from history, where it is exactly that — see [_backfill]. False when
  /// this is opened as a read-back from inside a live conversation, which is not
  /// a chat anybody is finished with.
  final bool backfill;

  const ChatTranscriptScreen({
    super.key,
    required this.chat,
    this.backfill = true,
  });

  @override
  State<ChatTranscriptScreen> createState() => _ChatTranscriptScreenState();
}

class _ChatTranscriptScreenState extends State<ChatTranscriptScreen> {
  late final Future<List<Message>> _messages =
      Backend.data.fetchMessages(widget.chat.id);

  @override
  void initState() {
    super.initState();
    _backfill();
  }

  /// Asks the API to finish closing this chat, if it never got that far.
  ///
  /// Titling and the memory merge run in a background task after the user leaves
  /// a chat, and the request that starts them can simply not arrive — the app was
  /// killed, the network was down, Render was cold. Without a second chance, that
  /// chat is untitled and outside the user's memory forever, silently.
  ///
  /// Opening one is the natural retry: the user is looking at the chat, the API
  /// skips whichever half already ran, and the work is bounded by their own
  /// tapping rather than by a loop.
  void _backfill() {
    if (!widget.backfill) return;
    final chat = widget.chat;
    if (chat.title != null || chat.status != ChatStatus.completed) return;
    // Not awaited and not shown: the title lands on the next visit to history.
    // Blocking a transcript the user asked to read on a model call would be a
    // strange thing to do to them.
    completeChat(chat);
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            title: widget.chat.title ?? widget.chat.category.label,
            subtitle: 'The whole conversation',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: FutureBuilder<List<Message>>(
              future: _messages,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppTheme.s5),
                    child: ErrorBanner(message: snapshot.error.toString()),
                  );
                }

                final messages = snapshot.data!;
                if (messages.isEmpty) return const _NothingInIt();

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppTheme.s5,
                    AppTheme.s3,
                    AppTheme.s5,
                    AppTheme.s8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _Turn(message: messages[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// An abandoned chat: the dashboard opens a chat row on the category tap, so a
/// mis-tap is a real row with nothing in it.
class _NothingInIt extends StatelessWidget {
  const _NothingInIt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppTheme.s8),
        child: Text(
          'This one never got started.',
          textAlign: TextAlign.center,
          style: AppTheme.secondary(context),
        ),
      ),
    );
  }
}

/// One turn, rendered by what kind of turn it was.
///
/// A question and its answer are one row in the database, so they are one widget
/// here: the question in the quiet type a label gets, the answer under it.
class _Turn extends StatelessWidget {
  final Message message;

  const _Turn({required this.message});

  @override
  Widget build(BuildContext context) {
    final answer = (message.answerText ?? '').trim();
    final question = (message.questionText ?? '').trim();

    switch (message.type) {
      case MessageType.intake:
      case MessageType.adaptiveQuestion:
        // An unanswered question is still worth showing — it is what the chat
        // was in the middle of asking when it was abandoned.
        return _QuestionAndAnswer(
          question: question,
          answer: answer,
          // Written by the flow for a multi-select turn, so the transcript can
          // show three ticked answers as three answers rather than as one
          // sentence with semicolons in it.
          selected: (message.metadata['selected'] as List? ?? const [])
              .whereType<String>()
              .toList(),
        );
      case MessageType.freeText:
        if (answer.isEmpty) return const SizedBox.shrink();
        return _Said(text: answer);
      case MessageType.recommendation:
        if (answer.isEmpty) return const SizedBox.shrink();
        return _Advice(text: answer, metadata: message.metadata);
      case MessageType.assistantReply:
        if (answer.isEmpty) return const SizedBox.shrink();
        return _Replied(text: answer);
    }
  }
}

class _QuestionAndAnswer extends StatelessWidget {
  final String question;
  final String answer;
  final List<String> selected;

  const _QuestionAndAnswer({
    required this.question,
    required this.answer,
    this.selected = const [],
  });

  @override
  Widget build(BuildContext context) {
    // More than one is what makes it worth listing; a single-select answer
    // stored with the same key is just a sentence.
    final asList = selected.length > 1;

    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.isNotEmpty) ...[
            Text(question, style: AppTheme.meta(context)),
            SizedBox(height: AppTheme.s2),
          ],
          if (answer.isEmpty)
            Text(
              '(skipped)',
              style: AppTheme.body(context).copyWith(
                color: AppTheme.textFaint,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (asList)
            for (final one in selected)
              Padding(
                padding: EdgeInsets.only(bottom: AppTheme.s1 + 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                    ),
                    SizedBox(width: AppTheme.s2),
                    Expanded(
                      child: Text(
                        one,
                        style: AppTheme.body(context).copyWith(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
          else
            Text(
              answer,
              style: AppTheme.body(context).copyWith(
                color: AppTheme.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// The user's own words — the same sage the chat bubbles use for them.
class _Said extends StatelessWidget {
  final String text;

  const _Said({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: AppTheme.s5),
      padding: EdgeInsets.all(AppTheme.s4),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        boxShadow: AppTheme.shadowSoft,
      ),
      child: Text(
        text,
        style: AppTheme.body(context).copyWith(color: Colors.white),
      ),
    );
  }
}

class _Replied extends StatelessWidget {
  final String text;

  const _Replied({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: AppTheme.s5),
      padding: EdgeInsets.all(AppTheme.s4),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: RichBody(
        markdown: text,
        baseStyle: AppTheme.body(context),
        allowCallouts: false,
      ),
    );
  }
}

/// The advice, given the weight it had on the day.
///
/// It is the one turn someone comes back to read, so it is the one turn that
/// gets a heading, its headline, and its steps — a transcript where the answer
/// looked like every other bubble would make them scroll for the thing they
/// opened this to find.
class _Advice extends StatelessWidget {
  final String text;
  final Map<String, dynamic> metadata;

  const _Advice({required this.text, required this.metadata});

  List<String> get _steps =>
      (metadata['next_steps'] as List? ?? const []).whereType<String>().toList();

  String get _headline => (metadata['headline'] as String? ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final headline = _headline;

    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.s5),
      child: AppCard(
        highlighted: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('What I said', icon: Icons.bolt_rounded),
            SizedBox(height: AppTheme.s3),
            if (headline.isNotEmpty) ...[
              Text(headline, style: AppTheme.title(context)),
              SizedBox(height: AppTheme.s3),
            ],
            RichBody(markdown: text, baseStyle: AppTheme.body(context)),
            if (steps.isNotEmpty) ...[
              SizedBox(height: AppTheme.s4),
              const SectionLabel('Where to start'),
              SizedBox(height: AppTheme.s3),
              for (final step in steps)
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
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      SizedBox(width: AppTheme.s3),
                      Expanded(
                        child: Text(step, style: AppTheme.body(context)),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
