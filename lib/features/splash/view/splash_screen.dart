import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/colors.dart';
import '../../../app/theme/typography.dart';
import '../../../common/widgets/app_logo.dart';
import '../controller/splash_controller.dart';
import '../widgets/splash_background.dart';

class SplashScreen extends StatefulWidget {
  static const routePath = '/';
  static const routeName = 'splash';

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;

  final _logic = SplashController();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));

    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _scaleIn = Tween<double>(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // start animation quickly, then perform boot and route
    scheduleMicrotask(() async {
      if (mounted) _controller.forward();
      await _logic.boot(context, (route) {
        if (!mounted) return;
        context.go(route);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(
        children: [
          const SplashBackground(),
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fadeIn,
                child: ScaleTransition(
                  scale: _scaleIn,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandLogo(size: 120, showWordmark: true),

                      const SizedBox(height: 16),
                      Text('Bangalow, NSW', style: ts.bodyMedium!.copyWith(color: AppColors.ink.withOpacity(0.6), letterSpacing: 0.3)),
                      const SizedBox(height: 28),
                      Text('MEMBERSHIP APP', style: AppTypography.textTheme.headlineSmall),
                      const SizedBox(height: 36),
                      const _ProgressDots(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatefulWidget {
  const _ProgressDots();

  @override
  State<_ProgressDots> createState() => _ProgressDotsState();
}

class _ProgressDotsState extends State<_ProgressDots> with SingleTickerProviderStateMixin {
  late final AnimationController _dots;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _anim = CurvedAnimation(parent: _dots, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle));
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = _anim.value;
        final s1 = 1.0 + 0.25 * _pulse(v);
        final s2 = 1.0 + 0.25 * _pulse((v + 0.33) % 1.0);
        final s3 = 1.0 + 0.25 * _pulse((v + 0.66) % 1.0);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [Transform.scale(scale: s1, child: dot), const SizedBox(width: 10), Transform.scale(scale: s2, child: dot), const SizedBox(width: 10), Transform.scale(scale: s3, child: dot)],
        );
      },
    );
  }

  double _pulse(double t) => (1 - (2 * (t - 0.5)).abs()); // triangle wave
}
