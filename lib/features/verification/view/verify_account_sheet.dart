import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/colors.dart';
import '../../../common/widgets/google_mark.dart';
import '../models/verification_status.dart';
import '../repo/verification_actions.dart';
import '../widgets/verification_banner.dart';

/// Opens the "Verify your account" bottom sheet. Resolves to true once the email is verified.
Future<bool?> showVerifyAccountSheet(BuildContext context, {required VerificationStatus status, required VerificationActions actions}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => VerifyAccountSheet(status: status, actions: actions),
  );
}

class VerifyAccountSheet extends StatefulWidget {
  final VerificationStatus status;
  final VerificationActions actions;

  /// For previews/screenshots: start with the code already sent.
  final bool initialCodeSent;

  const VerifyAccountSheet({super.key, required this.status, required this.actions, this.initialCodeSent = false});

  @override
  State<VerifyAccountSheet> createState() => _VerifyAccountSheetState();
}

class _VerifyAccountSheetState extends State<VerifyAccountSheet> {
  late VerificationStatus _status = widget.status;
  late final _emailCtrl = TextEditingController(text: widget.status.email);
  final _codeCtrl = TextEditingController();

  late bool _codeSent = widget.initialCodeSent;
  String _codeSentTo = '';
  bool _busyCode = false;
  bool _busyGoogle = false;
  String? _error;

  bool get _busy => _busyCode || _busyGoogle;

  @override
  void initState() {
    super.initState();
    if (_codeSent) _codeSentTo = widget.status.email;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _busyCode = true;
      _error = null;
    });
    final res = await widget.actions.sendEmailCode(email);
    if (!mounted) return;
    setState(() {
      _busyCode = false;
      if (res.ok) {
        _codeSent = true;
        _codeSentTo = email;
        _codeCtrl.clear();
      } else {
        _error = res.message.isNotEmpty ? res.message : 'Could not send the code. Please try again.';
      }
    });
  }

  Future<void> _confirmCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _busyCode = true;
      _error = null;
    });
    final res = await widget.actions.confirmEmailCode(_codeSentTo, code);
    if (!mounted) return;
    setState(() => _busyCode = false);
    _handleResult(res);
  }

  Future<void> _verifyWithGoogle({bool allowEmailChange = false}) async {
    setState(() {
      _busyGoogle = true;
      _error = null;
    });
    final res = await widget.actions.verifyWithGoogle(allowEmailChange: allowEmailChange);
    if (!mounted) return;
    setState(() => _busyGoogle = false);

    if (res.needsEmailChangeConfirmation) {
      final use = await _confirmEmailChange(res.googleEmail ?? '');
      if (use == true) await _verifyWithGoogle(allowEmailChange: true);
      return;
    }
    _handleResult(res);
  }

  void _handleResult(VerificationResult res) {
    if (res.cancelled) return;
    if (res.ok) {
      setState(() => _status = res.updated ?? _status);
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = res.message.isNotEmpty ? res.message : 'Verification failed. Please try again.');
  }

  Future<bool?> _confirmEmailChange(String googleEmail) {
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Use your Google email?'),
            content: Text(
              'Your Google account uses $googleEmail, but your Herbal Wisdom account email is ${_status.email.isEmpty ? '(none)' : _status.email}.\n\n'
              'Do you want to use $googleEmail as your account email? It will be verified straight away.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, keep mine')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use Google email')),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Verify your account', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(
              'Please verify your email so you can use the app properly. We use it for your specials, important updates and to help you recover your account.',
              style: t.bodyMedium?.copyWith(color: AppColors.ink.withValues(alpha: .7), height: 1.35),
            ),
            const SizedBox(height: 16),
            _StatusCard(status: _status),
            const SizedBox(height: 20),
            Text('Choose how to verify your email', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 10),

            // Option 1: Google
            _OptionCard(
              icon: const GoogleMark(size: 22),
              title: 'Verify with Google',
              subtitle: 'Fastest. We\'ll use the verified email of the Google account you choose.',
              badge: 'Recommended',
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _verifyWithGoogle(),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: _busyGoogle ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const GoogleMark(size: 18),
                  label: const Text('Continue with Google'),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Option 2: email code
            _OptionCard(
              icon: const Icon(Icons.mark_email_read_outlined, color: AppColors.primary),
              title: 'Get a code by email',
              subtitle: 'We\'ll email you a 6-digit code. Missing or wrong email? Enter the right one below.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _emailCtrl,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined), border: OutlineInputBorder(), isDense: true),
                    onChanged: (_) {
                      if (_codeSent && _emailCtrl.text.trim() != _codeSentTo) setState(() => _codeSent = false);
                    },
                  ),
                  const SizedBox(height: 10),
                  if (!_codeSent)
                    FilledButton(
                      onPressed: _busy ? null : _sendCode,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: _busyCode ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Send code'),
                    )
                  else ...[
                    Text('Code sent to $_codeSentTo. It\'s valid for 10 minutes.', style: t.bodySmall?.copyWith(color: AppColors.primary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeCtrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(letterSpacing: 6, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(labelText: '6-digit code', counterText: '', prefixIcon: Icon(Icons.pin_outlined), border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton(onPressed: _busy ? null : _sendCode, child: const Text('Resend code')),
                        const Spacer(),
                        FilledButton(
                          onPressed: _busy ? null : _confirmCode,
                          child: _busyCode ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Verify code'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFBE3DF), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFB23B2E), size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFB23B2E)))),
                  ],
                ),
              ),
            ],

            if (_status.phoneNeedsVerification) ...[
              const SizedBox(height: 16),
              Text(
                'Your phone number is verified automatically the next time you sign in with it.',
                style: t.bodySmall?.copyWith(color: AppColors.ink.withValues(alpha: .6)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final VerificationStatus status;
  const _StatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E8E3))),
      child: Column(
        children: [
          _row(context, Icons.email_outlined, status.email.isEmpty ? 'No email added' : status.email, VerificationChip(label: 'Email', verified: status.emailVerified, missing: status.email.isEmpty)),
          const Divider(height: 18),
          _row(context, Icons.phone_outlined, status.hasPhone ? status.phone : 'No phone number', VerificationChip(label: 'Phone', verified: status.phoneVerified, missing: !status.hasPhone)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String value, Widget chip) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.ink.withValues(alpha: .6)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
        const SizedBox(width: 8),
        chip,
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final String? badge;
  final Widget child;
  const _OptionCard({required this.icon, required this.title, required this.subtitle, required this.child, this.badge});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDDE3DD))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 28, child: Center(child: icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
                            child: Text(badge!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2E6B3F))),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: t.bodySmall?.copyWith(color: AppColors.ink.withValues(alpha: .65), height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
