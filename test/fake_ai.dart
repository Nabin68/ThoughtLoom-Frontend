import 'package:thoughtloom/services/ai_service.dart';

/// A stand-in for the FastAPI service.
///
/// Shared rather than defined per suite: it implements an interface, so a
/// second copy would be a second place to remember when that interface grows —
/// and the compiler only complains once you have already forgotten.
///
/// The model itself is the API's problem and is tested there. What these fakes
/// support testing is the client's half of the contract: that an answer goes
/// back with the id it belongs to, that a failure offers a retry instead of
/// losing the conversation, and that leaving a chat closes it.
class FakeAi implements AiService {
  final List<AdaptiveTurn> turns;
  Recommendation? recommendation_;
  String reply = 'Then do not do it.';

  /// Queued failures, thrown one per call.
  final List<AiFailure> failures = [];

  final List<Map<String, String?>> answersSent = [];
  int followUpCalls = 0;

  /// Chats this was asked to close. The screens fire this without awaiting it,
  /// so a test that reads it has to pump first.
  final List<String> completed = [];

  FakeAi({this.turns = const []});

  void _maybeFail() {
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }

  int _turn = 0;

  @override
  Future<AdaptiveTurn> nextQuestion({
    required String chatId,
    String? answerToMessageId,
    String? answer,
  }) async {
    if (answer != null) {
      answersSent.add({'id': answerToMessageId, 'text': answer});
    }
    _maybeFail();
    if (_turn >= turns.length) {
      return const AdaptiveTurn(done: true, round: 0);
    }
    return turns[_turn++];
  }

  @override
  Future<Recommendation> recommendation({required String chatId}) async {
    _maybeFail();
    return recommendation_ ??
        const Recommendation(
          text: 'Finish the degree, but stop pretending it is the point.',
          nextSteps: ['Talk to your head of department'],
          confidence: 'Fairly sure.',
        );
  }

  @override
  Future<String> followUp({
    required String chatId,
    required String message,
  }) async {
    followUpCalls++;
    _maybeFail();
    return reply;
  }

  @override
  Future<void> completeChat({required String chatId}) async {
    completed.add(chatId);
    _maybeFail();
  }
}
