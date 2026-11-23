import 'package:shared_preferences/shared_preferences.dart';

import '../repo/auth_repo.dart';

enum LoginOutcome { success, notFound, error }

class AuthController {
  final AuthRepo _repo;
  AuthController({AuthRepo? repo}) : _repo = repo ?? AuthRepo();

  String? validatePhone(String? v) {
    final s = (v ?? '').replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty) return 'Enter mobile number';
    if (!RegExp(r'^[0-9]{8,15}$').hasMatch(s)) return 'Enter a valid number';
    return null;
  }

  String? validateFirst(String? v) => (v ?? '').trim().isEmpty ? 'First name required' : null;
  String? validateLast(String? v) => (v ?? '').trim().isEmpty ? 'Last name required' : null;
  String? validateEmail(String? v) {
    if ((v ?? '').trim().isEmpty) return 'Email required';
    final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v!.trim());
    return ok ? null : 'Enter a valid email';
  }

  Future<void> startOtpLogin({required String phone, required Function(String verificationId) onCodeSent, required Function(String error) onError}) async {
    await _repo.sendOtp(phone: phone, onCodeSent: onCodeSent, onError: onError);
  }

  /// 1) Verify OTP on Firebase
  Future<bool> verifyOtpFirebase({required String verificationId, required String code, required String phone, required String name, required String email}) {
    return _repo.signInWithOtp(verificationId: verificationId, code: code, phone: phone, name: name, email: email);
  }

  /// 2) Hit login API
  Future<LoginOutcome> tryLogin(String phone) async {
    final res = await _repo.loginUser(phone);
    if (res.status == "1" && res.token != null) {
      // Save token on successful login
      // Reuse register helper to store token (or do it here)
      // Here, just store directly using repo's private helper is not possible.
      // So call registerUser with no-op? Instead, expose a tiny utility:
      // We'll store token by calling a tiny throwaway method:
      await _saveTokenPublic(res.token!);
      return LoginOutcome.success;
    } else if (res.status == "2") {
      return LoginOutcome.notFound;
    } else {
      return LoginOutcome.error;
    }
  }

  /// 3) Register (for status "2" case)
  Future<RegisterResult> registerAfterLoginNotFound({required String firstName, required String lastName, required String email, required String phone}) async {
    final res = await _repo.registerUser(firstName: firstName, lastName: lastName, email: email, phone: phone);
    final success = res.status == "1" && res.token != null;
    return RegisterResult(success: success, message: res.message);
  }

  /// Sign in / sign up with Google (also verifies the email of an existing account).
  Future<GoogleLoginResult> loginWithGoogle() => _repo.signInWithGoogle();

  /// Registration: verify the email with Google instead of the email code.
  Future<GoogleEmailCheckResult> verifyEmailWithGoogle() => _repo.verifyEmailWithGoogleForRegistration();

  Future<EmailCodeSendResult> sendEmailOtp(String email) async {
    return _repo.sendEmailOtp(email);
  }

  Future<bool> verifyEmailOtp(String email, String otp) async {
    return _repo.verifyEmailOtp(email, otp);
  }

  // --- tiny bridge to save token from controller when login is "1"
  Future<void> _saveTokenPublic(String token) async {
    // use the same key used in repo
    // ignore: invalid_use_of_visible_for_testing_member
    // Re-implement locally to keep repo's private helper encapsulated
    // (shared prefs is cheap here)
    final sp = await SharedPreferences.getInstance();
    await sp.setString('auth_token', token);
  }
}

class RegisterResult {
  final bool success;
  final String message;
  RegisterResult({required this.success, required this.message});
}
