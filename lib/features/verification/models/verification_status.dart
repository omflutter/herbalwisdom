/// Email / phone verification state of the signed-in user (from GET /get-verification-status).
class VerificationStatus {
  final String email;
  final bool emailVerified;
  final String phone;
  final bool phoneVerified;
  final bool hasPhone;
  final bool googleLinked;

  const VerificationStatus({
    required this.email,
    required this.emailVerified,
    required this.phone,
    required this.phoneVerified,
    required this.hasPhone,
    required this.googleLinked,
  });

  factory VerificationStatus.fromJson(Map json) {
    bool b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
    final phone = (json['phone'] ?? '').toString().trim();
    return VerificationStatus(
      email: (json['email'] ?? '').toString(),
      emailVerified: b(json['email_verified']),
      phone: phone,
      phoneVerified: b(json['phone_verified']),
      hasPhone: json.containsKey('has_phone') ? b(json['has_phone']) : phone.isNotEmpty,
      googleLinked: b(json['google_linked']),
    );
  }

  /// A phone number that exists but was never verified (verified again on next phone sign-in).
  bool get phoneNeedsVerification => hasPhone && !phoneVerified;

  /// Show the "verify your account" banner?
  bool get needsAttention => !emailVerified || phoneNeedsVerification;
}
