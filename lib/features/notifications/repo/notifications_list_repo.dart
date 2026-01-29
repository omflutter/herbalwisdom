import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';
import '../models/notification_item.dart';

class NotificationsListRepo {
  final Dio _dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 20), headers: {'Accept': 'application/json'}));

  Future<List<NotificationItem>> fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null || token.isEmpty) {
      throw Exception('User not logged in');
    }

    try {
      final res = await _dio.get('/get-user-notification', options: Options(headers: {'auth-token': token}));

      final data = res.data as Map<String, dynamic>;
      if (data['status']?.toString() == '1' && data['details'] is List) {
        final list = data['details'] as List;
        return list.map((e) => NotificationItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to fetch notifications: $e');
    }
  }

  Future<void> markAsSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    if (token == null || token.isEmpty) return;

    try {
      await _dio.post('/user-seen-notification', data: FormData.fromMap({'id': id}), options: Options(headers: {'auth-token': token}));
    } catch (e) {
      // Ignore error, just try best effort
    }
  }

  Future<void> markAllAsSeen() async {
    try {
      final notifications = await fetchNotifications();
      final unseenNotifications = notifications.where((n) => !n.seen).toList();

      // Mark each unseen notification as seen
      for (final notification in unseenNotifications) {
        await markAsSeen(notification.id);
      }
    } catch (e) {
      // Ignore error, best effort
      debugPrint('Error marking all as seen: $e');
    }
  }

  Future<int> getUnseenCount() async {
    try {
      final notifications = await fetchNotifications();
      return notifications.where((n) => !n.seen).length;
    } catch (e) {
      return 0;
    }
  }
}
