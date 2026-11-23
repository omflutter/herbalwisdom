import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool fromAdmin;
  final String type;
  final String? fileName;
  final int? fileSize;
  final DateTime ts;

  ChatMessage({required this.id, required this.text, required this.fromAdmin, required this.type, this.fileName, this.fileSize, required this.ts});

  factory ChatMessage.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    return ChatMessage(
      id: doc.id,
      text: data['message']?.toString() ?? '',
      fromAdmin: (data['sender'] ?? '') == 'admin',
      type: data['type']?.toString() ?? 'text',
      fileName: data['fileName']?.toString(),
      fileSize: (data['fileSize'] is int) ? data['fileSize'] as int : null,
      ts: parseTime(data['time']),
    );
  }
}
