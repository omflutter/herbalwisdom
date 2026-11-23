import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/app_config.dart';
import '../../auth/repo/google_identity.dart';
import '../models/verification_status.dart';
import 'verification_actions.dart';

class VerificationRepo implements VerificationActions {
  VerificationRepo._();
  static final VerificationRepo instance = VerificationRepo._();

  /// Latest known status; the banner listens to this.
  static final ValueNotifier<VerificationStatus?> status = ValueNotifier<VerificationStatus?>(null);

  final Dio _dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 20), headers: {'Accept': 'application/json'}));

  Future<Options?> _authOptions() async {
    final sp = await SharedPreferences.getInstance();
    final token = sp.getString('auth_token');
    if (token == null || token.isEmpty) return null;
    return Options(headers: {'Accept': 'application/json', 'auth-token': token});
  }

  Future<VerificationStatus?> refresh() async {
    try {
      final opts = await _authOptions();
      if (opts == null) return null;
      final res = await _dio.get('/get-verification-status', options: opts);
      final data = res.data as Map;
      if (data['status']?.toString() == '1' && data['details'] is Map) {
        final s = VerificationStatus.fromJson(data['details'] as Map);
        status.value = s;
        return s;
      }
    } catch (e) {
      debugPrint('⚠️ [Verification] refresh failed: $e');
    }
    return null;
  }

  /// Emails a 6-digit code from the backend (not Firebase). One code per email per 60s.
  @override
  Future<VerificationResult> sendEmailCode(String email) async {
    try {
      final res = await _dio.post('/send-otp-on-email', data: FormData.fromMap({'email': email.trim(), 'purpose': 'verify'}));
      final data = res.data as Map;
      final details = data['details'] is Map ? data['details'] as Map : const {};
      final st = data['status']?.toString() ?? '0';
      return VerificationResult(
        status: st,
        message: (data['message'] ?? '').toString(),
        retryAfter: int.tryParse('${details['retry_after'] ?? ''}') ?? (st == '1' ? 60 : 0),
      );
    } on DioException catch (e) {
      debugPrint('❌ [Verification] send code: ${e.message}');
      return const VerificationResult(status: '0', message: 'Network error. Please try again.');
    }
  }

  @override
  Future<VerificationResult> confirmEmailCode(String email, String code) async {
    try {
      final opts = await _authOptions();
      if (opts == null) return const VerificationResult(status: '0', message: 'Please sign in again.');
      final res = await _dio.post('/verify-email-otp', data: FormData.fromMap({'email': email.trim(), 'otp': code.trim()}), options: opts);
      return _fromResponse(res.data as Map);
    } on DioException catch (e) {
      debugPrint('❌ [Verification] confirm code: ${e.message}');
      return const VerificationResult(status: '0', message: 'Network error. Please try again.');
    }
  }

  /// Picks a Google account once and remembers its token, so confirming an email change
  /// doesn't show the account picker a second time.
  String? _pendingGoogleToken;

  @override
  Future<VerificationResult> verifyWithGoogle({bool allowEmailChange = false}) async {
    String? idToken = allowEmailChange ? _pendingGoogleToken : null;
    if (idToken == null) {
      final picked = await GoogleIdentity.pickAccount();
      if (picked.cancelled) return const VerificationResult(status: '0', cancelled: true);
      if (!picked.ok) return VerificationResult(status: '0', message: picked.error ?? 'Google sign-in failed.');
      idToken = picked.idToken;
    }

    try {
      final opts = await _authOptions();
      if (opts == null) return const VerificationResult(status: '0', message: 'Please sign in again.');
      final res = await _dio.post('/verify-email-google', data: FormData.fromMap({'id_token': idToken, 'allow_email_change': allowEmailChange ? '1' : '0'}), options: opts);
      final result = _fromResponse(res.data as Map);
      _pendingGoogleToken = result.needsEmailChangeConfirmation ? idToken : null;
      return result;
    } on DioException catch (e) {
      debugPrint('❌ [Verification] google: ${e.message}');
      _pendingGoogleToken = null;
      return const VerificationResult(status: '0', message: 'Network error. Please try again.');
    } finally {
      if (_pendingGoogleToken == null) await GoogleIdentity.signOut();
    }
  }

  VerificationResult _fromResponse(Map data) {
    final st = data['status']?.toString() ?? '0';
    final details = data['details'] is Map ? data['details'] as Map : const {};
    VerificationStatus? updated;
    if (st == '1' && details.containsKey('email_verified')) {
      updated = VerificationStatus.fromJson(details);
      status.value = updated;
    }
    return VerificationResult(status: st, message: (data['message'] ?? '').toString(), updated: updated, googleEmail: details['google_email']?.toString());
  }
}
