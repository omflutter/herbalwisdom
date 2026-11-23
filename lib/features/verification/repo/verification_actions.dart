import '../models/verification_status.dart';

/// Outcome of a verification step.
class VerificationResult {
  /// "1" success, "0" error, "3" Google email differs from the account email (needs confirmation).
  final String status;
  final String message;
  final VerificationStatus? updated;
  final String? googleEmail;
  final bool cancelled;

  /// Seconds before another email code can be requested (send-code only).
  final int retryAfter;

  const VerificationResult({required this.status, this.message = '', this.updated, this.googleEmail, this.cancelled = false, this.retryAfter = 0});

  bool get ok => status == '1';
  bool get needsEmailChangeConfirmation => status == '3';
}

/// What the verification UI can do. Implemented by [VerificationRepo]; kept abstract so the
/// banner / sheet stay pure UI.
abstract class VerificationActions {
  Future<VerificationResult> sendEmailCode(String email);
  Future<VerificationResult> confirmEmailCode(String email, String code);
  Future<VerificationResult> verifyWithGoogle({bool allowEmailChange = false});
}
