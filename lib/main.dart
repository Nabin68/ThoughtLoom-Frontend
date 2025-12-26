import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "ThoughtLoom",
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          children: [
            // 🔹 Background image
            Positioned.fill(
              child: Image.asset(
                'assets/background.png',
                fit: BoxFit.cover,
              ),
            ),

            // 🔹 Foreground content
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // 🔹 Logo
                  Image.asset(
                    'assets/logo.png',
                    height: 80, // adjust if needed
                  ),

                const SizedBox(height: 16),
                  // App name
                  const Text(
                    "ThoughtLoom",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E3A3F),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Tagline
                  const Text(
                    "Weave clarity into your decisions.",
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF5F6F78),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 4),

                  // Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6F8F9B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 6,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Start Thinking Clearly",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}