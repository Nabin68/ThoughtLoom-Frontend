//user_memory.dart

import 'chat_category.dart';

/// Durable facts carried across chats, so a session months from now starts
/// warm instead of cold.
///
/// A null [category] is the global row: things true of the user regardless of
/// topic. A non-null one scopes memory to a single life area, which keeps a
/// financial chat from surfacing relationship history.
class UserMemory {
  final String id;
  final String userId;
  final ChatCategory? category;

  /// Prose the model reads back as context.
  final String summary;

  /// Discrete facts, kept alongside [summary] so they can be revised or dropped
  /// individually rather than by rewriting the prose.
  final List<dynamic> facts;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserMemory({
    required this.id,
    required this.userId,
    this.category,
    this.summary = '',
    this.facts = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isGlobal => category == null;

  factory UserMemory.fromJson(Map<String, dynamic> json) => UserMemory(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        category: json['category'] == null
            ? null
            : ChatCategory.fromWire(json['category'] as String),
        summary: json['summary'] as String? ?? '',
        facts: List<dynamic>.from(json['facts'] as List? ?? const []),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'category': category?.wireValue,
        'summary': summary,
        'facts': facts,
      };

  UserMemory copyWith({String? summary, List<dynamic>? facts}) => UserMemory(
        id: id,
        userId: userId,
        category: category,
        summary: summary ?? this.summary,
        facts: facts ?? this.facts,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );
}
