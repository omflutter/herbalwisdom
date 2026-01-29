class SplashConfig {
  final Duration minShowTime;
  final Duration logoInDelay;
  final Duration logoOutDelay;
  final String? nextRoute;

  const SplashConfig({
    this.minShowTime = const Duration(milliseconds: 1200),
    this.logoInDelay = const Duration(milliseconds: 200),
    this.logoOutDelay = const Duration(milliseconds: 350),
    this.nextRoute,
  });

  SplashConfig copyWith({
    Duration? minShowTime,
    Duration? logoInDelay,
    Duration? logoOutDelay,
    String? nextRoute,
  }) {
    return SplashConfig(
      minShowTime: minShowTime ?? this.minShowTime,
      logoInDelay: logoInDelay ?? this.logoInDelay,
      logoOutDelay: logoOutDelay ?? this.logoOutDelay,
      nextRoute: nextRoute ?? this.nextRoute,
    );
  }
}
