import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../auth/view/login_screen.dart';
import '../models/splash_config.dart';
import '../repo/splash_repo.dart';

class SplashController {
  final SplashRepo _repo;
  final SplashConfig _config;

  SplashController({SplashRepo? repo, SplashConfig? config}) : _repo = repo ?? SplashRepo(), _config = config ?? const SplashConfig();

  Future<void> boot(BuildContext context, void Function(String route) go) async {
    final start = DateTime.now();

    bool loggedIn = false;
    try {
      // Checks SharedPreferences (or however your SplashRepo implements it)
      loggedIn = await _repo.isLoggedIn();
    } catch (_) {
      // Fall back to loggedOut on any error
      loggedIn = false;
    }

    // Ensure splash minimum display time
    final elapsed = DateTime.now().difference(start);
    final wait = _config.minShowTime - elapsed;
    if (wait.inMilliseconds > 0) {
      await Future.delayed(wait);
    }

    // Respect an optional preferred destination after auth
    final preferred = _config.nextRoute; // e.g., a deep link within the app

    if (loggedIn) {
      // Straight to notifications screen (index 3 in bottom nav)
      go(preferred ?? '/home');
    } else {
      // To login; preserve preferred as ?next=... so you can redirect after login
      final loginRoute = preferred == null ? LoginScreen.routePath : '${LoginScreen.routePath}?next=${Uri.encodeComponent(preferred)}';
      go(loginRoute);
    }
  }
}
