import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:herbalwisdom/features/notifications/models/notification_item.dart';
import 'package:herbalwisdom/features/notifications/repo/notifications_list_repo.dart';
import 'package:herbalwisdom/common/widgets/error_view.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../../main.dart' show notificationReceivedController;

class NotificationsListScreen extends StatefulWidget {
  static const routePath = 'notifications';
  static const routeName = 'notifications_list';

  const NotificationsListScreen({super.key});

  @override
  State<NotificationsListScreen> createState() => _NotificationsListScreenState();
}

class _NotificationsListScreenState extends State<NotificationsListScreen> with WidgetsBindingObserver {
  final _repo = NotificationsListRepo();

  // Local state to manage notifications without full reload
  List<NotificationItem>? _notifications;
  bool _isLoading = true;
  String? _error;
  String? _lastCheckedUri; // Track last URI to avoid duplicate refreshes
  StreamSubscription? _notificationUpdateSubscription; // Listen for new notifications

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadNotifications();

    // Listen for new incoming notifications to auto-refresh the list
    _notificationUpdateSubscription = notificationReceivedController.stream.listen((value) {
      // Only refresh if this is a NEW notification (value == 1), not a badge update (null)
      if (value == 1) {
        // Add a small delay to let the notification be saved in backend first
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !_isLoading) {
            debugPrint('🔄 Auto-refreshing alerts list due to new notification');
            _loadNotifications();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Check if we should refresh (when navigating from notification tap)
    try {
      final uri = GoRouterState.of(context).uri.toString();

      // Only refresh if this is a new navigation with refresh parameter
      if (uri.contains('refresh=1') && _lastCheckedUri != uri) {
        _lastCheckedUri = uri;
        debugPrint('🔄 Auto-refreshing alerts list from notification tap');

        // Force immediate refresh
        Future.microtask(() {
          if (mounted) {
            _loadNotifications();
          }
        });
      }
    } catch (e) {
      debugPrint('Error checking refresh parameter: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh when app comes to foreground and we have pending refresh
    if (state == AppLifecycleState.resumed) {
      // Clear the last checked URI to allow refresh if the app was backgrounded and brought back
      // and the user navigates to this screen with a refresh parameter again.
      // This is a simple way to ensure a refresh if the app was paused and resumed.
      _lastCheckedUri = null;
    }
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await _repo.fetchNotifications();
      if (mounted) {
        setState(() {
          _notifications = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await _loadNotifications();
  }

  void _showNotificationDialog(NotificationItem item, int index) {
    showDialog(
      context: context,
      builder:
          (context) => _NotificationDetailDialog(
            notification: item,
            onClose:
                !item.seen
                    ? () {
                      // INSTANT UPDATE: Mark as seen locally first
                      setState(() {
                        _notifications![index] = NotificationItem(id: item.id, name: item.name, title: item.title, body: item.body, dateTime: item.dateTime, seen: true);
                      });

                      // Trigger immediate count update via stream
                      notificationReceivedController.add(null);

                      // Call API in background to persist
                      _repo.markAsSeen(item.id).catchError((e) {
                        debugPrint('Failed to mark notification as seen: $e');
                      });
                    }
                    : null,
          ),
    );
  }

  Future<void> _confirmMarkAllAsRead() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Mark all as read?'),
            content: const Text('Are you sure you want to mark all alerts as read?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Mark all')),
            ],
          ),
    );

    if (confirmed == true) {
      _executeMarkAllAsRead();
    }
  }

  Future<void> _executeMarkAllAsRead() async {
    try {
      // Calculate how many are unseen for instant UI update
      final unseenCount = _notifications?.where((n) => !n.seen).length ?? 0;

      if (unseenCount == 0) {
        // Nothing to mark
        return;
      }

      // INSTANT UPDATE: Mark all as seen locally first
      if (mounted && _notifications != null) {
        setState(() {
          _notifications =
              _notifications!.map((notification) {
                return NotificationItem(
                  id: notification.id,
                  name: notification.name,
                  title: notification.title,
                  body: notification.body,
                  dateTime: notification.dateTime,
                  seen: true, // Mark all as seen
                );
              }).toList();
        });
      }

      // Trigger instant badge update for ALL unseen notifications
      for (int i = 0; i < unseenCount; i++) {
        notificationReceivedController.add(null);
      }
      debugPrint('⚡ Triggered $unseenCount badge decrements for mark all as read');

      // Call API in background to persist
      await _repo.markAllAsSeen();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All alerts marked as read')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to mark all as read')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnseenNotifications = _notifications?.any((n) => !n.seen) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Alert Settings',
            onPressed: () {
              // Navigate to NotificationPrefsScreen
              context.push('/notifications/prefs');
            },
          ),
          if (hasUnseenNotifications) IconButton(icon: const Icon(Icons.done_all), tooltip: 'Mark all as read', onPressed: _confirmMarkAllAsRead),
        ],
      ),
      body: RefreshIndicator(onRefresh: _refresh, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    // Loading state - show shimmer skeleton
    if (_isLoading && _notifications == null) {
      return ListView.builder(padding: const EdgeInsets.all(12), itemCount: 5, itemBuilder: (context, index) => _ShimmerNotificationCard());
    }

    // Error state
    if (_error != null && _notifications == null) {
      return ErrorView(title: 'Unable to load alerts', message: 'Please check your internet connection and try again.', onRetry: _refresh);
    }

    final items = _notifications ?? [];

    // Empty state
    if (items.isEmpty) {
      return const Center(child: Text('No alerts found'));
    }

    // Success state - show list
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 0.5,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: () => _showNotificationDialog(item, index),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      if (!item.seen) Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item.body, style: TextStyle(color: Colors.grey.shade700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text(DateFormat('MMM d, y h:mm a').format(item.dateTime), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dialog to show notification details
class _NotificationDetailDialog extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback? onClose;

  const _NotificationDetailDialog({required this.notification, this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(notification.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // Date
            Text(DateFormat('MMMM d, y • h:mm a').format(notification.dateTime), style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 16),

            // Divider
            const Divider(),
            const SizedBox(height: 16),

            // Body
            Text(notification.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),

            // Close button
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  // Trigger callback BEFORE closing for instant update
                  onClose?.call();
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer placeholder for notification cards while loading
class _ShimmerNotificationCard extends StatelessWidget {
  const _ShimmerNotificationCard();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Card(
        elevation: 0.5,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title shimmer
              Container(height: 16, width: 200, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 8),

              // Body shimmer - 2 lines
              Container(height: 14, width: double.infinity, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 4),
              Container(height: 14, width: 250, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 8),

              // Date shimmer
              Container(height: 12, width: 120, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
            ],
          ),
        ),
      ),
    );
  }
}
