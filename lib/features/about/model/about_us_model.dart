// lib/features/about/models/about_us_model.dart
class AboutUsResponse {
  final String status; // "1" success
  final String message;
  final AboutUsDetails? details;

  AboutUsResponse({
    required this.status,
    required this.message,
    required this.details,
  });

  factory AboutUsResponse.fromJson(Map<String, dynamic> json) {
    return AboutUsResponse(
      status: (json['status'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      details: json['details'] is Map<String, dynamic>
          ? AboutUsDetails.fromJson(json['details'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get isOk => status == '1' && details != null;
}

class AboutUsDetails {
  final String? title;
  final String? description;
  final String? instagram;
  final String? facebook;
  final String? xOrTwitter;
  final String? reddit;
  final String? threads;
  final String? phone1;
  final String? phone2;
  final String? phone3;
  final String? address;
  final String? email;

  AboutUsDetails({
    this.title,
    this.description,
    this.instagram,
    this.facebook,
    this.xOrTwitter,
    this.reddit,
    this.threads,
    this.phone1,
    this.phone2,
    this.phone3,
    this.address,
    this.email,
  });

  factory AboutUsDetails.fromJson(Map<String, dynamic> json) {
    return AboutUsDetails(
      title: _s(json['title']),
      description: _s(json['description']),
      instagram: _s(json['instagram']),
      facebook: _s(json['facebook']),
      xOrTwitter: _s(json['x_or_twitter']),
      reddit: _s(json['reddit']),
      threads: _s(json['threads']),
      phone1: _s(json['phone_1']),
      phone2: _s(json['phone_2']),
      phone3: _s(json['phone_3']),
      address: _s(json['address']),
      email: _s(json['email']),
    );
  }

  static String? _s(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  List<String> get phones =>
      [phone1, phone2, phone3].whereType<String>().where((p) => p.trim().isNotEmpty).toList();
}
