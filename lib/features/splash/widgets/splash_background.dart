import 'package:flutter/material.dart';
import '../../../app/theme/colors.dart';

class SplashBackground extends StatelessWidget {
  const SplashBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HerbalPaperPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _HerbalPaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Soft paper background + subtle curved mint shapes
    final bg = Paint()..color = AppColors.background;
    canvas.drawRect(Offset.zero & size, bg);

    final mint = Paint()..color = AppColors.mint;
    final dark = Paint()..color = AppColors.darkMint;

    Path blob1 = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.55, size.width * 0.55, size.height * 0.75)
      ..quadraticBezierTo(size.width * 0.8, size.height * 0.92, size.width, size.height * 0.80)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    Path blob2 = Path()
      ..moveTo(0, size.height * 0.18)
      ..quadraticBezierTo(size.width * 0.15, size.height * 0.12, size.width * 0.33, size.height * 0.20)
      ..quadraticBezierTo(size.width * 0.46, size.height * 0.26, size.width * 0.6, size.height * 0.18)
      ..quadraticBezierTo(size.width * 0.9, size.height * 0.05, size.width, size.height * 0.10)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();

    canvas.drawPath(blob1, mint);
    canvas.drawPath(blob2, dark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
