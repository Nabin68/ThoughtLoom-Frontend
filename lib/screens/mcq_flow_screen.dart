import 'package:flutter/material.dart';
import '../models/question_model.dart';
import '../data/career_confusion.dart';
import '../data/stuck_between_choices.dart';
import '../data/overwhelmed.dart';
import '../data/clarity_before_step.dart';
import '../screens/reason_screen.dart'; // Import for ReasonType enum
import 'summary_input_screen.dart'; 

class MCQFlowScreen extends StatefulWidget {
  final ReasonType reason;

  const MCQFlowScreen({super.key, required this.reason});

  @override
  State<MCQFlowScreen> createState() => _MCQFlowScreenState();
}

class _MCQFlowScreenState extends State<MCQFlowScreen> {
  // Store user answers
  final Map<String, dynamic> answers = {};
  int currentIndex = 0;

  // Load questions based on reason
  List<Question> get questions {
    switch (widget.reason) {
      case ReasonType.careerConfusion:
        return careerConfusionQuestions;
      case ReasonType.stuckBetweenChoices:
        return stuckBetweenChoicesQuestions;
      case ReasonType.overwhelmed:
        return overwhelmedQuestions;
      case ReasonType.clarityBeforeStep:
        return clarityQuestions;
    }
  }

  Question get currentQuestion => questions[currentIndex];

  // Save answer
  void saveAnswer(dynamic value) {
    setState(() {
      answers[currentQuestion.id] = value;
    });
  }

  // Navigate to next question
  // Navigate to next question
void nextQuestion() {
  if (currentIndex < questions.length - 1) {
    setState(() {
      currentIndex++;
    });
  } else {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryInputScreen(
          reason: widget.reason,
          responses: answers,
        ),
      ),
    );
  }
}

  // Check if current question is answered
  bool get isAnswered {
    if (currentQuestion.multiSelect) {
      return answers[currentQuestion.id] != null &&
          (answers[currentQuestion.id] as List).isNotEmpty;
    }
    return answers[currentQuestion.id] != null;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Progress indicator
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: screenHeight * 0.02,
                  ),
                  child: Text(
                    'Step ${currentIndex + 1} of ${questions.length}',
                    style: TextStyle(
                      fontSize: screenWidth * 0.038,
                      color: const Color(0xFF5F6F78),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                
                // Main content
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: screenHeight * 0.02),
                          
                          // Question text
                          Text(
                            currentQuestion.text,
                            style: TextStyle(
                              fontSize: screenWidth * 0.065,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2E3A3F),
                              height: 1.3,
                              letterSpacing: -0.5,
                            ),
                          ),
                          
                          SizedBox(height: screenHeight * 0.04),
                          
                          // Options
                          if (currentQuestion.multiSelect)
                            _buildMultiSelectOptions()
                          else
                            _buildSingleSelectOptions(),
                          
                          SizedBox(height: screenHeight * 0.03),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Bottom button
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: screenHeight * 0.02,
                  ),
                  child: Container(
                    width: screenWidth * 0.65,
                    height: screenHeight * 0.065,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6F8F9B).withValues(alpha: 0.3),
                          offset: const Offset(0, 8),
                          blurRadius: 20,
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          offset: const Offset(0, 4),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: isAnswered ? nextQuestion : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAnswered
                            ? const Color(0xFF6F8F9B)
                            : const Color(0xFF6F8F9B).withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            currentIndex < questions.length - 1
                                ? "Continue"
                                : "See My Insight",
                            style: TextStyle(
                              fontSize: screenWidth * 0.042,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.02),
                          Icon(
                            Icons.arrow_forward,
                            size: screenWidth * 0.05,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Single select options (like first screen in image)
  Widget _buildSingleSelectOptions() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final selectedValue = answers[currentQuestion.id];

    return Column(
      children: currentQuestion.options.map((option) {
        final isSelected = selectedValue == option;
        
        return GestureDetector(
          onTap: () => saveAnswer(option),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            padding: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.05,
              vertical: screenHeight * 0.02,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF9FB6C2)
                  : const Color(0xFFF5F1E8).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Center(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: screenWidth * 0.042,
                  color: isSelected ? Colors.white : const Color(0xFF3D4F56),
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Multi-select options (like second screen in image)
  Widget _buildMultiSelectOptions() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    List<String> selectedValues =
        (answers[currentQuestion.id] as List<String>?) ?? [];

    return Column(
      children: currentQuestion.options.map((option) {
        final isSelected = selectedValues.contains(option);
        
        return GestureDetector(
          onTap: () {
            List<String> newValues = List.from(selectedValues);
            if (isSelected) {
              newValues.remove(option);
            } else {
              newValues.add(option);
            }
            saveAnswer(newValues);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.only(bottom: screenHeight * 0.015),
            padding: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.05,
              vertical: screenHeight * 0.02,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF9FB6C2)
                  : const Color(0xFFF5F1E8).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                // Circle indicator for multi-select
                Container(
                  width: screenWidth * 0.06,
                  height: screenWidth * 0.06,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.3)
                        : const Color(0xFF9FB6C2).withValues(alpha: 0.3),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF9FB6C2),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: screenWidth * 0.04,
                          color: Colors.white,
                        )
                      : null,
                ),
                SizedBox(width: screenWidth * 0.035),
                
                // Option text
                Expanded(
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: screenWidth * 0.042,
                      color: isSelected ? Colors.white : const Color(0xFF3D4F56),
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}