class Voucher {
  final String id;
  final String title;
  final String description;

  /// API: start_date
  final DateTime startDate;

  /// API: expiry_date
  final DateTime expiryDate;

  /// Whether this voucher has been used.
  /// Comes from API (used_date_time / list type) and can be updated locally.
  bool used;

  /// API: special_coupon ("1"/"0")
  final bool specialCoupon;

  /// API: available_to_all ("1"/"0")
  final bool availableToAll;

  /// API: used_date_time (only present for USED list)
  final DateTime? usedAt;

  Voucher({
    required this.id,
    required this.title,
    required this.description,
    required this.startDate,
    required this.expiryDate,
    this.used = false,
    this.specialCoupon = false,
    this.availableToAll = false,
    this.usedAt,
  });

  /// Derived flags
  bool get expired => expiryDate.isBefore(DateTime.now());
  bool get active => !expired && !used;

  // ---------- JSON helper ----------

  factory Voucher.fromJson(
    Map<String, dynamic> json, {
    String? listType, // "ACTIVE" or "USED" (optional hint from API call)
  }) {
    DateTime _parseDate(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isEmpty) return DateTime.now();
      return DateTime.parse(s); // handles "yyyy-MM-dd" and "yyyy-MM-dd HH:mm:ss"
    }

    final usedStr = (json['used_date_time'] ?? '').toString().trim();
    final usedAt = usedStr.isNotEmpty ? DateTime.parse(usedStr) : null;

    final typeUpper = listType?.toUpperCase();
    final isUsedFromType = typeUpper == 'USED';

    return Voucher(
      id: json['id'].toString(),
      title: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      startDate: _parseDate(json['start_date']),
      expiryDate: _parseDate(json['expiry_date']),
      used: (json['used'] == true || json['used'].toString().toLowerCase() == 'true') || usedAt != null || isUsedFromType,
      specialCoupon: json['special_coupon']?.toString() == '1',
      availableToAll: json['available_to_all']?.toString() == '1',
      usedAt: usedAt,
    );
  }
}
