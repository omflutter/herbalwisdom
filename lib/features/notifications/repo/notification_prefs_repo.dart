import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_topic.dart';

class NotificationPrefsRepo {
  final Dio _dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, headers: {'Accept': 'application/json'}, connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 20)));

  /// Ensure the device's FCM subscription matches this topic's "push" flag.
  Future<void> syncPushByTopic(NotificationTopic topic) async {
    final fcmTopic = topic.key; // using ID as topic
    try {
      if (topic.push) {
        await FirebaseMessaging.instance.subscribeToTopic(fcmTopic);
        debugPrint('✅ [NotifRepo] Sync subscribe: $fcmTopic');
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(fcmTopic);
        debugPrint('✅ [NotifRepo] Sync unsubscribe: $fcmTopic');
      }
    } catch (e) {
      debugPrint('💥 [NotifRepo] Sync push failed ($fcmTopic): $e');
      // Intentionally swallow to avoid blocking UI; you can bubble up if you prefer.
    }
  }

  /// Ensure all topics have their FCM subscription state applied.
  Future<void> syncAllPush(List<NotificationTopic> topics) async {
    for (final t in topics) {
      await syncPushByTopic(t);
    }
  }

  /// Load all notification categories (server truth)
  Future<List<NotificationTopic>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null || token.isEmpty) {
        throw Exception('Missing auth token. Please log in again.');
      }

      final res = await _dio.get('/get-notifications-category-list', options: Options(headers: {'auth-token': token}));

      final data = res.data;
      if (data['status'] != "1") {
        throw Exception(data['message'] ?? 'Failed to load notification categories');
      }

      final List details = data['details'] ?? [];
      return details.map((e) {
        return NotificationTopic(
          key: e['id'].toString(), // category ID
          title: (e['name'] ?? '').toString(),
          description: (e['description'] ?? '').toString(),
          push: e['message']?.toString() == '1',
          email: e['email']?.toString() == '1',
        );
      }).toList();
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Error loading notifications: $e');
    }
  }

  /// Update preferences:
  /// - 'message' (push): hit API + FCM subscribe/unsubscribe by category ID
  /// - 'email'        : hit API only (NO FCM)
  /// - null           : update both (with FCM only for push)
  Future<void> update(NotificationTopic topic, {String? type}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null || token.isEmpty) {
        throw Exception('Missing auth token.');
      }

      // Determine which types to update
      final List<String> updateTypes;
      if (type == null) {
        updateTypes = const ['message', 'email'];
      } else {
        updateTypes = [type];
      }

      final fcmTopic = topic.key; // use category ID as the FCM topic

      for (final t in updateTypes) {
        final subscribeFlag = (t == 'message' ? topic.push : topic.email) ? '1' : '2';

        // FCM only for push
        if (t == 'message') {
          try {
            if (topic.push) {
              await FirebaseMessaging.instance.subscribeToTopic(fcmTopic);
              debugPrint('✅ Subscribed to FCM topic (by id): $fcmTopic');
            } else {
              await FirebaseMessaging.instance.unsubscribeFromTopic(fcmTopic);
              debugPrint('✅ Unsubscribed from FCM topic (by id): $fcmTopic');
            }
          } catch (e) {
            debugPrint('💥 FCM topic update failed ($fcmTopic): $e');
            rethrow; // let UI revert the toggle
          }
        }

        // Always hit your API for whichever type we're updating
        final res = await _dio.post(
          '/update-notification-settings',
          options: Options(headers: {'auth-token': token}),
          data: FormData.fromMap({
            'type': t, // 'message' or 'email'
            'subscribe': subscribeFlag, // '1' or '2'
            'category_id': topic.key,
          }),
        );

        final data = res.data;
        if (data['status'] != "1") {
          // If server rejected push update, revert the FCM change we just did (best-effort)
          if (t == 'message') {
            try {
              if (topic.push) {
                await FirebaseMessaging.instance.unsubscribeFromTopic(fcmTopic);
              } else {
                await FirebaseMessaging.instance.subscribeToTopic(fcmTopic);
              }
              debugPrint('↩️ Reverted FCM change due to server error ($fcmTopic)');
            } catch (_) {}
          }
          throw Exception('Failed to update $t setting: ${data['message']}');
        }
      }
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Error updating notification: $e');
    }
  }
}
