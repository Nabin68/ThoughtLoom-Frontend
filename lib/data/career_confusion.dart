import '../models/question_model.dart';

final careerConfusionQuestions = [
  Question(
    id: "current_status",
    text: "What are you currently doing?",
    options: [
      "Studying",
      "Working",
      "Studying + Working",
      "Preparing for something",
      "Taking a break",
    ],
  ),
  Question(
    id: "confusion_reason",
    text: "What exactly are you confused about?",
    options: [
      "Choosing between options",
      "Fear of social opinion",
      "Family pressure",
      "Self-doubt",
      "Career change",
      "Higher studies",
    ],
    multiSelect: true,
  ),
  Question(
    id: "career_stage",
    text: "Where are you in your career journey?",
    options: [
      "Just starting out",
      "Early career (0-3 years)",
      "Mid career (3-7 years)",
      "Experienced (7+ years)",
      "Considering a switch",
    ],
  ),
  Question(
    id: "confusion_intensity",
    text: "How long have you felt this confusion?",
    options: [
      "Few days",
      "Few weeks",
      "Few months",
      "More than 6 months",
      "Over a year",
    ],
  ),
  Question(
    id: "external_pressure",
    text: "Are you facing pressure from others?",
    options: [
      "Yes, a lot",
      "Somewhat",
      "A little",
      "Not really",
      "No external pressure",
    ],
  ),
];