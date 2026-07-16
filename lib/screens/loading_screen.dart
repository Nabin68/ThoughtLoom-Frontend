import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../config/api_config.dart';
import 'insight_screen.dart';

class LoadingScreen extends StatefulWidget {
  final Map<String, dynamic> payload;

  const LoadingScreen({super.key, required this.payload});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  int _currentMessageIndex = 0;
  Timer? _messageTimer;

  final List<String> _loadingMessages = [
    "Weaving your thoughts...",
    "Understanding your situation...",
    "Analyzing patterns...",
    "Connecting the dots...",
    "Crafting personalized insights...",
    "Almost there...",
  ];

  @override
  void initState() {
    super.initState();
    _startMessageRotation();
    _callAPI();
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  void _startMessageRotation() {
    _messageTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _currentMessageIndex = (_currentMessageIndex + 1) % _loadingMessages.length;
        });
      }
    });
  }

  Future<void> _callAPI() async {
    try {
      final response = await http
          .post(
            ApiConfig.analyzeUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(widget.payload),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      if (response.statusCode != 200) {
        debugPrint('Analyze failed: ${response.statusCode} ${response.body}');
        _showError(
          "ThoughtLoom couldn't work through this one. Please try again.",
        );
        return;
      }

      final result = jsonDecode(response.body);

      // Small delay to ensure user sees the loading animation
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => InsightScreen(
            result: result,
          ),
        ),
      );
    } on TimeoutException {
      _showError("This is taking longer than usual. Please try again.");
    } catch (e) {
      debugPrint('Analyze request failed: $e');
      _showError("We couldn't reach ThoughtLoom. Check your connection and try again.");
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),
          
          // Content
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  SizedBox(
                    width: screenWidth * 0.25,
                    height: screenWidth * 0.25,
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.06),

                  // App name
                  Text(
                    "ThoughtLoom",
                    style: TextStyle(
                      fontSize: screenWidth * 0.08,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2E3A3F),
                      letterSpacing: -0.5,
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.02),

                  // Animated message
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.3),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      _loadingMessages[_currentMessageIndex],
                      key: ValueKey<int>(_currentMessageIndex),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.045,
                        color: const Color(0xFF5F6F78),
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  SizedBox(height: screenHeight * 0.04),

                  // Loading indicator
                  SizedBox(
                    width: screenWidth * 0.15,
                    height: screenWidth * 0.15,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF6F8F9B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}