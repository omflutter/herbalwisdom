class NotificationTopic {
  final String key;
  final String title;
  final String description;
  bool push;
  bool email;

  NotificationTopic({
    required this.key,
    required this.title,
    required this.description,
    this.push = true,
    this.email = false,
  });
}
