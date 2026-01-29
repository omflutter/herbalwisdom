// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'app/app_router.dart';
import 'app/theme/colors.dart';
import 'app/theme/typography.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// Stream controller to notify app when a new notification is received
// Sends 1 for new notification (should refresh list), null for badge update only
final StreamController<int?> notificationReceivedController = StreamController<int?>.broadcast();

String? _currentUserName;

String _pretty(Object? obj) {
  try {
    return const JsonEncoder.withIndent('  ').convert(obj);
  } catch (_) {
    return obj.toString();
  }
}

/// ---------- Logger ----------
enum _L { d, i, w, e }

void _log(_L level, String tag, String message, [Object? error, StackTrace? st]) {
  final mark = {_L.d: '🐞', _L.i: 'ℹ️', _L.w: '⚠️', _L.e: '💥'}[level];
  final ts = DateTime.now().toIso8601String();
  final lines = <String>['$mark [$ts][$tag] $message', if (error != null) '  error: $error', if (st != null) '  stack: $st'];
  for (final l in lines) debugPrint(l);
}

/// ---------- Background handler ----------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  _log(_L.i, 'BG', 'Handling background message:\n${const JsonEncoder.withIndent("  ").convert(message.toMap())}');

  try {
    // Increment badge count locally
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt('local_badge_count') ?? 0;

    // Increment
    current++;

    // Update badge
    await AppBadgePlus.updateBadge(current);

    // Save new count
    await prefs.setInt('local_badge_count', current);

    _log(_L.i, 'BG', 'Incremented badge to $current');
  } catch (e) {
    _log(_L.e, 'BG', 'Error updating badge in background', e);
  }
}

/// ---------- Load user name (still kept for potential future use) ----------
Future<void> _loadCurrentUserName() async {
  try {
    final sp = await SharedPreferences.getInstance();

    _currentUserName = sp.getString('user_name');
    if (_currentUserName != null && _currentUserName!.isNotEmpty) {
      _log(_L.i, 'Profile', 'Cached name: $_currentUserName');
    }

    final token = sp.getString('auth_token');
    if (token == null || token.isEmpty) {
      _log(_L.w, 'Profile', 'No auth-token; skip fetch');
      return;
    }

    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json', 'auth-token': token},
      ),
    );

    final res = await dio.get('/get-user-profile');
    final data = res.data as Map;

    if (data['status']?.toString() == '1' && data['details'] is Map) {
      final details = data['details'] as Map;
      final first = (details['first_name'] ?? details['name'] ?? '').toString().trim();
      final last = (details['last_name'] ?? details['lastname'] ?? '').toString().trim();
      final full = [first, last].where((s) => s.isNotEmpty).join(' ').trim();

      _currentUserName = full.isNotEmpty ? full : (first.isNotEmpty ? first : null);
      _log(_L.i, 'Profile', 'Loaded user name: ${_currentUserName ?? "(null)"}');

      await sp.setString('user_name', _currentUserName ?? '');
    } else {
      _log(_L.w, 'Profile', 'Profile fetch failed: ${data['message']}');
    }
  } catch (e, st) {
    _log(_L.e, 'Profile', 'Error fetching profile', e, st);
  }
}

/// ---------- Notification Tap Handler ----------
void _handleNotificationTap(Map<String, dynamic> data) {
  try {
    _log(_L.i, 'Nav', 'Handling notification tap data: $data');

    // Check for type in the data payload
    final String? notificationType = data['type']?.toString();

    if (notificationType == 'CHAT') {
      _log(_L.i, 'Nav', 'Navigating to chat from notification');
      // Use a slight delay to ensure router is ready if coming from cold start
      Future.delayed(const Duration(milliseconds: 500), () {
        AppRouter.router.go('/chat');
      });
      return;
    }

    if (notificationType == 'PROMOTIONS') {
      // Extract voucher info from notification_info
      if (data.containsKey('notification_info')) {
        final dynamic infoRaw = data['notification_info'];
        Map<String, dynamic> info;

        if (infoRaw is String) {
          info = jsonDecode(infoRaw) as Map<String, dynamic>;
        } else if (infoRaw is Map) {
          info = Map<String, dynamic>.from(infoRaw);
        } else {
          _log(_L.w, 'Nav', 'notification_info is not a valid format');
          return;
        }

        // Get the voucher ID
        final String? voucherId = info['id']?.toString();
        if (voucherId != null && voucherId.isNotEmpty) {
          _log(_L.i, 'Nav', 'Navigating to voucher detail: $voucherId');
          // Use a slight delay to ensure router is ready
          Future.delayed(const Duration(milliseconds: 500), () {
            AppRouter.router.go('/vouchers/$voucherId');
          });
        } else {
          _log(_L.w, 'Nav', 'No voucher ID found in notification_info');
        }
      } else {
        _log(_L.w, 'Nav', 'No notification_info found for PROMOTIONS type');
      }
      return;
    }

    // For any other notification type, navigate to alerts list
    _log(_L.i, 'Nav', 'Navigating to alerts list for type: $notificationType');
    Future.delayed(const Duration(milliseconds: 500), () {
      AppRouter.router.go('/notifications?refresh=1');
    });
  } catch (e) {
    _log(_L.e, 'Nav', 'Error handling notification tap', e);
  }
}

