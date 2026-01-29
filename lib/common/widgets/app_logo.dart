import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';

/// If/when you get the official logo PNG/SVG, replace this with Image.asset.
/// This draws a simple spiral-leaf mark that feels “Herbal Wisdom”.import 'package:flutter/material.dart';

/// Brand logo widget.
///
/// - When [showWordmark] = true → uses the full "HERBAL WISDOM" title logo
///   from `assets/icons/herbal_title_logo.png`.
/// - When [showWordmark] = false → uses only the spiral icon logo
///   from `assets/icons/herbal_logo.png`.
class BrandLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const BrandLogo({super.key, this.size = 68, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    if (showWordmark) {
      // Full logo with text
      return Image.asset(
        'assets/icons/herbal_title_logo.png',
        width: size * 2.8, // tweak if you want it larger/smaller
        fit: BoxFit.contain,
      );
    }

    // Icon-only logo (round spiral)
    return Image.asset('assets/icons/herbal_logo.png', width: size, height: size, fit: BoxFit.contain);
  }
}

class _SpiralPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint =
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.065
          ..strokeCap = StrokeCap.round;

    // simple spiral
    final path = Path();
    const turns = 2.2;
    final maxR = size.width * 0.45;
    for (double t = 0; t <= 1; t += 0.005) {
      final angle = turns * 6.28318 * t;
      final r = t * maxR;
      final x = center.dx + r * MathCos(angle);
      final y = center.dy + r * MathSin(angle);
      if (t == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);

    // small leaf
    final leaf =
        Path()
          ..moveTo(center.dx + maxR * 0.85, center.dy)
          ..quadraticBezierTo(center.dx + maxR * 1.10, center.dy - maxR * 0.25, center.dx + maxR * 0.78, center.dy - maxR * 0.05)
          ..quadraticBezierTo(center.dx + maxR * 0.95, center.dy + maxR * 0.15, center.dx + maxR * 0.85, center.dy);
    final leafPaint =
        Paint()
          ..color = AppColors.secondary
          ..style = PaintingStyle.fill;
    canvas.drawPath(leaf, leafPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;

  // quick trig helpers:
  double MathSin(double a) => Math.sin(a);
  double MathCos(double a) => Math.cos(a);
}

class Math {
  static double sin(double x) => _table.sin(x);
  static double cos(double x) => _table.cos(x);
  static const _table = _Trig();
}

class _Trig {
  const _Trig();
  double sin(double x) => _math(x, true);
  double cos(double x) => _math(x, false);
  double _math(double x, bool s) {
    // Dart's math import avoided to keep this file self-contained; replace with dart:math normally.
    // This tiny approximation is adequate for our decorative spiral.
    // For production accuracy, import 'dart:math' as math and use math.sin/cos.
    const pi = 3.1415926535897932;
    // range reduce:
    final k = (x / (2 * pi)).floorToDouble();
    final xr = x - k * 2 * pi;
    // Taylor series up to x^7 term
    double p = xr, x2 = xr * xr, x3 = x2 * xr, x5 = x3 * x2, x7 = x5 * x2;
    final sVal = p - x3 / 6 + x5 / 120 - x7 / 5040;
    final cVal = 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
    return s ? sVal : cVal;
  }
}
