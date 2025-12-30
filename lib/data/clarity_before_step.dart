import '../models/question_model.dart';

final clarityQuestions = [
  Question(
    id: "step_type",
    text: "What step are you considering?",
    options: [
      "Starting something new",
      "Quitting/leaving something",
      "Making a big purchase",
      "Relationship decision",
      "Career move",
      "Life transition",
    ],
  ),
  Question(
    id: "clarity_needed",
    text: "What specifically do you need clarity on?",
    options: [
      "Whether to do it or not",
      "Timing of the step",
      "How to do it",
      "Consequences/outcomes",
      "Others' reactions",
      "My own readiness",
    ],
    multiSelect: true,
  ),
  Question(
    id: "hesitation_reason",
    text: "What's causing you to hesitate?",
    options: [
      "Fear of failure",
      "Fear of regret",
      "Lack of information",
      "Financial risk",
      "Others' opinions",
      "Self-doubt",
    ],
    multiSelect: true,
  ),
  Question(
    id: "information_gathered",
    text: "How prepared do you feel?",
    options: [
      "Very prepared, just need confidence",
      "Somewhat prepared",
      "Need more information",
      "Don't know where to start",
      "Completely unprepared",
    ],
  ),
  Question(
    id: "step_urgency",
    text: "How urgent is this decision?",
    options: [
      "Must decide now",
      "Within a week",
      "Within a month",
      "This year",
      "No rush, just thinking ahead",
    ],
  ),
];