//app_background.dart

import 'package:flutter/material.dart';

/// The full-bleed background every screen sits on.
///
/// ### The veil
///
/// The artwork is drawn as a frame: ribbons crowd the top and bottom and leave
/// the middle clean. Cards are opaque and sit over it happily, but a screen's
/// *heading* is bare text at the top — exactly where the ribbons are densest —
/// and secondary text there is a light grey crossing a tan line. It is readable
/// and it is busy, and busy behind the first thing you read is a large part of
/// what "the UI is confusing" turns out to mean.
///
/// So a cream veil sits between the artwork and the content. At 0.35 the ribbons
/// still read plainly as the app's face; they simply stop competing with the
/// sentence on top of them. One number, if it ever wants tuning.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/background.png', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0xFFF7F5F0).withValues(alpha: 0.35),
              ),
            ),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}
