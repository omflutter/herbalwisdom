import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'google_identity.dart';
import '../../verification/repo/verification_repo.dart';

import '../mdoels/auth_models.dart';

class AuthRepo {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Dio _dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 20), headers: {'Accept': 'application/json'}));

  AppUser? _current;
  AppUser? get currentUser => _current;
  bool get isLoggedIn => _current != null;

  /// --- STEP 1: Send OTP via Firebase (iOS-hang safe) ---
  Future<void> sendOtp({required String phone, required void Function(String verificationId) onCodeSent, required void Function(String error) onError}) async {
    final formatted = phone.trim();
    debugPrint('📲 [AuthRepo] sendOtp -> raw="$phone" formatted="$formatted"');

    bool completed = false;
    void safeComplete() => completed = true;

    final timeout = Timer(const Duration(seconds: 30), () {
      if (!completed) {
        debugPrint('⏳ [AuthRepo] verifyPhoneNumber timed out without callbacks');
        onError(
          'OTP request timed out. If you\'re on iOS, check:\n'
          '• REVERSED_CLIENT_ID URL Scheme in Xcode (required)\n'
          '• Push Notifications + Background Remote Notifications enabled\n'
          '• APNs Auth Key uploaded in Firebase Console (Project Settings → Cloud Messaging)\n'
          'Or try again with a real E.164 phone like +9198XXXXXXXX.',
        );
      }
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: formatted,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential cred) async {
          debugPrint('✅ [AuthRepo] verificationCompleted: provider=${cred.providerId}');
        },
        verificationFailed: (FirebaseAuthException e) {
          if (completed) return;
          safeComplete();
          timeout.cancel();
          debugPrint('❌ [AuthRepo] verificationFailed code=${e.code} msg=${e.message}');
          onError(e.message ?? 'Verification failed (${e.code})');
        },
        codeSent: (String verificationId, int? resendToken) {
          if (completed) return;
          safeComplete();
          timeout.cancel();
          debugPrint('📩 [AuthRepo] codeSent: verificationId=$verificationId resendToken=$resendToken');
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (completed) return;
          safeComplete();
          timeout.cancel();
          debugPrint('⏰ [AuthRepo] codeAutoRetrievalTimeout: verificationId=$verificationId');
          onError('Auto-retrieval timed out. Please request OTP again.');
        },
      );
    } catch (e, st) {
      if (!completed) {
        safeComplete();
        timeout.cancel();
        debugPrint('💥 [AuthRepo] verifyPhoneNumber threw: $e\n$st');
        onError('Failed to start OTP: $e');
      }
    }
  }

  /// --- STEP 2: Verify OTP on Firebase only ---
  Future<bool> signInWithOtp({required String verificationId, required String code, required String phone, required String name, required String email}) async {
    try {
      final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code);
      await _auth.signInWithCredential(credential);
      final user = _auth.currentUser;
      _current = AppUser(id: user?.uid ?? '', phone: phone, fullName: name, email: email);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ OTP verification failed: ${e.message}');
      return false;
    }
  }

  /// --- EMAIL OTP (Manual) ---
  Future<bool> sendEmailOtp(String email) async {
    try {
      // API call to backend to send OTP
      final res = await _dio.post('/send-otp-on-email', data: FormData.fromMap({'email': email}));
      final status = res.data['status']?.toString();
      debugPrint('📧 [AuthRepo] sendEmailOtp: $status');
      return status == "1";
    } catch (e) {
      debugPrint('❌ [AuthRepo] sendEmailOtp error: $e');
      // For now, return false. In a real app, rethrow or handle error.
      return false;
    }
  }

  Future<bool> verifyEmailOtp(String email, String otp) async {
    try {
      final res = await _dio.post('/verify-otp', data: FormData.fromMap({'email': email, 'otp': otp}));
      final status = res.data['status']?.toString();
      debugPrint('✅ [AuthRepo] verifyEmailOtp: $status');
      return status == "1";
    } catch (e) {
      debugPrint('❌ [AuthRepo] verifyEmailOtp error: $e');
      return false;
    }
  }

  /// --- CALL /login-user (form-data: phone) ---
  Future<LoginApiResult> loginUser(String phone) async {
    try {
      // 🔹 NEW: Firebase Auth UID to send to backend
      final firebaseUid = _auth.currentUser?.uid ?? '';
      debugPrint('🧩 [Register] Firebase UID = "$firebaseUid"');
      final resp = await _dio.post('/login-user', data: FormData.fromMap({'phone': phone, "firebase_id": firebaseUid}));
      final data = resp.data as Map;

      final status = (data['status'] ?? '').toString();
      final message = (data['message'] ?? '').toString();
      final token = (data['details'] is Map) ? (data['details']['token'] as String?) : null;

      if (status == "1" && token != null) {
        await _subscribeToUserTopic(firebaseUid);
        // Save user_id for background badge updates
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', firebaseUid);
      }

      return LoginApiResult(status: status, message: message, token: token);
    } on DioException catch (e) {
      debugPrint('❌ Login API error: ${e.message}');
      return LoginApiResult(status: '0', message: 'Network error');
    } catch (e) {
      debugPrint('❌ Unknown login error: $e');
      return LoginApiResult(status: '0', message: 'Unexpected error');
    }
  }

  /// --- GOOGLE SIGN-IN -> Firebase -> /google-login ---
  ///
  /// Backend links/creates the account by the Google email and marks that email as verified
  /// (this also verifies an existing account whose email was never verified).
  Future<GoogleLoginResult> signInWithGoogle() async {
    try {
      final picked = await GoogleIdentity.pickAccount();
      if (picked.cancelled) return GoogleLoginResult(status: '0', message: '', cancelled: true);
      if (!picked.ok) return GoogleLoginResult(status: '0', message: picked.error ?? 'Google sign-in failed.');

      await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: picked.idToken));
      final firebaseIdToken = await _auth.currentUser?.getIdToken(true);
      if (firebaseIdToken == null) {
        return GoogleLoginResult(status: '0', message: 'Could not complete Google sign-in.');
      }

      final deviceId = await _getFirebaseDeviceId();
      final resp = await _dio.post('/google-login', data: FormData.fromMap({'id_token': firebaseIdToken, 'device_id': deviceId}));
      final data = resp.data as Map;

      final status = (data['status'] ?? '').toString();
      final message = (data['message'] ?? '').toString();
      final details = data['details'] is Map ? data['details'] as Map : const {};
      final token = details['token'] as String?;

      if (status != '1' || token == null) {
        // Don't leave a half-signed-in Firebase/Google session behind.
        await _signOutGoogle();
        await _auth.signOut();
        return GoogleLoginResult(status: status.isEmpty ? '0' : status, message: message.isEmpty ? 'Google sign-in failed.' : message);
      }

      // Chat + push topic are keyed on the backend's firebase_id (an existing phone account keeps its original one).
      final firebaseId = (details['firebase_id'] ?? _auth.currentUser?.uid ?? '').toString();

      await _saveToken(token);
      final prefs = await SharedPreferences.getInstance();
      if (firebaseId.isNotEmpty) {
        await prefs.setString('firebase_id', firebaseId);
        await prefs.setString('user_id', firebaseId);
        await _subscribeToUserTopic(firebaseId);
      }

      return GoogleLoginResult(status: status, message: message, token: token, isNewUser: details['is_new_user'] == true, phoneRequired: details['phone_required'] == true);
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ [AuthRepo] Firebase Google credential error: ${e.code} ${e.message}');
      await _signOutGoogle();
      return GoogleLoginResult(status: '0', message: e.message ?? 'Google sign-in failed.');
    } on DioException catch (e) {
      debugPrint('❌ [AuthRepo] /google-login network error: ${e.message}');
      await _signOutGoogle();
      await _auth.signOut();
      return GoogleLoginResult(status: '0', message: 'Network error');
    } catch (e) {
      debugPrint('❌ [AuthRepo] Google sign-in unexpected error: $e');
      return GoogleLoginResult(status: '0', message: 'Unexpected error');
    }
  }

  Future<void> _signOutGoogle() => GoogleIdentity.signOut();

  /// Registration helper: verify an email with Google (instead of the email code).
  /// Returns the verified email + name from Google, or an error message.
  Future<GoogleEmailCheckResult> verifyEmailWithGoogleForRegistration() async {
    final picked = await GoogleIdentity.pickAccount();
    if (picked.cancelled) return GoogleEmailCheckResult(cancelled: true);
    if (!picked.ok) return GoogleEmailCheckResult(message: picked.error);
    try {
      final resp = await _dio.post('/verify-email-with-google', data: FormData.fromMap({'id_token': picked.idToken}));
      final data = resp.data as Map;
      final details = data['details'] is Map ? data['details'] as Map : const {};
      if (data['status']?.toString() == '1') {
        return GoogleEmailCheckResult(
          email: details['email']?.toString(),
          firstName: details['first_name']?.toString() ?? '',
          lastName: details['last_name']?.toString() ?? '',
        );
      }
      return GoogleEmailCheckResult(message: (data['message'] ?? 'Google could not verify your email.').toString());
    } on DioException catch (e) {
      debugPrint('❌ [AuthRepo] verify-email-with-google: ${e.message}');
      return GoogleEmailCheckResult(message: 'Network error');
    } finally {
      await GoogleIdentity.signOut();
    }
  }

  /// --- CALL /register-user (returns token on success) ---
  Future<RegisterApiResult> registerUser({required String firstName, required String lastName, required String email, required String phone}) async {
    try {
      final deviceId = await _getFirebaseDeviceId();

      // 🔹 NEW: Firebase Auth UID to send to backend
      final firebaseUid = _auth.currentUser?.uid ?? '';
      debugPrint('🧩 [Register] Firebase UID = "$firebaseUid"');

      // Build form map
      final formMap = <String, dynamic>{
        'name': firstName,
        'lastname': (lastName.isEmpty ? 'User' : lastName),
        'email': email,
        'phone': phone,
        'device_id': deviceId, // existing field
        'firebase_id': firebaseUid,
      };

      final resp = await _dio.post('/register-user', data: FormData.fromMap(formMap));

      final data = resp.data as Map;
      print(data);
      final status = (data['status'] ?? '').toString();
      final message = (data['message'] ?? '').toString();
      final token = (data['details'] is Map) ? (data['details']['token'] as String?) : null;

      if (status == "1" && token != null) {
        await _saveToken(token);
        await _subscribeToUserTopic(firebaseUid);
        // Save user_id for background badge updates
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', firebaseUid);
      }
      return RegisterApiResult(status: status, message: message, token: token);
    } on DioException catch (e) {
      debugPrint('❌ Register API error: ${e.message}');
      return RegisterApiResult(status: '0', message: 'Network error');
    } catch (e) {
      debugPrint('❌ Unknown register error: $e');
      return RegisterApiResult(status: '0', message: 'Unexpected error');
    }
  }

  /// Persist auth token locally
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// --- LOGOUT: call /log-out + clear Firebase & local token ---
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    // 1️⃣ Try to hit backend logout API (if we have a token)
    try {
      if (token != null && token.isNotEmpty) {
        debugPrint('🔌 [AuthRepo] Calling /log-out with token...');
        final resp = await _dio.delete('/log-out', options: Options(headers: {'Accept': 'application/json', 'auth-token': token}));
        debugPrint('✅ [AuthRepo] Logout API status=${resp.statusCode} data=${resp.data}');
      } else {
        debugPrint('ℹ️ [AuthRepo] No auth_token stored, skipping API logout');
      }
    } on DioException catch (e) {
      debugPrint('⚠️ [AuthRepo] Logout API failed: ${e.message}');
      // We still continue with local logout
    } catch (e) {
      debugPrint('⚠️ [AuthRepo] Logout unknown error: $e');
    } finally {
      // 2️⃣ Always clear Firebase + local state
      final uid = _auth.currentUser?.uid ?? '';
      await _unsubscribeFromUserTopic(uid);
      await _signOutGoogle();
      await _auth.signOut();
      await prefs.clear(); // This clears user_id too
      VerificationRepo.status.value = null;
      _current = null;
      debugPrint('👋 [AuthRepo] Local logout complete');
    }
  }

  // =========================
  // 🔹 REAL Firebase "device id"
  // =========================
  Future<String> _getFirebaseDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    // Return cached id if available
    final cached = prefs.getString('device_id');
    if (cached != null && cached.isNotEmpty) {
      debugPrint('💾 [DeviceId] Using cached: $cached');
      return cached;
    }

    // 1) Try FID
    try {
      final fid = await FirebaseInstallations.instance.getId();
      if (fid.isNotEmpty) {
        final id = 'fid:$fid';
        await prefs.setString('device_id', id);
        debugPrint('✅ [DeviceId] Firebase Installations ID acquired: $id');
        return id;
      }
    } catch (e, st) {
      debugPrint('⚠️ [DeviceId] FID error: $e\n$st');
    }

    // 2) Fallback to FCM token
    try {
      final fcm = await FirebaseMessaging.instance.getToken();
      if (fcm != null && fcm.isNotEmpty) {
        final id = 'fcm:$fcm';
        await prefs.setString('device_id', id);
        debugPrint('✅ [DeviceId] FCM token used as device id: (truncated) ${id.substring(0, 20)}...');
        return id;
      }
    } catch (e, st) {
      debugPrint('⚠️ [DeviceId] FCM error: $e\n$st');
    }

    // 3) Last resort – platform tag
    final fallback =
        Platform.isAndroid
            ? 'fallback:android'
            : Platform.isIOS
            ? 'fallback:ios'
            : 'fallback:unknown';
    await prefs.setString('device_id', fallback);
    debugPrint('🟡 [DeviceId] Using fallback id: $fallback');
    return fallback;
  }

  /// Subscribe to user-specific topic: recieveMessageNotification$uid
  Future<void> _subscribeToUserTopic(String uid) async {
    if (uid.isEmpty) return;
    try {
      final topic = 'recieveMessageNotification$uid';
      await FirebaseMessaging.instance.subscribeToTopic(topic);
      debugPrint('✅ [AuthRepo] Subscribed to user topic: $topic');
    } catch (e) {
      debugPrint('⚠️ [AuthRepo] Failed to subscribe to user topic: $e');
    }
  }

  /// Unsubscribe from user-specific topic
  Future<void> _unsubscribeFromUserTopic(String uid) async {
    if (uid.isEmpty) return;
    try {
      final topic = 'recieveMessageNotification$uid';
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      debugPrint('✅ [AuthRepo] Unsubscribed from user topic: $topic');
    } catch (e) {
      debugPrint('⚠️ [AuthRepo] Failed to unsubscribe from user topic: $e');
    }
  }
}

/// --- Small DTOs for clarity ---
class LoginApiResult {
  final String status; // "1" success, "2" not found, "0" error
  final String message;
  final String? token;
  LoginApiResult({required this.status, required this.message, this.token});
}

class GoogleEmailCheckResult {
  final String? email; // set on success
  final String firstName;
  final String lastName;
  final String? message;
  final bool cancelled;
  GoogleEmailCheckResult({this.email, this.firstName = '', this.lastName = '', this.message, this.cancelled = false});
  bool get ok => email != null;
}

class GoogleLoginResult {
  final String status; // "1" success, "0" error
  final String message;
  final String? token;
  final bool isNewUser;
  final bool phoneRequired;
  final bool cancelled; // user closed the Google account picker
  GoogleLoginResult({required this.status, required this.message, this.token, this.isNewUser = false, this.phoneRequired = false, this.cancelled = false});
}

class RegisterApiResult {
  final String status; // "1" success
  final String message;
  final String? token;
  RegisterApiResult({required this.status, required this.message, this.token});
}
