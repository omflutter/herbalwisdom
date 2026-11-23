import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'dart:async';
import '../../app/theme/colors.dart';
import '../../features/notifications/repo/notifications_list_repo.dart';
import '../../features/vouchers/repo/vouchers_repo.dart';
import '../../features/chat/repo/chat_repo.dart';
import '../../main.dart' show notificationReceivedController;
import '../../features/verification/widgets/verification_banner_host.dart';

class AppShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _notificationsRepo = NotificationsListRepo();
  int _unseenNotificationCount = 0;
  Timer? _notificationPollTimer;
  StreamSubscription? _notificationStreamSubscription;

  @override
  void initState() {
    super.initState();
    _maybeShowNotificationPrefs();
    _startNotificationPolling();

    // Listen for real-time notification events
    _notificationStreamSubscription = notificationReceivedController.stream.listen((value) {
      // INSTANT UPDATE: Optimistically decrement count first for immediate feedback
      // Decrement on any event (new notification increases count elsewhere, seen updates decrease here)
      if (_unseenNotificationCount > 0) {
        setState(() {
          _unseenNotificationCount--;
        });
        debugPrint('⚡ Instant badge decrement to $_unseenNotificationCount');
      }

      // Then verify with API in background (will auto-correct if needed)
      Future.delayed(const Duration(milliseconds: 500), () {
        _fetchNotificationCount();
      });
    });
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    _notificationStreamSubscription?.cancel();
    super.dispose();
  }

  void _startNotificationPolling() {
    // Fetch immediately
    _fetchNotificationCount();

    // Poll every 30 seconds for notification updates
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchNotificationCount();
    });
  }

  Future<void> _fetchNotificationCount() async {
    try {
      final count = await _notificationsRepo.getUnseenCount();
      if (mounted) {
        setState(() {
          _unseenNotificationCount = count;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notification count: $e');
    }
  }

  Future<void> _maybeShowNotificationPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('notification_intro_shown') ?? false;
    if (!shown) {
      // Navigate after first frame to avoid build conflicts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/notifications/prefs?setup=1');
        }
      });
    } else {
      // Ensure Home tab is selected on subsequent launches
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.navigationShell.goBranch(0);
        }
      });
    }
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if we switched TO the chat tab (index 2)
    if (widget.navigationShell.currentIndex == 2 && oldWidget.navigationShell.currentIndex != 2) {
      _markChatSeen();
    }
    // Check if we switched TO the notifications tab (index 3)
    if (widget.navigationShell.currentIndex == 3 && oldWidget.navigationShell.currentIndex != 3) {
      _fetchNotificationCount();
    }
  }

  Future<void> _markChatSeen() async {
    try {
      // We need to import ChatRepo or use a provider.
      // Since ChatRepo is simple, we can instantiate it or use a static method if available.
      // For now, let's use a quick Firestore call to avoid circular imports if ChatRepo is heavy.
      // Actually, let's just use the same logic as ChatRepo to be safe.
      final userId = FirebaseAuth.instance.currentUser?.uid ?? ChatRepo.resolvedUserId;
      if (userId == null || userId.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance.collection('chats').doc(userId).collection('conversation');
      final unseen = await col.where('sender', isEqualTo: 'admin').where('seen', isEqualTo: false).get();

      if (unseen.docs.isNotEmpty) {
        for (final doc in unseen.docs) {
          batch.update(doc.reference, {'seen': true});
        }
        await batch.commit();

        // Update last message
        await FirebaseFirestore.instance.collection('chats').doc(userId).set({
          'lastMessage': {'seen': true},
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('AppShell mark seen error: $e');
    }
  }

  void _goBranch(int index) {
    widget.navigationShell.goBranch(index, initialLocation: index == widget.navigationShell.currentIndex);
    if (index == 1) {
      VouchersRepo.voucherUpdatesNotifier.value++;
    } else if (index == 2) {
      _markChatSeen();
    } else if (index == 3) {
      _fetchNotificationCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? ChatRepo.resolvedUserId;

    // If no user, show basic nav bar without stream
    if (userId == null || userId.isEmpty) {
      return Scaffold(
        body: VerificationBannerHost(child: widget.navigationShell),
        bottomNavigationBar: NavigationBar(
          selectedIndex: widget.navigationShell.currentIndex,
          onDestinationSelected: _goBranch,
          indicatorColor: AppColors.mint,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Specials'),
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
            NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Alerts'),
            NavigationDestination(icon: Icon(Icons.info_outline), selectedIcon: Icon(Icons.info), label: 'About Us'),
          ],
        ),
      );
    }

    return Scaffold(
      body: VerificationBannerHost(child: widget.navigationShell),
      bottomNavigationBar: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('chats').doc(userId).collection('conversation').where('sender', isEqualTo: 'admin').where('seen', isEqualTo: false).snapshots(),
        builder: (context, snapshot) {
          final unseenCount = snapshot.data?.docs.length ?? 0;

          // Calculate total badge count: chat + notifications
          final totalBadgeCount = unseenCount + _unseenNotificationCount;

          // Update app icon badge with combined count
          if (totalBadgeCount > 0) {
            AppBadgePlus.updateBadge(totalBadgeCount);
          } else {
            AppBadgePlus.updateBadge(0);
          }

          // Save locally for background increments
          SharedPreferences.getInstance().then((prefs) {
            prefs.setInt('local_badge_count', totalBadgeCount);
          });

          return NavigationBar(
            selectedIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: _goBranch,
            indicatorColor: AppColors.mint,
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              const NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Specials'),
              // Chat tab with live badge
              NavigationDestination(
                icon: Badge(isLabelVisible: unseenCount > 0, label: Text(unseenCount > 99 ? '99+' : '$unseenCount'), child: const Icon(Icons.chat_bubble_outline)),
                selectedIcon: Badge(isLabelVisible: unseenCount > 0, label: Text(unseenCount > 99 ? '99+' : '$unseenCount'), child: const Icon(Icons.chat_bubble)),
                label: 'Chat',
              ),
              // Alerts tab with live badge
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: _unseenNotificationCount > 0,
                  label: Text(_unseenNotificationCount > 99 ? '99+' : '$_unseenNotificationCount'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: _unseenNotificationCount > 0,
                  label: Text(_unseenNotificationCount > 99 ? '99+' : '$_unseenNotificationCount'),
                  child: const Icon(Icons.notifications),
                ),
                label: 'Alerts',
              ),
              const NavigationDestination(icon: Icon(Icons.info_outline), selectedIcon: Icon(Icons.info), label: 'About Us'),
            ],
          );
        },
      ),
    );
  }
}
