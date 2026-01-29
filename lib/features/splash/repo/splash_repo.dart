// lib/features/splash/repo/splash_repo.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Boot-time checks (auth, flags, etc.)
class SplashRepo {
  static const _kAuthTokenKey = 'auth_token';

  /// Returns true if a non-empty auth token exists.
  Future<bool> isLoggedIn() async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString(_kAuthTokenKey);
    print("My token is: $token");
    return token != null && token.isNotEmpty;
  }

  /// (Optional) Read stored token.
  Future<String?> getToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kAuthTokenKey);
  }

  /// (Optional) Clear auth (useful for a logout from splash or debug).
  Future<void> clearAuth() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kAuthTokenKey);
  }
}
