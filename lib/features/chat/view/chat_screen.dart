import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herbalwisdom/common/widgets/app_config.dart';
import '../repo/chat_repo.dart';
import '../models/chat_message.dart';

class ChatScreen extends StatefulWidget {
  static const routePath = '/chat';
  static const routeName = 'chat';
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _repo = ChatRepo();
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0);

  List<ChatMessage> _messages = [];
  bool _userScrolledUp = false;
  bool _isVisible = false; // ✅ True only when user is really seeing chat tab
  bool _loadingUser = false;

  // Upload preview state
  String? _uploadingFilePath;
  String? _uploadingFileType; // 'image', 'video', or 'file'
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureUserId();

    // 👇 Detect first visibility after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isVisible = ModalRoute.of(context)?.isCurrent ?? true;
    });
  }

  Future<void> _ensureUserId() async {
    if (_repo.currentUserId.isEmpty) {
      setState(() => _loadingUser = true);
      try {
        final sp = await SharedPreferences.getInstance();
        final uid = sp.getString('firebase_id') ?? sp.getString('user_id');
        if (uid != null && uid.isNotEmpty) {
          ChatRepo.setCachedUserId(uid);
        } else {
          final token = sp.getString('auth_token');
          if (token != null && token.isNotEmpty) {
            final dio = Dio(BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Accept': 'application/json', 'auth-token': token},
            ));
            final res = await dio.get('/get-user-profile');
            if (res.data['status']?.toString() == '1' && res.data['details'] is Map) {
              final fId = res.data['details']['firebase_id']?.toString().trim();
              if (fId != null && fId.isNotEmpty) {
                await sp.setString('firebase_id', fId);
                ChatRepo.setCachedUserId(fId);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('ChatScreen _ensureUserId error: $e');
      } finally {
        if (mounted) setState(() => _loadingUser = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Register dependency to ensure we get notified when tab changes
    try {
      StatefulNavigationShell.of(context);
    } catch (_) {}

    _checkVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVisibility();
    } else {
      _isVisible = false;
    }
  }

  void _checkVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        final shell = StatefulNavigationShell.of(context);
        // Chat is at index 2
        final isChatTab = shell.currentIndex == 2;
        final isRouteCurrent = ModalRoute.of(context)?.isCurrent ?? false;

        final newVisible = isChatTab && isRouteCurrent;
        debugPrint('ChatScreen visibility check: tab=$isChatTab (${shell.currentIndex}), route=$isRouteCurrent -> visible=$newVisible');

        if (newVisible != _isVisible) {
          _isVisible = newVisible;
          if (_isVisible) {
            _markSeenSafe();
          }
        }
      } catch (e) {
        debugPrint('ChatScreen visibility error (not in shell?): $e');
        // If not in shell, fallback to just route current
        // BUT: if we are in a shell but it failed, we might default to false to be safe
        final isRouteCurrent = ModalRoute.of(context)?.isCurrent ?? false;
        if (isRouteCurrent != _isVisible) {
          _isVisible = isRouteCurrent;
          if (_isVisible) _markSeenSafe();
        }
      }
    });
  }

  Future<void> _markSeenSafe() async {
    debugPrint('ChatScreen marking seen... (visible=$_isVisible)');
    try {
      await _repo.markMessagesAsSeen();
      debugPrint('ChatScreen marked seen done.');
    } catch (e) {
      debugPrint('ChatScreen mark seen error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  bool _isNearBottom() {
    if (!_scrollCtrl.hasClients) return true;
    // In reverse mode, position 0 is at the bottom
    final threshold = 120;
    return _scrollCtrl.offset < threshold;
  }

  void _scrollToBottom({bool instant = false}) {
    if (!_scrollCtrl.hasClients) return;
    // In reverse mode, scroll to position 0 (bottom)
    if (instant) {
      _scrollCtrl.jumpTo(0);
    } else {
      _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  Future<void> _openMedia(String url, {String? fileName}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/${fileName ?? url.split('/').last.split('?').first}';
      final file = File(savePath);
      if (!await file.exists()) {
        final dio = Dio();
        await dio.download(url, savePath);
      }
      await OpenFilex.open(savePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to open file: $e')));
    }
  }

  Widget _buildMessageBubble(ChatMessage m) {
    final align = m.fromAdmin ? Alignment.centerLeft : Alignment.centerRight;
    final color = m.fromAdmin ? Colors.grey.shade200 : Theme.of(context).colorScheme.primary.withOpacity(.15);

    final timeString = TimeOfDay.fromDateTime(m.ts).format(context);

    Widget content;
    switch (m.type) {
      case 'image':
        content = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openMedia(m.text, fileName: m.fileName ?? 'image.jpg'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(m.text, width: 180, height: 180, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 80)),
          ),
        );
        break;
      case 'video':
        content = TextButton.icon(icon: const Icon(Icons.play_circle_fill), label: Text(m.fileName ?? 'Play Video'), onPressed: () => _openMedia(m.text, fileName: m.fileName ?? 'video.mp4'));
        break;
      case 'file':
        content = TextButton.icon(icon: const Icon(Icons.download), label: Text(m.fileName ?? 'Download File'), onPressed: () => _openMedia(m.text, fileName: m.fileName ?? 'file'));
        break;
      default:
        content = Text(m.text);
    }

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: m.fromAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            content,
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: m.fromAdmin ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                Text(timeString, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                if (!m.fromAdmin) ...[const SizedBox(width: 3), const Icon(Icons.done_all, size: 14, color: Colors.blueAccent)],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadingBubble() {
    if (_uploadingFilePath == null || !_isUploading) return const SizedBox.shrink();

    final align = Alignment.centerRight;
    final color = Theme.of(context).colorScheme.primary.withOpacity(.15);
    final isImage = _uploadingFileType == 'image';

    Widget content;
    if (isImage) {
      content = ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_uploadingFilePath!), width: 180, height: 180, fit: BoxFit.cover));
    } else {
      content = Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [const Icon(Icons.insert_drive_file), const SizedBox(width: 8), Flexible(child: Text(_uploadingFilePath!.split('/').last, overflow: TextOverflow.ellipsis))],
        ),
      );
    }

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            content,
            // Dark overlay
            Positioned.fill(child: Container(decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(8)))),
            // Progress indicator
            ValueListenableBuilder<double>(
              valueListenable: _progressNotifier,
              builder:
                  (_, value, __) => SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [CircularProgressIndicator(value: value, strokeWidth: 4, color: Colors.white), if (value >= 1.0) const Icon(Icons.check_circle, color: Colors.white)],
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendAttachment(bool isImage) async {
    setState(() {
      _isUploading = false;
      _uploadingFilePath = null;
      _uploadingFileType = null;
      _progressNotifier.value = 0;
    });

    await _repo.sendAttachment(
      isImage: isImage,
      onPreviewReady: (path) {
        final ext = path.toLowerCase();
        String type = 'file';
        if (ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png')) {
          type = 'image';
        } else if (ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi') || ext.endsWith('.mkv')) {
          type = 'video';
        }

        setState(() {
          _isUploading = true;
          _uploadingFilePath = path;
          _uploadingFileType = type;
        });

        // Auto-scroll to bottom to show the upload
        Future.delayed(const Duration(milliseconds: 100), () => _scrollToBottom());
      },
      onProgress: (progress) {
        _progressNotifier.value = progress;
      },
    );

    // Clear uploading state
    setState(() {
      _isUploading = false;
      _uploadingFilePath = null;
      _uploadingFileType = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasUser = _repo.currentUserId.isNotEmpty;

    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping anywhere on screen
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Navigate to home tab (index 0) in bottom navigation
              StatefulNavigationShell.of(context).goBranch(0);
            },
          ),
          title: const Text('Chat with Admin'),
        ),
        body: _loadingUser
            ? const Center(child: CircularProgressIndicator())
            : !hasUser
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'Session Expired or Inactive',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Please log out and log in again with your phone number to access chat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () {
                              StatefulNavigationShell.of(context).goBranch(0);
                            },
                            child: const Text('Go to Home'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (scroll) {
                            if (scroll is UserScrollNotification) {
                              // In reverse mode, scrolling down (away from bottom) means moving forward
                              if (scroll.direction == ScrollDirection.reverse) {
                                _userScrolledUp = true;
                              } else if (scroll.direction == ScrollDirection.forward && _isNearBottom()) {
                                _userScrolledUp = false;
                              }
                            }
                            return false;
                          },
                          child: StreamBuilder<List<ChatMessage>>(
                            stream: _repo.stream(),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                                        const SizedBox(height: 12),
                                        const Text('Unable to connect to chat'),
                                        const SizedBox(height: 8),
                                        TextButton(
                                          onPressed: () => setState(() {}),
                                          child: const Text('Retry'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }

                              final msgs = snapshot.data ?? const <ChatMessage>[];

                    // ✅ Check visibility strictly using shell index
                    bool isChatTab = false;
                    try {
                      final shell = StatefulNavigationShell.of(context);
                      isChatTab = shell.currentIndex == 2;
                    } catch (_) {
                      // Fallback: assume visible if not in shell (e.g. standalone route)
                      isChatTab = true;
                    }

                    // Only mark seen if we are strictly on the chat tab
                    if (isChatTab && msgs.isNotEmpty) {
                      _markSeenSafe();
                    }

                    if (!_userScrolledUp && _isNearBottom() && msgs.length > _messages.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                    }

                    _messages = msgs;

                    if (msgs.isEmpty && !_isUploading) {
                      return const Center(child: Text('No messages yet.'));
                    }

                    // Calculate total items: messages + uploading bubble (if active)
                    final totalItems = msgs.length + (_isUploading ? 1 : 0);

                    return ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      reverse: true, // Start from bottom
                      itemCount: totalItems,
                      itemBuilder: (context, i) {
                        // In reverse mode, first item (i=0) is the latest/bottom item
                        // If uploading, show uploading bubble at i=0 (bottom)
                        if (i == 0 && _isUploading) {
                          return _buildUploadingBubble();
                        }

                        // Adjust index for messages (account for uploading bubble if present)
                        final msgIndex = _isUploading ? msgs.length - i : msgs.length - 1 - i;
                        return _buildMessageBubble(msgs[msgIndex]);
                      },
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.photo), onPressed: () => _pickAndSendAttachment(true)),
                    IconButton(icon: const Icon(Icons.attach_file), onPressed: () => _pickAndSendAttachment(false)),
                    Expanded(child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: 'Type a message...'))),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final text = _ctrl.text.trim();
                        if (text.isEmpty) return;
                        _ctrl.clear();
                        await _repo.sendUser(text);
                        Future.delayed(const Duration(milliseconds: 200), () => _scrollToBottom());
                      },
                      child: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
