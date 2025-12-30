class Question {
  final String id;
  final String text;
  final List<String> options;
  final bool multiSelect;

  Question({
    required this.id,
    required this.text,
    required this.options,
    this.multiSelect = false,
  });
}