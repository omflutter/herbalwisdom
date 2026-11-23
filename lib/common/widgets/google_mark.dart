import 'package:flutter/material.dart';

/// Multi-colour "G" used on Google buttons (no image asset needed).
class GoogleMark extends StatelessWidget {
  final double size;
  const GoogleMark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback:
          (bounds) => const SweepGradient(
            colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4)],
          ).createShader(bounds),
      child: Text('G', style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
    );
  }
}
