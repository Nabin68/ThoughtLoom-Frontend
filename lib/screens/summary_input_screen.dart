import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../screens/reason_screen.dart'; // Import for ReasonType enum

class SummaryInputScreen extends StatefulWidget {
  final ReasonType reason;
  final Map<String, dynamic> responses;

  const SummaryInputScreen({
    super.key,
    required this.reason,
    required this.responses,
  });

  @override
  State<SummaryInputScreen> createState() => _SummaryInputScreenState();
}

class _SummaryInputScreenState extends State<SummaryInputScreen> {
  final TextEditingController controller = TextEditingController();
  bool isSubmitting = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  // Prepare final payload for LLM
  Map<String, dynamic> get finalPayload {
    return {
      "reason": widget.reason.name,
      "mcq_answers": widget.responses,
      "additional_context": controller.text.trim(),
    };
  }

  // Send data to FastAPI backend
  Future<void> submitToLLM() async {
    if (controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please share a bit about your situation'),
          backgroundColor: Color(0xFF6F8F9B),
        ),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      // 🔥 Replace with your actual FastAPI endpoint
      const String apiUrl = 'http://localhost:8000/api/analyze';
      // For Android emulator use: http://10.0.2.2:8000/api/analyze
      // For real device use your computer's IP: http://192.168.x.x:8000/api/analyze

      debugPrint('=== SENDING TO API ===');
      debugPrint('URL: $apiUrl');
      debugPrint('Payload: ${jsonEncode(finalPayload)}');
      debugPrint('=====================');

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(finalPayload),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        debugPrint('=== API RESPONSE ===');
        debugPrint(result.toString());
        debugPrint('===================');

        // TODO: Navigate to InsightScreen with result
        // Navigator.pushReplacement(
        //   context,
        //   MaterialPageRoute(
        //     builder: (_) => InsightScreen(result: result),
        //   ),
        // );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Analysis complete! Processing insights...'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('=== ERROR ===');
      debugPrint(e.toString());
      debugPrint('=============');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
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
                // Header
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: screenHeight * 0.02,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        color: const Color(0xFF3D4F56),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
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
                          SizedBox(height: screenHeight * 0.01),

                          // Title
                          Text(
                            "Tell us more about\nyour situation",
                            style: TextStyle(
                              fontSize: screenWidth * 0.08,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2E3A3F),
                              height: 1.2,
                              letterSpacing: -0.5,
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.015),

                          // Subtitle
                          Text(
                            "Share any additional details that might\nhelp us understand you better.",
                            style: TextStyle(
                              fontSize: screenWidth * 0.038,
                              color: const Color(0xFF5F6F78),
                              height: 1.4,
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.04),

                          // Text input field
                          Container(
                            constraints: BoxConstraints(
                              minHeight: screenHeight * 0.25,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F1E8)
                                  .withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  offset: const Offset(0, 4),
                                  blurRadius: 12,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: controller,
                              maxLines: null,
                              minLines: 8,
                              style: TextStyle(
                                fontSize: screenWidth * 0.042,
                                color: const Color(0xFF3D4F56),
                                height: 1.5,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    "I feel stuck because everyone expects me to choose engineering, but I'm more interested in...",
                                hintStyle: TextStyle(
                                  fontSize: screenWidth * 0.04,
                                  color: const Color(0xFF5F6F78)
                                      .withValues(alpha: 0.5),
                                  height: 1.5,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: screenWidth * 0.05,
                                  vertical: screenHeight * 0.025,
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.02),

                          // Character count / helpful tip
                          Text(
                            "💡 The more you share, the better we can help",
                            style: TextStyle(
                              fontSize: screenWidth * 0.035,
                              color: const Color(0xFF5F6F78),
                              fontStyle: FontStyle.italic,
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.03),
                        ],
                      ),
                    ),
                  ),
                ),

                // Submit button
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
                          color: const Color(0xFF6F8F9B)
                              .withValues(alpha: 0.3),
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
                      onPressed: isSubmitting ? null : submitToLLM,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6F8F9B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                      ),
                      child: isSubmitting
                          ? SizedBox(
                              width: screenWidth * 0.05,
                              height: screenWidth * 0.05,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Get My Insights",
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
}