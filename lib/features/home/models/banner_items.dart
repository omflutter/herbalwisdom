class BannerItem {
  final String id;
  final String content; // text or image URL
  final String type; // TEXT or IMAGE
  final String color;
  final DateTime created;

  BannerItem({
    required this.id,
    required this.content,
    required this.type,
    required this.color,
    required this.created,
  });

  factory BannerItem.fromJson(Map<String, dynamic> json) {
    return BannerItem(
      id: json['id'].toString(),
      content: (json['banner'] ?? '').toString(),
      type: (json['type'] ?? 'TEXT').toUpperCase(),
      color: (json['color'] ?? '').toString(),
      created: DateTime.tryParse(json['created'] ?? '') ?? DateTime.now(),
    );
  }
}
