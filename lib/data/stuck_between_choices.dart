import '../models/question_model.dart';

final stuckBetweenChoicesQuestions = [
  Question(
    id: "decision_type",
    text: "What kind of decision are you facing?",
    options: [
      "Career path",
      "Job offer",
      "Education/Course",
      "Relocation",
      "Business/Startup",
      "Personal life",
    ],
  ),
  Question(
    id: "number_of_options",
    text: "How many options are you considering?",
    options: [
      "2 options",
      "3 options",
      "4 or more options",
      "Too many to count",
    ],
  ),
  Question(
    id: "decision_factors",
    text: "What factors are making this difficult?",
    options: [
      "All options seem equally good",
      "Fear of choosing wrong",
      "Conflicting priorities",
      "Others' expectations",
      "Financial concerns",
      "Time pressure",
    ],
    multiSelect: true,
  ),
  Question(
    id: "decision_deadline",
    text: "How soon do you need to decide?",
    options: [
      "Immediately",
      "Within a week",
      "Within a month",
      "Within 3 months",
      "No specific deadline",
    ],
  ),
  Question(
    id: "research_done",
    text: "How much have you researched your options?",
    options: [
      "Haven't started yet",
      "Some basic research",
      "Moderate research",
      "Extensive research",
      "Analyzed everything possible",
    ],
  ),
];