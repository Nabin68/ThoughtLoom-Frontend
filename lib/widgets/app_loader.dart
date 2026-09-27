//app_loader.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import '../theme/app_theme.dart';

/// The app's loading animation.
///
/// Two arcs on a faint track — the sage over the tan, the app's two brand
/// colours and nothing new — turning against each other while the outer sweep
/// breathes open and closed. No assets, no package: one `AnimationController`
/// driving a `CustomPainter` through `repaint`, so nothing above it rebuilds
/// and a wait costs a repaint of one small box per frame.
///
/// ### Why not `CircularProgressIndicator`
///
/// Material's spinner is a fixed arc at a fixed speed, and the eye stops seeing
/// it within a second or two — which is the wrong instrument for this app,
/// where a wait can legitimately be a minute behind a Render cold start. The
/// breathing sweep is the whole trick: it changes shape, so a long wait keeps
/// reading as *working* rather than as a frame that got stuck.
class AppLoader extends StatefulWidget {
  /// The box the arcs are drawn in. The inner arc is dropped below 24 so that
  /// the small sizes — inside a button, beside a "Thinking..." bubble — stay
  /// two clean strokes rather than a smudge.
  final double size;

  /// Both arcs in one colour, for the places the sage would disappear — the
  /// white-on-sage primary button, chiefly. Defaults to the brand pair.
  final Color? color;

  const AppLoader({super.key, this.size = 34, this.color});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.color;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _LoomPainter(
          progress: _controller,
          arc: tint ?? AppTheme.primary,
          // The tan reads as a quiet second thread against the sage. Given one
          // colour to work with, the inner arc is the same colour held back,
          // which keeps the two strokes distinguishable on a sage button.
          innerArc: tint?.withValues(alpha: 0.45) ?? AppTheme.accent,
          track: tint?.withValues(alpha: 0.18) ?? AppTheme.border,
        ),
      ),
    );
  }
}

class _LoomPainter extends CustomPainter {
  final Animation<double> progress;
  final Color arc;
  final Color innerArc;
  final Color track;

  /// `repaint: progress` rather than a rebuild: the painter is listening to the
  /// controller directly, so no widget in the tree rebuilds per frame.
  _LoomPainter({
    required this.progress,
    required this.arc,
    required this.innerArc,
    required this.track,
  }) : super(repaint: progress);

  static const _turn = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final extent = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = (extent * 0.085).clamp(2.0, 3.6);
    final radius = extent / 2 - stroke / 2;
    if (radius <= 0) return;

    Paint pen(Color colour) => Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, pen(track));

    // 0 -> 1 -> 0 across one turn. The outer sweep opens and closes with it,
    // never reaching zero, so the arc is always visible.
    final breath = (1 - math.cos(t * _turn)) / 2;
    final sweep = (0.3 + 0.95 * breath) * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      t * _turn - math.pi / 2,
      sweep,
      false,
      pen(arc),
    );

    // Below this the two strokes would touch and read as one thick smudge.
    if (extent < 24) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.56),
      // Counter-rotating, and not at a whole multiple of the outer speed, so
      // the two never settle into a pattern the eye can predict.
      -t * _turn * 1.45 - math.pi / 2,
      math.pi * 0.62,
      false,
      pen(innerArc),
    );
  }

  @override
  bool shouldRepaint(_LoomPainter old) =>
      old.arc != arc || old.innerArc != innerArc || old.track != track;
}

/// A full-screen wait: the loader, and a line of copy that changes.
///
/// One widget for every long wait in the app, because they are all the same
/// wait — a model call, possibly behind a sleeping Render instance — and three
/// screens were each keeping their own `Timer` to say so.
///
/// ### The warm-up line
///
/// While [backendWarm] is false the backend has not yet answered, which on the
/// free tier means it is still booting. That is a different thing from "the
/// model is thinking", takes a different amount of time, and is worth saying
/// out loud: a wait you have been told the reason for is a much shorter wait
/// than a silent one. The moment it answers, the copy switches to whatever the
/// screen wanted to say.
class AppWaiting extends StatefulWidget {
  /// Shown in order, one at a time, once the backend is awake.
  final List<String> lines;

  /// How long each line stays up.
  final Duration interval;

  final double size;

  /// Emphasised copy, for the screen whose whole job is the wait.
  final bool prominent;

  const AppWaiting({
    super.key,
    required this.lines,
    this.interval = const Duration(seconds: 4),
    this.size = 34,
    this.prominent = false,
  });

  @override
  State<AppWaiting> createState() => _AppWaitingState();
}

class _AppWaitingState extends State<AppWaiting> {
  static const _waking = 'Waking the server up — it naps between chats...';

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _index = _index + 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.s8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppLoader(size: widget.size),
            SizedBox(height: widget.prominent ? AppTheme.s6 : AppTheme.s5),
            ValueListenableBuilder<bool>(
              valueListenable: backendWarm,
              builder: (context, warm, _) {
                // Not a rotating line: while the server is waking there is
                // exactly one true thing to say, and cycling through cheerful
                // alternatives would be inventing progress.
                final text = warm
                    ? widget.lines[_index % widget.lines.length]
                    : _waking;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Text(
                    text,
                    key: ValueKey(text),
                    textAlign: TextAlign.center,
                    style: widget.prominent
                        ? AppTheme.body(context).copyWith(
                            color: AppTheme.textDark,
                            fontWeight: FontWeight.w600,
                          )
                        : AppTheme.secondary(context),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
