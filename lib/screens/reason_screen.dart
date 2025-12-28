import 'package:flutter/material.dart';

class ReasonScreen extends StatefulWidget {
  const ReasonScreen({super.key});

  @override
  State<ReasonScreen> createState() => _ReasonScreenState();
}

class _ReasonScreenState extends State<ReasonScreen> {
  int selectedIndex = 2; // default selected: Feeling overwhelmed

  final List<Map<String, dynamic>> options = [
    {
      "icon": Icons.work_outline,
      "text": "Career confusion",
    },
    {
      "icon": Icons.merge_type,
      "text": "Stuck between choices",
    },
    {
      "icon": Icons.blur_on,
      "text": "Feeling overwhelmed",
    },
    {
      "icon": Icons.explore_outlined,
      "text": "Need clarity before a step",
    },
  ];

  @override
  Widget build(BuildContext context) {
    // Get screen size for responsive design
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Calculate responsive spacing
    final topPadding = screenHeight * 0.03;
    final horizontalPadding = screenWidth * 0.06;

    return Scaffold(
      body: Stack(
        children: [
          // 🔹 Background
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: topPadding),

                            // 🔹 Title - Responsive font size
                            Text(
                              "What brings you\nhere today?",
                              style: TextStyle(
                                fontSize: screenWidth * 0.08,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2E3A3F),
                                height: 1.2,
                                letterSpacing: -0.5,
                              ),
                            ),

                            SizedBox(height: screenHeight * 0.015),

                            // 🔹 Subtitle - Responsive font size
                            Text(
                              "Choose what best matches how you're\nfeeling right now.",
                              style: TextStyle(
                                fontSize: screenWidth * 0.038,
                                color: const Color(0xFF5F6F78),
                                height: 1.4,
                              ),
                            ),

                            SizedBox(height: screenHeight * 0.04),

                            // 🔹 Options list with flexible sizing
                            ...List.generate(options.length, (index) {
                              final isSelected = index == selectedIndex;

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    selectedIndex = index;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: EdgeInsets.only(
                                    bottom: screenHeight * 0.018,
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: screenWidth * 0.05,
                                    vertical: screenHeight * 0.02,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF9FB6C2)
                                        : const Color(0xFFF5F1E8)
                                            .withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      // Soft outer shadow for depth
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                        offset: const Offset(0, 4),
                                        blurRadius: 12,
                                        spreadRadius: 0,
                                      ),
                                      // Subtle inner highlight for texture
                                      BoxShadow(
                                        color: Colors.white.withValues(
                                          alpha: isSelected ? 0.1 : 0.4,
                                        ),
                                        offset: const Offset(0, -1),
                                        blurRadius: 2,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      // 🔹 Icon container with subtle background
                                      Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.white
                                                  .withValues(alpha: 0.15)
                                              : Colors.transparent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          options[index]["icon"],
                                          size: screenWidth * 0.06,
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0xFF3D4F56),
                                        ),
                                      ),
                                      SizedBox(width: screenWidth * 0.035),
                                      // 🔹 Text - Responsive and flexible
                                      Flexible(
                                        child: Text(
                                          options[index]["text"],
                                          style: TextStyle(
                                            fontSize: screenWidth * 0.042,
                                            color: isSelected
                                                ? Colors.white
                                                : const Color(0xFF3D4F56),
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.2,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),

                            // 🔹 Spacer with minimum height
                            SizedBox(height: screenHeight * 0.03),
                            const Spacer(),

                            // 🔹 Continue button with enhanced shadow
                            Center(
                              child: Container(
                                width: screenWidth * 0.65,
                                height: screenHeight * 0.065,
                                margin: EdgeInsets.only(
                                  bottom: screenHeight * 0.02,
                                ),
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
                                  onPressed: () {
                                    // TODO: Go to next flow (chat / analysis screen)
                                  },
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
                                  child: Text(
                                    "Continue",
                                    style: TextStyle(
                                      fontSize: screenWidth * 0.042,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(height: screenHeight * 0.02),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}