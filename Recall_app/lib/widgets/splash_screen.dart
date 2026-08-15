import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const Duration _kSplashDuration = Duration(milliseconds: 2400);
const Duration _kReducedMotionDuration = Duration(milliseconds: 900);

/// Keeps the main page alive underneath the launch layer while the animation
/// is playing. The [SplashScreen] is removed as soon as its timeline ends.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _motionReduced = false;
  bool _started = false;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _kSplashDuration)
      ..addStatusListener(_handleAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;

    _motionReduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _controller.duration = _motionReduced
        ? _kReducedMotionDuration
        : _kSplashDuration;
    _started = true;
    _controller.forward();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _showSplash = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final pageProgress = _motionReduced
            ? _segment(_controller.value, 0.62, 1, Curves.easeOutCubic)
            : _segment(_controller.value, 0.875, 1, Curves.easeOutCubic);

        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: _showSplash,
              child: ExcludeSemantics(
                excluding: _showSplash,
                child: Opacity(
                  opacity: pageProgress,
                  child: Transform.scale(
                    scale: ui.lerpDouble(0.99, 1, pageProgress)!,
                    child: child,
                  ),
                ),
              ),
            ),
            if (_showSplash)
              Positioned.fill(
                child: SplashScreen(
                  animation: _controller,
                  motionReduced: _motionReduced,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The visual launch layer. It intentionally has no app or data concerns;
/// the page behind it can initialize normally while this timeline runs.
class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    required this.animation,
    required this.motionReduced,
  });

  final Animation<double> animation;
  final bool motionReduced;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final value = animation.value;
          final fadeOut = motionReduced
              ? _segment(value, 0.62, 1, Curves.easeInOutCubic)
              : _segment(value, 0.875, 1, Curves.easeInOutCubic);
          final dotIn = _segment(value, 0, 0.17, Curves.easeOutCubic);
          final dotOut = _segment(value, 0.42, 0.7, Curves.easeInCubic);
          final dotOpacity = motionReduced ? 0.0 : dotIn * (1 - dotOut);
          final dotScale = ui.lerpDouble(0.3, 1, dotIn)!;
          final dotSize = ui.lerpDouble(7, 15, dotIn)!;

          final orbitIn = _segment(value, 0.16, 0.34, Curves.easeOutCubic);
          final orbitOut = _segment(value, 0.42, 0.69, Curves.easeInOutCubic);
          final orbitOpacity = motionReduced ? 0.0 : orbitIn * (1 - orbitOut);
          final orbitScale = motionReduced
              ? 0.4
              : ui.lerpDouble(0.42, 1, orbitIn)! *
                    ui.lerpDouble(1, 0.42, orbitOut)!;
          final orbitRotation = motionReduced
              ? 0.0
              : ui.lerpDouble(-0.35, math.pi * 1.12, orbitIn)! +
                    ui.lerpDouble(0, math.pi * 0.42, orbitOut)!;
          final orbitBlur = motionReduced
              ? 0.0
              : ui.lerpDouble(4.5, 0.45, orbitIn)!;

          final logoIn = motionReduced
              ? _segment(value, 0, 0.45, Curves.easeOutCubic)
              : _segment(value, 0.417, 0.667, Curves.easeOutCubic);
          final logoOpacity = logoIn;
          final logoScale = motionReduced
              ? ui.lerpDouble(0.92, 1, logoIn)!
              : value < 0.667
              ? ui.lerpDouble(0.8, 1.04, logoIn)!
              : ui.lerpDouble(
                  1.04,
                  1,
                  _segment(value, 0.667, 0.875, Curves.easeOutCubic),
                )!;
          final logoBlur = motionReduced
              ? ui.lerpDouble(2, 0, logoIn)!
              : ui.lerpDouble(4, 0.2, logoIn)!;
          final textIn = motionReduced
              ? _segment(value, 0.28, 0.58, Curves.easeOutCubic)
              : _segment(value, 0.667, 0.875, Curves.easeOutCubic);
          final textOffset = ui.lerpDouble(8, 0, textIn)!;

          final particlesIn = _segment(value, 0.28, 0.48, Curves.easeOutCubic);
          final particlesOut = _segment(value, 0.6, 0.86, Curves.easeInCubic);
          final particlesOpacity = motionReduced
              ? 0.0
              : particlesIn * (1 - particlesOut) * 0.72;
          final particleProgress = _segment(
            value,
            0.28,
            0.78,
            Curves.easeOutCubic,
          );

          return Opacity(
            opacity: 1 - fadeOut,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shortestSide = math.min(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final orbitSize = _clampDouble(shortestSide * 0.68, 210, 320);
                final markSize = _clampDouble(shortestSide * 0.18, 58, 84);
                final centerBlockHeight = orbitSize + 78;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const BackgroundDecoration(),
                    CustomPaint(
                      painter: _ParticlePainter(
                        progress: particleProgress,
                        opacity: particlesOpacity,
                        radius: orbitSize * 0.44,
                      ),
                      child: const SizedBox.expand(),
                    ),
                    Align(
                      alignment: const Alignment(0, -0.08),
                      child: SizedBox(
                        width: orbitSize,
                        height: centerBlockHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          fit: StackFit.expand,
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: orbitSize,
                              child: Center(
                                child: Opacity(
                                  opacity: orbitOpacity,
                                  child: Transform.rotate(
                                    angle: orbitRotation,
                                    child: Transform.scale(
                                      scale: orbitScale,
                                      child: ImageFiltered(
                                        imageFilter: ui.ImageFilter.blur(
                                          sigmaX: orbitBlur,
                                          sigmaY: orbitBlur,
                                        ),
                                        child: OrbitShape(
                                          size: orbitSize,
                                          morphProgress: orbitOut,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: orbitSize,
                                  height: orbitSize,
                                  child: Center(
                                    child: Transform.scale(
                                      scale: dotScale,
                                      child: Opacity(
                                        opacity: dotOpacity,
                                        child: GlowDot(size: dotSize),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: (orbitSize - markSize) / 2,
                              left: 0,
                              right: 0,
                              child: LogoReveal(
                                markSize: markSize,
                                markOpacity: logoOpacity,
                                markScale: logoScale,
                                markBlur: logoBlur,
                                textOpacity: textIn,
                                textOffset: textOffset,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class GlowDot extends StatelessWidget {
  const GlowDot({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF477CF1), Color(0xFF1BC6B2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF36BFC7).withValues(alpha: 0.35),
            blurRadius: 9,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class OrbitShape extends StatelessWidget {
  const OrbitShape({
    super.key,
    required this.size,
    required this.morphProgress,
  });

  final double size;
  final double morphProgress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _OrbitPainter(morphProgress: morphProgress),
    );
  }
}

class LogoReveal extends StatelessWidget {
  const LogoReveal({
    super.key,
    required this.markSize,
    required this.markOpacity,
    required this.markScale,
    required this.markBlur,
    required this.textOpacity,
    required this.textOffset,
  });

  final double markSize;
  final double markOpacity;
  final double markScale;
  final double markBlur;
  final double textOpacity;
  final double textOffset;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: markOpacity,
          child: Transform.scale(
            scale: markScale,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: markBlur,
                sigmaY: markBlur,
              ),
              child: RecallLogoMark(size: markSize),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Opacity(
          opacity: textOpacity,
          child: Transform.translate(
            offset: Offset(0, textOffset),
            child: Text(
              'Recall',
              style: TextStyle(
                color: const Color(0xFF223B52),
                fontSize: _clampDouble(markSize * 0.24, 16, 21),
                fontWeight: FontWeight.w600,
                letterSpacing: 2.2,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Placeholder mark used because the project currently has no Recall logo
/// asset. Add the real asset at this path and replace this widget in one place.
class RecallLogoMark extends StatelessWidget {
  const RecallLogoMark({super.key, required this.size});

  static const String assetPath = 'assets/branding/recall_logo.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFF3D6FEA), Color(0xFF15BBAE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bounds),
        child: Text(
          'R',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: size * 0.9,
            fontWeight: FontWeight.w700,
            height: 0.92,
          ),
        ),
      ),
    );
  }
}

class BackgroundDecoration extends StatelessWidget {
  const BackgroundDecoration({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF7FBFF), Color(0xFFEFFAFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: CustomPaint(
        painter: _WavePainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.morphProgress});

  final double morphProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.38;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final strokeWidth = size.shortestSide * 0.052;

    _drawArc(
      canvas,
      rect,
      startAngle: -2.65,
      sweepAngle: ui.lerpDouble(1.5, 1.12, morphProgress)!,
      color: const Color(0xFF4B78EC),
      strokeWidth: strokeWidth,
    );
    _drawArc(
      canvas,
      rect,
      startAngle: -0.58,
      sweepAngle: ui.lerpDouble(1.28, 0.96, morphProgress)!,
      color: const Color(0xFF22BFC0),
      strokeWidth: strokeWidth,
    );
    _drawArc(
      canvas,
      rect,
      startAngle: 1.02,
      sweepAngle: ui.lerpDouble(0.78, 0.56, morphProgress)!,
      color: const Color(0xFFF1C95B),
      strokeWidth: strokeWidth,
    );
  }

  void _drawArc(
    Canvas canvas,
    Rect rect, {
    required double startAngle,
    required double sweepAngle,
    required Color color,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) {
    return oldDelegate.morphProgress != morphProgress;
  }
}

class _ParticlePainter extends CustomPainter {
  const _ParticlePainter({
    required this.progress,
    required this.opacity,
    required this.radius,
  });

  static const List<_Particle> _particles = [
    _Particle(
      angle: -2.72,
      distance: 0.75,
      size: 2.2,
      color: Color(0xFF4B78EC),
    ),
    _Particle(
      angle: -2.05,
      distance: 0.92,
      size: 1.6,
      color: Color(0xFF20B8B5),
    ),
    _Particle(
      angle: -1.22,
      distance: 0.76,
      size: 1.8,
      color: Color(0xFF8AA9F3),
    ),
    _Particle(angle: -0.38, distance: 0.9, size: 1.5, color: Color(0xFFF0C65C)),
    _Particle(angle: 0.42, distance: 0.78, size: 2.1, color: Color(0xFF36BFC0)),
    _Particle(angle: 1.28, distance: 0.94, size: 1.7, color: Color(0xFF7095EC)),
    _Particle(angle: 2.12, distance: 0.82, size: 1.5, color: Color(0xFF52C6BF)),
    _Particle(angle: 2.86, distance: 0.93, size: 1.8, color: Color(0xFF9DB6F1)),
  ];

  final double progress;
  final double opacity;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(progress);
    for (final particle in _particles) {
      final distance = radius * particle.distance + 24 * eased;
      final position = center + Offset.fromDirection(particle.angle, distance);
      final paint = Paint()..color = particle.color.withValues(alpha: opacity);
      canvas.drawCircle(position, particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.opacity != opacity ||
        oldDelegate.radius != radius;
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
  });

  final double angle;
  final double distance;
  final double size;
  final Color color;
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final waveOne = Paint()
      ..color = const Color(0xFFEAF5FF).withValues(alpha: 0.48);
    final waveTwo = Paint()
      ..color = const Color(0xFFDDF8F5).withValues(alpha: 0.3);
    final waveThree = Paint()
      ..color = const Color(0xFFF7FAFF).withValues(alpha: 0.68);

    canvas.drawPath(
      _wavePath(
        width,
        height,
        startY: height * 0.83,
        firstControlY: height * 0.72,
        secondControlY: height * 0.88,
      ),
      waveOne,
    );
    canvas.drawPath(
      _wavePath(
        width,
        height,
        startY: height * 0.89,
        firstControlY: height * 0.8,
        secondControlY: height * 0.94,
      ),
      waveTwo,
    );
    canvas.drawPath(
      _wavePath(
        width,
        height,
        startY: height * 0.94,
        firstControlY: height * 0.87,
        secondControlY: height * 0.98,
      ),
      waveThree,
    );
  }

  Path _wavePath(
    double width,
    double height, {
    required double startY,
    required double firstControlY,
    required double secondControlY,
  }) {
    return Path()
      ..moveTo(0, startY)
      ..quadraticBezierTo(width * 0.28, firstControlY, width * 0.58, startY)
      ..quadraticBezierTo(width * 0.82, secondControlY, width, startY - 10)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => false;
}

double _segment(double value, double start, double end, Curve curve) {
  if (value <= start) return 0;
  if (value >= end) return 1;
  return curve.transform((value - start) / (end - start));
}

double _clampDouble(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}