/// ---------- Push + Local notifications ----------
Future<void> _setupPushAndNotifications() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for important notifications.',
    importance: Importance.high,
  );

  final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);

  const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initIOS = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: initAndroid, iOS: initIOS);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (resp) {
      _log(_L.i, 'Notif', 'Tapped local notification payload=${resp.payload}');
      if (resp.payload != null) {
        try {
          final data = jsonDecode(resp.payload!) as Map<String, dynamic>;
          _handleNotificationTap(data);
        } catch (_) {}
      }
    },
  );

  await androidPlugin?.requestNotificationsPermission();
  final iosPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
  await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  _log(_L.i, 'Push', 'Background handler registered');

  final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
  _log(_L.i, 'Push', 'Firebase permission: ${settings.authorizationStatus}');

  // Allow OS banners (since personalization is removed)
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

  if (Platform.isIOS) {
    try {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      _log(_L.i, 'Push', 'APNs token: ${apns ?? "null"}');
    } catch (e) {
      _log(_L.w, 'Push', 'APNs token not available yet: $e');
    }
  }

  try {
    final fcm = await FirebaseMessaging.instance.getToken();
    _log(_L.i, 'Push', 'FCM token: ${fcm ?? "null"}');
  } catch (e) {
    _log(_L.w, 'Push', 'FCM token not available: $e');
  }

  // ---------- Foreground ----------
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    _log(_L.i, 'Push', 'onMessage:\n${_pretty(message.toMap())}');

    // Notify listeners that a new notification was received (send 1 to trigger list refresh)
    notificationReceivedController.add(1);

    String? title = message.notification?.title ?? message.data['title'] ?? 'Alert';
    String? body = message.notification?.body ?? message.data['body'] ?? 'You got a message';

    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'Used for important notifications.',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    // show on Android manually; iOS uses system banner automatically
    if (!Platform.isIOS) {
      await flutterLocalNotificationsPlugin.show(message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch, title, body, details, payload: jsonEncode(message.data));
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    final title = message.notification?.title;
    final body = message.notification?.body;
    _log(_L.i, 'Push', 'onMessageOpenedApp: $title / $body');
    _handleNotificationTap(message.data);
  });

  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) {
    final title = initial.notification?.title;
    final body = initial.notification?.body;
    _log(_L.i, 'Push', 'getInitialMessage: $title / $body');
    _handleNotificationTap(initial.data);
  }
}

/// ---------- Error handlers ----------
void _wireGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    _log(_L.e, 'Flutter', 'Framework error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _log(_L.e, 'Dart', 'Uncaught error', error, stack);
    return true;
  };
}

/// ---------- Main entry ----------
Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _wireGlobalErrorHandlers();

      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _log(_L.i, 'Core', 'Firebase initialized (project: ${DefaultFirebaseOptions.currentPlatform.projectId})');

      await _loadCurrentUserName();

      await _setupPushAndNotifications();

      runApp(const HerbalWisdomApp());
    },
    (error, stack) {
      _log(_L.e, 'Main', 'Uncaught zone error', error, stack);
    },
  );
}

/// ---------- App ----------
class HerbalWisdomApp extends StatelessWidget {
  const HerbalWisdomApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = AppRouter.router;
    return MaterialApp.router(
      title: 'Herbal Wisdom',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed, primary: AppColors.primary, secondary: AppColors.secondary),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: AppTypography.textTheme,
        useMaterial3: true,
      ),
    );
  }
}

/* 

TODO: 5 Dec, 2025

1. Notfication count is changing in some time
2. Still user is navigating to voucher screen even if there is no voucher content
3. Continue button is not disappearing on pressing for the first time in notification pref screen




1. /register-user -- add firebase id

2. show ACTIVE and USED in voucher

3. change voucher  model

4. /chat-with-admin


1. If user has declined notification then show alert to enable it
2. Refresh voucher list on 
3. Resend otp


1. Chat notification routing to chat screen
2. Chat counnt at bottom nav bar
3. Notification screen to show all the notification with time.
4.  

 */
