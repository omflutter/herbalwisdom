class NotificationItem {
  final String id;
  final String name;
  final String title;
  final String body;
  final DateTime dateTime;
  final bool seen;

  NotificationItem({required this.id, required this.name, required this.title, required this.body, required this.dateTime, required this.seen});

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      dateTime: DateTime.tryParse(json['date_time'] ?? '') ?? DateTime.now(),
      seen: json['seen'] == true || json['seen'] == 'true',
    );
  }
}
