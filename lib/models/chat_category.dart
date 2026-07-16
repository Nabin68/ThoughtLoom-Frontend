//chat_category.dart

/// The life area a chat is about. Wire values match the `chat_category` enum
/// in supabase/schema.sql — changing one without the other breaks writes.
enum ChatCategory {
  education('education', 'Education'),
  financial('financial', 'Financial'),
  relationship('relationship', 'Relationship'),
  other('other', 'Other');

  const ChatCategory(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static ChatCategory fromWire(String value) => values.firstWhere(
        (c) => c.wireValue == value,
        orElse: () => ChatCategory.other,
      );
}
