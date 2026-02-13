// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class InsightScreen extends StatelessWidget {
  final Map<String, dynamic> result;

  const InsightScreen({super.key, required this.result});

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
                        onPressed: () {
                          Navigator.popUntil(context, (r) => r.isFirst);
                        },
                      ),
                      const Spacer(),
                      Text(
                        "Your Insights",
                        style: TextStyle(
                          fontSize: screenWidth * 0.05,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2E3A3F),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(width: screenWidth * 0.12),
                    ],
                  ),
                ),

                // Content
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

                          // Summary Section
                          _buildSectionCard(
                            context: context,
                            title: "Summary",
                            icon: Icons.psychology_outlined,
                            child: Text(
                              result['summary'] ?? 'No summary available',
                              style: TextStyle(
                                fontSize: screenWidth * 0.04,
                                color: const Color(0xFF3D4F56),
                                height: 1.6,
                              ),
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.025),

                          // Insights Section
                          Text(
                            "Key Insights",
                            style: TextStyle(
                              fontSize: screenWidth * 0.055,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF2E3A3F),
                              letterSpacing: -0.5,
                            ),
                          ),

                          SizedBox(height: screenHeight * 0.015),

                          // Insight Cards
                          ...(_buildInsightCards(context)),

                          SizedBox(height: screenHeight * 0.03),
                        ],
                      ),
                    ),
                  ),
                ),

                // Start Over Button
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
                          color: const Color(0xFF6F8F9B).withOpacity(0.3),
                          offset: const Offset(0, 8),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.popUntil(context, (r) => r.isFirst);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6F8F9B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.refresh, size: 20),
                          SizedBox(width: screenWidth * 0.02),
                          Text(
                            "Start Over",
                            style: TextStyle(
                              fontSize: screenWidth * 0.042,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
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

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.045),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8).withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6F8F9B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF6F8F9B),
                  size: screenWidth * 0.06,
                ),
              ),
              SizedBox(width: screenWidth * 0.03),
              Text(
                title,
                style: TextStyle(
                  fontSize: screenWidth * 0.05,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2E3A3F),
                ),
              ),
            ],
          ),
          SizedBox(height: screenWidth * 0.04),
          child,
        ],
      ),
    );
  }

  List<Widget> _buildInsightCards(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    final insights = result['insights'] as List<dynamic>? ?? [];
    
    if (insights.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F1E8).withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Text('No insights available'),
        ),
      ];
    }

    return List.generate(insights.length, (index) {
      final insight = insights[index];
      
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(screenWidth * 0.045),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F1E8).withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Insight Number Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6F8F9B),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "Insight ${index + 1}",
                    style: TextStyle(
                      fontSize: screenWidth * 0.032,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                SizedBox(height: screenWidth * 0.03),

                // Title
                Text(
                  insight['title'] ?? 'Insight',
                  style: TextStyle(
                    fontSize: screenWidth * 0.048,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2E3A3F),
                    height: 1.3,
                  ),
                ),

                SizedBox(height: screenWidth * 0.025),

                // Explanation
                Text(
                  insight['explanation'] ?? '',
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    color: const Color(0xFF5F6F78),
                    height: 1.6,
                  ),
                ),

                SizedBox(height: screenWidth * 0.04),

                // Next Steps
                if (insight['next_steps'] != null && 
                    (insight['next_steps'] as List).isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: const Color(0xFF6F8F9B),
                        size: screenWidth * 0.05,
                      ),
                      SizedBox(width: screenWidth * 0.02),
                      Text(
                        "Next Steps",
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2E3A3F),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: screenWidth * 0.02),
                  ...(insight['next_steps'] as List).map((step) => Padding(
                        padding: EdgeInsets.only(
                          left: screenWidth * 0.02,
                          bottom: screenWidth * 0.015,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "• ",
                              style: TextStyle(
                                fontSize: screenWidth * 0.038,
                                color: const Color(0xFF6F8F9B),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                step,
                                style: TextStyle(
                                  fontSize: screenWidth * 0.038,
                                  color: const Color(0xFF5F6F78),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  SizedBox(height: screenWidth * 0.03),
                ],

                // Caution
                if (insight['caution'] != null && 
                    insight['caution'].toString().isNotEmpty) ...[
                  Container(
                    padding: EdgeInsets.all(screenWidth * 0.035),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFFD700).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: const Color(0xFFD97706),
                          size: screenWidth * 0.05,
                        ),
                        SizedBox(width: screenWidth * 0.025),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Keep in Mind",
                                style: TextStyle(
                                  fontSize: screenWidth * 0.038,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFD97706),
                                ),
                              ),
                              SizedBox(height: screenWidth * 0.01),
                              Text(
                                insight['caution'],
                                style: TextStyle(
                                  fontSize: screenWidth * 0.035,
                                  color: const Color(0xFF92400E),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (index < insights.length - 1) 
            SizedBox(height: screenHeight * 0.02),
        ],
      );
    });
  }
}