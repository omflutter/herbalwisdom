import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repo/notification_prefs_repo.dart';
import '../models/notification_topic.dart';

class NotificationPrefsScreen extends StatefulWidget {
  static const routePath = '/notifications';
  static const routeName = 'notifications';
  final bool setupMode; // when true, show "Continue" CTA after signup

  const NotificationPrefsScreen({super.key, this.setupMode = false});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen>
    with WidgetsBindingObserver {
  final _repo = NotificationPrefsRepo();
  late Future<List<NotificationTopic>> _future;

  bool _didSync = false; // guard to avoid re-syncing on rebuilds
  bool _permissionDenied = false; // track if notification permission is denied
  bool _showContinueButton = true; // control continue button visibility

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionStatus();
    _future = _repo.load();

    // Auto-mark as seen immediately so it's not shown again if app is restarted
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final uri = GoRouterState.of(context).uri;
        final isSetup =
            widget.setupMode || (uri.queryParameters['setup'] == '1');
        if (isSetup) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('notification_intro_shown', true);
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Re-check permission when app resumes from background
    if (state == AppLifecycleState.resumed) {
      _checkPermissionStatus();
    }
  }

  Future<void> _checkPermissionStatus() async {
    final status = await FirebaseMessaging.instance.getNotificationSettings();
    setState(() {
      _permissionDenied =
          status.authorizationStatus == AuthorizationStatus.denied;
    });
  }

  Future<bool> _requestPermissionIfNeeded() async {
    final status = await FirebaseMessaging.instance.getNotificationSettings();
    if (status.authorizationStatus == AuthorizationStatus.denied) {
      final newStatus = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final granted =
          newStatus.authorizationStatus == AuthorizationStatus.authorized ||
          newStatus.authorizationStatus == AuthorizationStatus.provisional;

      if (!granted && mounted) {
        // Permission was denied again, show dialog to open settings
        _showPermissionDeniedDialog();
      }

      setState(() {
        _permissionDenied = !granted;
      });
      return granted;
    }
    return true; // permission already granted
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Alerts Disabled'),
            content: const Text(
              'To receive push alerts, please enable notifications for this app in your device Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Open app settings
                  final uri = Uri.parse('app-settings:');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final isSetup = widget.setupMode || (uri.queryParameters['setup'] == '1');

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: FutureBuilder<List<NotificationTopic>>(
        future: _future,
        builder: (_, s) {
          // ✅ SHIMMER skeleton while loading
          if (s.connectionState == ConnectionState.waiting) {
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, __) {
                return Shimmer.fromColors(
                  baseColor: Colors.grey.shade300,
                  highlightColor: Colors.grey.shade100,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 16,
                            width: 140,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 14,
                            width: double.infinity,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Container(
                                height: 14,
                                width: 100,
                                color: Colors.grey.shade300,
                              ),
                              const Spacer(),
                              Container(
                                height: 28,
                                width: 48,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                height: 14,
                                width: 60,
                                color: Colors.grey.shade300,
                              ),
                              const Spacer(),
                              Container(
                                height: 28,
                                width: 48,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }

          if (s.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load alerts',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.error.toString().replaceAll('Exception: ', ''),
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _future = _repo.load();
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!s.hasData || s.data!.isEmpty) {
            return const Center(child: Text("No alert preferences found"));
          }

          final items = s.data!;

          // 🔁 One-time FCM sync when user enters this screen
          if (!_didSync) {
            _didSync = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await _repo.syncAllPush(items);
            });
          }

          // ✅ Smooth fade-in transition for loaded content
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: s.hasData ? 1.0 : 0.0,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder:
                  (_, i) => _TopicTile(
                    topic: items[i],
                    permissionDenied: _permissionDenied,
                    onChanged: (t, type) async {
                      final ok = await _repo
                          .update(t, type: type)
                          .then((_) => true)
                          .catchError((_) => false);
                      if (!ok) {
                        setState(() {
                          if (type == 'message') {
                            t.push = !t.push;
                          } else {
                            t.email = !t.email;
                          }
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not update ${type == 'message' ? 'push' : 'email'} setting. Please try again.',
                              ),
                            ),
                          );
                        }
                      } else {
                        setState(() {});
                      }
                    },
                    onRequestPermission: _requestPermissionIfNeeded,
                  ),
            ),
          );
        },
      ),
      floatingActionButton:
          (isSetup && _showContinueButton)
              ? FloatingActionButton.extended(
                onPressed: () async {
                  // Hide the button first for smooth UX
                  setState(() {
                    _showContinueButton = false;
                  });

                  // Wait for the UI to update
                  await Future.delayed(const Duration(milliseconds: 200));

                  // Save the preference
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('notification_intro_shown', true);

                  // Navigate to alerts list first to reset the alerts tab state
                  if (mounted) {
                    context.go('/notifications');

                    // Then navigate to home tab
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (mounted) {
                      context.go('/home');
                    }
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Continue'),
              )
              : null,
    );
  }
}

class _TopicTile extends StatefulWidget {
  final NotificationTopic topic;
  final bool permissionDenied;
  final Future<void> Function(NotificationTopic topic, String type) onChanged;
  final Future<bool> Function() onRequestPermission;
  const _TopicTile({
    required this.topic,
    required this.permissionDenied,
    required this.onChanged,
    required this.onRequestPermission,
  });

  @override
  State<_TopicTile> createState() => _TopicTileState();
}

class _TopicTileState extends State<_TopicTile> {
  late bool push;
  late bool mail;

  @override
  void initState() {
    super.initState();
    push = widget.permissionDenied ? false : widget.topic.push;
    mail = widget.topic.email;
  }

  @override
  void didUpdateWidget(_TopicTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If permission status changes, update push toggle
    if (oldWidget.permissionDenied != widget.permissionDenied) {
      setState(() {
        push = widget.permissionDenied ? false : widget.topic.push;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.topic.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(widget.topic.description),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Push Message'),
                const Spacer(),
                Switch(
                  value: push,
                  onChanged: (v) async {
                    // If trying to turn on and permission is denied, request permission first
                    if (v && widget.permissionDenied) {
                      final granted = await widget.onRequestPermission();
                      if (!granted) {
                        // Permission was not granted, ensure toggle stays OFF
                        setState(() => push = false);
                        return;
                      }
                    }
                    setState(() => push = v);
                    widget.topic.push = v;
                    await widget.onChanged(widget.topic, 'message');
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text('Email'),
                const Spacer(),
                Switch(
                  value: mail,
                  onChanged: (v) async {
                    setState(() => mail = v);
                    widget.topic.email = v;
                    await widget.onChanged(widget.topic, 'email');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
