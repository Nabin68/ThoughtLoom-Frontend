//chat.dart

import 'chat_category.dart';

enum ChatStatus {
  inProgress('in_progress'),

  /// The recommendation has landed and the user can still push back. Set by the
  /// backend when it writes the advice; only leaving the chat completes it.
  awaitingFollowUp('awaiting_follow_up'),
  completed('completed');

  const ChatStatus(this.wireValue);

  final String wireValue;

  static ChatStatus fromWire(String value) => values.firstWhere(
        (s) => s.wireValue == value,
        orElse: () => ChatStatus.inProgress,
      );
}

/// One topic session. [title] stays null until the auto-titler names it.
class Chat {
  final String id;
  final String userId;
  final ChatCategory category;
  final String? title;
  final ChatStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Chat({
    required this.id,
    required this.userId,
    required this.category,
    this.title,
    this.status = ChatStatus.inProgress,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Chat.fromJson(Map<String, dynamic> json) => Chat(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        category: ChatCategory.fromWire(json['category'] as String),
        title: json['title'] as String?,
        status: ChatStatus.fromWire(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'category': category.wireValue,
        'title': title,
        'status': status.wireValue,
      };

  Chat copyWith({String? title, ChatStatus? status}) => Chat(
        id: id,
        userId: userId,
        category: category,
        title: title ?? this.title,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
}
