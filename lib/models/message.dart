//message.dart

enum MessageType {
  /// Fixed per-category MCQ from the scripted opening.
  intake('intake'),

  /// Follow-up the model wrote in response to this particular user.
  adaptiveQuestion('adaptive_question'),

  /// Anything the user typed or dictated of their own accord.
  freeText('free_text'),

  /// The model's actual advice. One per chat.
  recommendation('recommendation'),

  /// The model's turns in the conversation after the recommendation. Separate
  /// from [recommendation] so the advice itself stays findable in a chat that
  /// ran on afterwards.
  assistantReply('assistant_reply');

  const MessageType(this.wireValue);

  final String wireValue;

  static MessageType fromWire(String value) => values.firstWhere(
        (t) => t.wireValue == value,
        orElse: () => MessageType.freeText,
      );
}

/// One turn in a chat. A question-and-answer pair is a single row: [questionText]
/// is what was asked, [answerText] is what came back. Turns with no question
/// (free text, recommendations) leave [questionText] null.
class Message {
  final String id;
  final String chatId;
  final int seq;
  final MessageType type;
  final String? questionText;
  final String? answerText;

  /// Per-turn extras that shouldn't each cost a column: MCQ option lists,
  /// citations behind a recommendation, model name.
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.chatId,
    required this.seq,
    required this.type,
    this.questionText,
    this.answerText,
    this.metadata = const {},
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        chatId: json['chat_id'] as String,
        seq: json['seq'] as int,
        type: MessageType.fromWire(json['type'] as String),
        questionText: json['question_text'] as String?,
        answerText: json['answer_text'] as String?,
        metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat_id': chatId,
        'seq': seq,
        'type': type.wireValue,
        'question_text': questionText,
        'answer_text': answerText,
        'metadata': metadata,
      };

  Message copyWith({String? answerText, Map<String, dynamic>? metadata}) =>
      Message(
        id: id,
        chatId: chatId,
        seq: seq,
        type: type,
        questionText: questionText,
        answerText: answerText ?? this.answerText,
        metadata: metadata ?? this.metadata,
        createdAt: createdAt,
      );
}
