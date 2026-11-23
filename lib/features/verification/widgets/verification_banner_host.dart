import 'package:flutter/material.dart';

import '../models/verification_status.dart';
import '../repo/verification_repo.dart';
import '../view/verify_account_sheet.dart';
import 'verification_banner.dart';

/// Loads the user's verification status and shows [VerificationBanner] above [child] until the
/// account is verified. "Remind me later" hides it until the next app start.
class VerificationBannerHost extends StatefulWidget {
  final Widget child;
  const VerificationBannerHost({super.key, required this.child});

  @override
  State<VerificationBannerHost> createState() => _VerificationBannerHostState();
}

class _VerificationBannerHostState extends State<VerificationBannerHost> with WidgetsBindingObserver {
  static bool _dismissedThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VerificationRepo.instance.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Picks up changes made elsewhere (e.g. admin marked the email verified).
    if (state == AppLifecycleState.resumed) VerificationRepo.instance.refresh();
  }

  Future<void> _openSheet(VerificationStatus status) async {
    final verified = await showVerifyAccountSheet(context, status: status, actions: VerificationRepo.instance);
    if (verified == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks! Your email is verified ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VerificationStatus?>(
      valueListenable: VerificationRepo.status,
      builder: (context, status, _) {
        final show = status != null && status.needsAttention && !_dismissedThisSession;
        if (!show) return widget.child;

        return Column(
          children: [
            // Banner owns the status-bar inset; the screens below no longer need it.
            ColoredBox(
              color: const Color(0xFFFFF5E1),
              child: SafeArea(
                bottom: false,
                child: VerificationBanner(
                  status: status,
                  onVerify: () => _openSheet(status),
                  onDismiss: () => setState(() => _dismissedThisSession = true),
                ),
              ),
            ),
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
          ],
        );
      },
    );
  }
}
