//chat_transcript_screen.dart

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../services/backend.dart';
import '../services/chat_completion.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/error_banner.dart';

/// A finished conversation, read back.
///
/// Unlike `ContinuedChatScreen` — which shows the recommendation onward, because
/// it is a continuation and the scripted opening would bury the answer — this
/// shows *everything*, in order. It is the other job: not "keep talking" but
/// "what did I say, and what did it tell me?". The questions are part of that.
///
/// Read-only. A chat reopened from history is a record; re-answering a question
/// inside one would quietly change the conversation the advice was based on.
///
/// [userId] is not needed: the chat is handed in whole, and RLS scopes the
/// message read to its owner. This is a pushed route, so it cannot reach
/// `SessionScope` — see `HistoryScreen`.
class ChatTranscriptScreen extends StatefulWidget {
  final Chat chat;

  const ChatTranscriptScreen({super.key, required this.chat});

  @override
  State<ChatTranscriptScreen> createState() => _ChatTranscriptScreenState();
}

class _ChatTranscriptScreenState extends State<ChatTranscriptScreen> {
  late final Future<List<Message>> _messages =
      Backend.data.fetchMessages(widget.chat.id);

  @override
  void initState() {
    super.initState();
    _backfillTitle();
  }

  /// Asks the API to finish closing this chat, if it never got that far.
  ///
  /// Titling and the memory merge run in a background task after the user
  /// leaves a chat, and the request that starts them can simply not arrive —
  /// the app was killed, the network was down, Render was cold. Without a
  /// second chance, that chat is untitled and outside the user's memory
  /// forever, silently.
  ///
  /// Opening one is the natural retry: the user is looking at the chat, the API
  /// skips whichever half already ran, and the work is bounded by their own
  /// tapping rather than by a loop.
  void _backfillTitle() {
    final chat = widget.chat;
    if (chat.title != null || chat.status != ChatStatus.completed) return;
    // Not awaited and not shown: the title lands on the next visit to history.
    // Blocking a transcript the user asked to read on a model call would be a
    // strange thing to do to them.
    completeChat(chat);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return AppBackground(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              screenWidth * 0.06,
              screenHeight * 0.02,
              screenWidth * 0.06,
              screenHeight * 0.015,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.only(right: screenWidth * 0.03),
                    child: Icon(
                      Icons.arrow_back,
                      size: screenWidth * 0.055,
                      color: AppTheme.textLight,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.chat.title ?? widget.chat.category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: screenWidth * 0.038,
                      color: AppTheme.textLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Message>>(
              future: _messages,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
                    child: ErrorBanner(message: snapshot.error.toString()),
                  );
                }

                final messages = snapshot.data!;
                if (messages.isEmpty) return const _NothingInIt();

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    screenWidth * 0.06,
                    0,
                    screenWidth * 0.06,
                    screenHeight * 0.03,
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          screenWidth * 0.1,
          0,
          screenWidth * 0.1,
          screenWidth * 0.2,
        ),
        child: Text(
          'This one never got started.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: screenWidth * 0.042,
            color: AppTheme.textLight,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// One turn, rendered by what kind of turn it was.
///
/// A question and its answer are one row in the database, so they are one widget
/// here: the question in the quiet type a label gets, the answer in the card
/// under it.
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
          answer: answer.isEmpty ? '(skipped)' : answer,
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

  const _QuestionAndAnswer({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.only(bottom: screenWidth * 0.045),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.isNotEmpty) ...[
            Text(
              question,
              style: TextStyle(
                fontSize: screenWidth * 0.034,
                color: AppTheme.textLight,
                height: 1.4,
              ),
            ),
            SizedBox(height: screenWidth * 0.015),
          ],
          Text(
            answer,
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              color: AppTheme.textDark,
              fontWeight: FontWeight.w600,
              height: 1.4,
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: screenWidth * 0.05),
      padding: EdgeInsets.all(screenWidth * 0.045),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: screenWidth * 0.038,
          color: Colors.white,
          height: 1.5,
        ),
      ),
    );
  }
}

class _Replied extends StatelessWidget {
  final String text;

  const _Replied({required this.text});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: screenWidth * 0.05),
      padding: EdgeInsets.all(screenWidth * 0.045),
      decoration: BoxDecoration(
        color: AppTheme.cardBg.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: screenWidth * 0.038,
          color: AppTheme.textOnCard,
          height: 1.5,
        ),
      ),
    );
  }
}

/// The advice, given the weight it had on the day.
///
/// It is the one turn someone comes back to read, so it is the one turn that
/// gets a heading and its steps — a transcript where the answer looked like
/// every other bubble would make them scroll for the thing they opened this to
/// find.
class _Advice extends StatelessWidget {
  final String text;
  final Map<String, dynamic> metadata;

  const _Advice({required this.text, required this.metadata});

  List<String> get _steps =>
      (metadata['next_steps'] as List? ?? const []).whereType<String>().toList();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final steps = _steps;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: screenWidth * 0.05),
      padding: EdgeInsets.all(screenWidth * 0.05),
      decoration: BoxDecoration(
        color: AppTheme.cardBg.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What I said',
            style: TextStyle(
              fontSize: screenWidth * 0.032,
              color: AppTheme.textLight,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          SizedBox(height: screenWidth * 0.03),
          Text(
            text,
            style: TextStyle(
              fontSize: screenWidth * 0.04,
              color: AppTheme.textOnCard,
              height: 1.6,
            ),
          ),
          if (steps.isNotEmpty) ...[
            SizedBox(height: screenWidth * 0.045),
            for (final step in steps)
              Padding(
                padding: EdgeInsets.only(bottom: screenWidth * 0.02),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: screenWidth * 0.015),
                      child: Container(
                        width: screenWidth * 0.015,
                        height: screenWidth * 0.015,
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.03),
                    Expanded(
                      child: Text(
                        step,
                        style: TextStyle(
                          fontSize: screenWidth * 0.036,
                          color: AppTheme.textOnCard,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
