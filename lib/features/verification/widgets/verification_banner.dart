import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../models/verification_status.dart';

/// Top-of-app notice telling the user which of email / phone is verified, asking them to
/// verify their email. Pure UI: the host decides when to show it.
class VerificationBanner extends StatelessWidget {
  final VerificationStatus status;
  final VoidCallback onVerify;
  final VoidCallback? onDismiss;

  const VerificationBanner({super.key, required this.status, required this.onVerify, this.onDismiss});

  static const _bg = Color(0xFFFFF5E1);
  static const _border = Color(0xFFF1D29C);
  static const _accent = Color(0xFFB4741A);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final emailIssue = !status.emailVerified;

    final title = emailIssue ? 'Please verify your email' : 'Please verify your phone number';
    final body =
        emailIssue
            ? 'Verify your email address to use the app properly and get your specials, updates and account help.'
            : 'Sign out and sign back in with your mobile number to verify it.';

    return Material(
      color: _bg,
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _accent.withValues(alpha: .12), shape: BoxShape.circle),
              child: Icon(emailIssue ? Icons.mark_email_unread_outlined : Icons.phone_iphone, color: _accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(body, style: t.bodySmall?.copyWith(color: AppColors.ink.withValues(alpha: .75), height: 1.3)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      VerificationChip(label: 'Email', verified: status.emailVerified),
                      VerificationChip(label: 'Phone', verified: status.phoneVerified, missing: !status.hasPhone),
                    ],
                  ),
                  if (emailIssue) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 36,
                      child: FilledButton.icon(
                        onPressed: onVerify,
                        style: FilledButton.styleFrom(backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 14), textStyle: const TextStyle(fontWeight: FontWeight.w600)),
                        icon: const Icon(Icons.verified_outlined, size: 18),
                        label: const Text('Verify email now'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Remind me later',
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: Icon(Icons.close, size: 18, color: AppColors.ink.withValues(alpha: .55)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small "Email verified / not verified" pill.
class VerificationChip extends StatelessWidget {
  final String label;
  final bool verified;
  final bool missing;
  const VerificationChip({super.key, required this.label, required this.verified, this.missing = false});

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    final IconData icon;
    final String text;
    if (missing) {
      fg = const Color(0xFF5F6B64);
      bg = const Color(0xFFECEFEC);
      icon = Icons.remove_circle_outline;
      text = '$label not added';
    } else if (verified) {
      fg = const Color(0xFF2E6B3F);
      bg = AppColors.mint;
      icon = Icons.check_circle;
      text = '$label verified';
    } else {
      fg = const Color(0xFFB23B2E);
      bg = const Color(0xFFFBE3DF);
      icon = Icons.error_outline;
      text = '$label not verified';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}
