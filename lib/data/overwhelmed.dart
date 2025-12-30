import '../models/question_model.dart';

final overwhelmedQuestions = [
  Question(
    id: "overwhelm_source",
    text: "What's making you feel overwhelmed?",
    options: [
      "Too many responsibilities",
      "Life changes",
      "Work/Study pressure",
      "Relationship issues",
      "Financial stress",
      "Health concerns",
    ],
    multiSelect: true,
  ),
  Question(
    id: "overwhelm_duration",
    text: "How long have you been feeling this way?",
    options: [
      "Just today",
      "Few days",
      "Few weeks",
      "Few months",
      "Longer than 6 months",
    ],
  ),
  Question(
    id: "daily_impact",
    text: "How is this affecting your daily life?",
    options: [
      "Can't focus on anything",
      "Struggling with tasks",
      "Manageable but uncomfortable",
      "Occasional difficulty",
      "Minor impact",
    ],
  ),
  Question(
    id: "support_system",
    text: "Do you have people you can talk to?",
    options: [
      "Yes, strong support",
      "Few people",
      "One person",
      "Not really",
      "No one to talk to",
    ],
  ),
  Question(
    id: "coping_attempts",
    text: "What have you tried to manage this?",
    options: [
      "Taking breaks",
      "Talking to someone",
      "Exercise/meditation",
      "Planning/organizing",
      "Nothing yet",
      "Avoiding the situation",
    ],
    multiSelect: true,
  ),
];