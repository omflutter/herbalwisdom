import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:herbalwisdom/common/widgets/app_config.dart';
import '../models/chat_message.dart';

class ChatRepo {
  final _fire = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final String adminId = 'admin';

  static String? _cachedUserId;

  static void setCachedUserId(String? uid) {
    if (uid != null && uid.isNotEmpty) {
      _cachedUserId = uid;
    }
  }

  static String? get resolvedUserId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) return uid;
    return _cachedUserId;
  }

  String get currentUserId => resolvedUserId ?? '';

  final Dio _dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 20), headers: {'Accept': 'application/json'}));

  DocumentReference<Map<String, dynamic>>? get _chatDoc {
    final uid = currentUserId;
    if (uid.isEmpty) return null;
    return _fire.collection('chats').doc(uid);
  }

  CollectionReference<Map<String, dynamic>>? get _convCol {
    final doc = _chatDoc;
    if (doc == null) return null;
    return doc.collection('conversation');
  }

  // ===== FIRESTORE STREAM =====
  Stream<List<ChatMessage>> stream() {
    final col = _convCol;
    if (col == null) {
      return const Stream.empty();
    }
    return col.orderBy('time', descending: false).snapshots().map((snap) => snap.docs.map((d) => ChatMessage.fromDoc(d)).toList());
  }

  // ===== SEND MESSAGE TO FIRESTORE (user or admin) =====
  Future<void> sendMessage({required String message, required String type, required bool fromAdmin, String? fileName, int? fileSize}) async {
    final col = _convCol;
    final doc = _chatDoc;
    if (col == null || doc == null) {
      throw Exception('Chat session not found. Please log in again.');
    }

    final data = {
      'message': message,
      'sender': fromAdmin ? 'admin' : 'user',
      'receiver': fromAdmin ? 'user' : 'admin',
      'type': type,
      'fileName': fileName,
      'fileSize': fileSize,
      'time': FieldValue.serverTimestamp(),
      'seen': fromAdmin ? false : true, // 👈 user messages auto-seen, admin's unseen
    };

    await col.add(data);

    await doc.set({
      'lastMessage': {
        'message': type == 'text' ? message : (fileName ?? type.toUpperCase()),
        'sender': fromAdmin ? 'admin' : 'user',
        'type': type,
        'time': FieldValue.serverTimestamp(),
        'seen': fromAdmin ? false : true,
      },
    }, SetOptions(merge: true));
  }

  // ===== MARK ADMIN MESSAGES AS SEEN =====
  Future<void> markMessagesAsSeen() async {
    final col = _convCol;
    final doc = _chatDoc;
    if (col == null || doc == null) return;

    final unseen = await col.where('sender', isEqualTo: 'admin').where('seen', isEqualTo: false).get();

    if (unseen.docs.isEmpty) return;

    final batch = _fire.batch();
    for (final d in unseen.docs) {
      batch.update(d.reference, {'seen': true});
    }
    await batch.commit();

    // Update chat document's last message as seen too
    await doc.set({
      'lastMessage': {'seen': true},
    }, SetOptions(merge: true));
  }

  Stream<int> unseenCountStream() {
    final col = _convCol;
    if (col == null) {
      return Stream.value(0);
    }
    return col.where('sender', isEqualTo: 'admin').where('seen', isEqualTo: false).snapshots().map((snap) => snap.docs.length);
  }

  // ===== PUBLIC: SEND TEXT FROM USER =====
  Future<void> sendUser(String text) async {
    // 1) Save to Firebase chat
    await sendMessage(message: text, type: 'text', fromAdmin: false);

    // 2) Also send to REST API /chat-with-admin
    try {
      await _sendToAdminApi(text);
    } catch (e, st) {
      if (kDebugMode) {
        print('⚠️ [ChatRepo] Failed to send to admin API: $e\n$st');
      }
      // Do NOT rethrow – chat in Firebase should still succeed.
    }
  }

  // ===== ATTACHMENTS =====
  /// ✅ Pick image or video from gallery, or files from file picker
  Future<void> sendAttachment({required bool isImage, required Function(double progress) onProgress, required Function(String localPath) onPreviewReady}) async {
    File? file;
    String? name;
    int? size;
    String type = 'file';

    if (isImage) {
      // 🔹 Pick from gallery (can be image or video)
      final picker = ImagePicker();
      final XFile? picked = await picker.pickMedia(); // image or video

      if (picked == null) return;

      file = File(picked.path);
      name = picked.name;
      size = await file.length();

      final ext = name.toLowerCase();
      if (ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png')) {
        type = 'image';
      } else if (ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi') || ext.endsWith('.mkv')) {
        type = 'video';
      }
    } else {
      // 🔹 Pick documents (non-media)
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'docx', 'xlsx', 'zip', 'txt'], allowMultiple: false);
      if (result == null) return;

      file = File(result.files.single.path!);
      name = result.files.single.name;
      size = result.files.single.size;
      type = 'file';
    }

    // 🔹 Show preview immediately
    onPreviewReady(file.path);

    final uid = currentUserId;
    if (uid.isEmpty) throw Exception('Chat session not found. Please log in again.');

    // 🔹 Upload to Firebase Storage
    final ref = _storage.ref().child('chat_uploads/$uid/${DateTime.now().millisecondsSinceEpoch}_$name');

    final uploadTask = ref.putFile(file);

    uploadTask.snapshotEvents.listen((event) {
      final progress = event.bytesTransferred / event.totalBytes;
      onProgress(progress);
    });

    final snapshot = await uploadTask;
    final url = await snapshot.ref.getDownloadURL();

    // 🔹 Save message in Firestore
    await sendMessage(message: url, type: type, fromAdmin: false, fileName: name, fileSize: size);

    // (Optional) you could also ping API with a text note here if needed.
  }

  // ===== PRIVATE: CALL /chat-with-admin API =====
  Future<void> _sendToAdminApi(String message) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null || token.isEmpty) {
      if (kDebugMode) {
        print('⚠️ [ChatRepo] Missing auth_token – not sending to API');
      }
      return;
    }

    final chatId = currentUserId; // using Firebase UID as session id
    if (chatId.isEmpty) {
      if (kDebugMode) {
        print('⚠️ [ChatRepo] Missing currentUserId – not sending to API');
      }
      return;
    }

    final form = FormData.fromMap({'chat_id': chatId, 'message': message});

    final res = await _dio.post(
      '/chat-with-admin',
      data: form,
      options: Options(
        headers: {
          'auth-token': token, // header as per Swagger
        },
      ),
    );

    if (kDebugMode) {
      print('✅ [ChatRepo] /chat-with-admin -> status=${res.statusCode} body=${res.data}');
    }

    // According to Swagger: {"status":"1","message":"Message sent successfully.","details":[]}
    // We don't need to do anything with the response right now.
  }
}
