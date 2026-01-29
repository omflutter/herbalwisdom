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
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      text: data['message'] ?? '',
      fromAdmin: (data['sender'] ?? '') == 'admin',
      type: data['type'] ?? 'text',
      fileName: data['fileName'],
      fileSize: (data['fileSize'] is int) ? data['fileSize'] : null,
      ts: (data['time'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
