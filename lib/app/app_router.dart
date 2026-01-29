import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../common/widgets/app_shell.dart';
import '../features/news/view/news_details_screen.dart';
import '../features/notifications/view/notifcation_prefs_screen.dart';
import '../features/splash/view/splash_screen.dart';
import '../features/auth/view/login_screen.dart';
import '../features/auth/view/otp_screen.dart';
import '../features/auth/view/register_screen.dart';

import '../features/home/view/home_screen.dart';
import '../features/vouchers/view/vouchers_details_screen.dart';
import '../features/vouchers/view/vouchers_list_screen.dart';
import '../features/news/view/news_screen.dart';
import '../features/notifications/view/notifications_list_screen.dart';

import '../features/chat/view/chat_screen.dart';
import '../features/about/view/about_screen.dart';

class AppRouter {
  static final _rootKey = GlobalKey<NavigatorState>();

  static final _homeKey = GlobalKey<NavigatorState>(debugLabel: 'home');
  static final _specialsKey = GlobalKey<NavigatorState>(debugLabel: 'specials');
  static final _aboutKey = GlobalKey<NavigatorState>(debugLabel: 'about');
  static final _notifsKey = GlobalKey<NavigatorState>(debugLabel: 'notifs');
  static final _chatKey = GlobalKey<NavigatorState>(debugLabel: 'chat');

  static GoRouter router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: SplashScreen.routePath,
    errorBuilder: (context, state) {
      // Handle any routing errors gracefully
      debugPrint('🚫 [Router] Error: ${state.error} for location: ${state.uri}');

      // Check if this is a Firebase auth callback that we should ignore
      final uriString = state.uri.toString();
      if (uriString.contains('firebaseauth') || uriString.contains('__/auth/callback') || uriString.contains('deep_link_id')) {
        debugPrint('🔄 [Router] Detected Firebase auth deep link - showing loading screen');
        debugPrint('   Firebase SDK will handle this callback internally');

        // Auto-dismiss after a brief delay to allow Firebase SDK to process
        Future.delayed(const Duration(milliseconds: 500), () {
          if (context.mounted) {
            debugPrint('🔙 [Router] Auto-dismissing Firebase auth callback screen');
            // Try to go back, if that fails, go to login
            try {
              context.pop();
            } catch (e) {
              debugPrint('⚠️ [Router] Could not pop, will stay on loading screen');
            }
          }
        });

        // Just show a loading screen without redirecting
        // Firebase SDK will handle the callback and dismiss this automatically
        // This prevents interference with OTP screen navigation
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Processing authentication...', style: TextStyle(color: Colors.grey))],
            ),
          ),
        );
      }

      // For other errors, show the error page
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Page Not Found', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${state.uri}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => context.go(SplashScreen.routePath), child: const Text('Go Home')),
            ],
          ),
        ),
      );
    },
    routes: [
      // Splash & Auth outside the shell
      GoRoute(path: SplashScreen.routePath, name: SplashScreen.routeName, builder: (_, __) => const SplashScreen()),
      GoRoute(path: LoginScreen.routePath, name: LoginScreen.routeName, builder: (_, __) => const LoginScreen()),

      // Firebase auth callback handler - Firebase SDK handles this internally
      // We just need to provide a route so it doesn't show "Page Not Found"
      GoRoute(
        path: '/__/auth/callback',
        builder: (context, state) {
          final deepLink = state.uri.queryParameters['deep_link_id'];
          debugPrint('🔄 [Router] Firebase auth callback received');
          debugPrint('   Deep link: $deepLink');
          debugPrint('   All params: ${state.uri.queryParameters}');

          // Firebase SDK handles the callback internally, just show a blank screen briefly
          // The SDK will close this automatically after processing
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        },
      ),

      GoRoute(path: RegisterScreen.routePath, name: RegisterScreen.routeName, builder: (_, s) => RegisterScreen(extra: s.extra as Map<String, dynamic>?)),
      GoRoute(
        path: OtpScreen.routePath,
        name: OtpScreen.routeName,
        builder: (_, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return OtpScreen(
            phoneNumber: extra?['phone'] ?? s.uri.queryParameters['phone'],
            fromRoute: s.uri.queryParameters['from'],
            extra: extra, // ✅ Pass it down so OtpScreen gets verificationId
          );
        },
      ),

      // Tabbed shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          // 0) Home
          StatefulShellBranch(
            navigatorKey: _homeKey,
            routes: [
              GoRoute(
                path: HomeScreen.routePath,
                name: HomeScreen.routeName,
                builder: (_, __) => const HomeScreen(),
                routes: [
                  // GoRoute(path: NotificationsListScreen.routePath, name: NotificationsListScreen.routeName, builder: (_, __) => const NotificationsListScreen())
                ],
              ),
              // Optional: make News pushable from Home (kept simple)
              GoRoute(
                path: NewsScreen.routePath,
                name: NewsScreen.routeName,
                builder: (_, __) => const NewsScreen(),
                routes: [
                  GoRoute(
                    path: NewsDetailScreen.subPath, // ':id'
                    name: NewsDetailScreen.routeName,
                    builder: (_, s) => NewsDetailScreen(newsId: s.pathParameters['id']!),
                  ),
                ],
              ),
              // GoRoute(path: NewsScreen.routePath, name: NewsScreen.routeName, builder: (_, __) => const NewsScreen()),
            ],
          ),

          // 1) Specials (Vouchers)
          StatefulShellBranch(
            navigatorKey: _specialsKey,
            routes: [
              GoRoute(
                path: VouchersListScreen.routePath,
                name: VouchersListScreen.routeName,
                builder: (_, __) => const VouchersListScreen(),
                routes: [
                  GoRoute(
                    path: VoucherDetailScreen.subPath, // ':id'
                    name: VoucherDetailScreen.routeName,
                    builder: (_, s) => VoucherDetailScreen(voucherId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),

          // 4) Chat  ✅ NEW TAB
          StatefulShellBranch(navigatorKey: _chatKey, routes: [GoRoute(path: ChatScreen.routePath, name: ChatScreen.routeName, builder: (_, __) => const ChatScreen())]),

          // 3) Notifications (was Alerts)
          StatefulShellBranch(
            navigatorKey: _notifsKey,
            routes: [
              GoRoute(
                path: '/notifications', // Root path for this branch
                name: NotificationsListScreen.routeName,
                builder: (_, __) => const NotificationsListScreen(),
                routes: [
                  GoRoute(
                    path: 'prefs', // Sub-route path
                    name: NotificationPrefsScreen.routeName,
                    builder: (_, __) => const NotificationPrefsScreen(),
                  ),
                ],
              ),
            ],
          ),

          // 2) About
          StatefulShellBranch(navigatorKey: _aboutKey, routes: [GoRoute(path: AboutScreen.routePath, name: AboutScreen.routeName, builder: (_, __) => const AboutScreen())]),
        ],
      ),

      // Root stack (single pages) — keep empty to avoid duplicates.
      // (Removed Chat and About to prevent name/path collisions)
    ],
  );
}
