import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Result of asking the user to pick a Google account.
class GoogleIdentityResult {
  final String? idToken;
  final String? email;
  final bool cancelled;
  final String? error;
  const GoogleIdentityResult({this.idToken, this.email, this.cancelled = false, this.error});

  bool get ok => idToken != null;
}

/// Thin wrapper around google_sign_in (v7) shared by login, registration and email verification.
class GoogleIdentity {
  GoogleIdentity._();

  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize();
    _initialized = true;
  }

  /// Shows the Google account picker and returns the Google ID token.
  /// [fresh] signs out first so the user can pick a different account.
  static Future<GoogleIdentityResult> pickAccount({bool fresh = true}) async {
    try {
      await _ensureInitialized();
      if (fresh) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        return const GoogleIdentityResult(error: 'Google did not return a sign-in token.');
      }
      return GoogleIdentityResult(idToken: token, email: account.email);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const GoogleIdentityResult(cancelled: true);
      }
      debugPrint('❌ [GoogleIdentity] ${e.code} ${e.description}');
      return const GoogleIdentityResult(error: 'Google sign-in failed. Please try again.');
    } catch (e) {
      debugPrint('❌ [GoogleIdentity] unexpected: $e');
      return const GoogleIdentityResult(error: 'Google sign-in failed. Please try again.');
    }
  }

  static Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
