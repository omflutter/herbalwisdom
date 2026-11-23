import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/colors.dart';
import '../../../common/widgets/google_mark.dart';

/// What the user picked in [showEmailVerifyChoiceSheet].
class EmailVerifyChoice {
  final bool useGoogle;
  final String email; // set when useGoogle == false
  const EmailVerifyChoice.google() : useGoogle = true, email = '';
  const EmailVerifyChoice.email(this.email) : useGoogle = false;
}

/// "Verify your email" – choose Google or an emailed code.
/// [beforeCreate] tweaks the wording when opened from "Create account".
Future<EmailVerifyChoice?> showEmailVerifyChoiceSheet(BuildContext context, {String initialEmail = '', bool beforeCreate = false}) {
  return showModalBottomSheet<EmailVerifyChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => EmailVerifyChoiceSheet(initialEmail: initialEmail, beforeCreate: beforeCreate),
  );
}

class EmailVerifyChoiceSheet extends StatefulWidget {
  final String initialEmail;
  final bool beforeCreate;
  const EmailVerifyChoiceSheet({super.key, this.initialEmail = '', this.beforeCreate = false});

  @override
  State<EmailVerifyChoiceSheet> createState() => _EmailVerifyChoiceSheetState();
}

class _EmailVerifyChoiceSheetState extends State<EmailVerifyChoiceSheet> {
  late final _emailCtrl = TextEditingController(text: widget.initialEmail.trim());
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _emailMeACode() {
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    Navigator.pop(context, EmailVerifyChoice.email(email));
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
            Text('Verify your email', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(
              widget.beforeCreate
                  ? 'One quick step before we create your account. How would you like to verify your email?'
                  : 'How would you like to verify your email?',
              style: t.bodyMedium?.copyWith(color: AppColors.ink.withValues(alpha: .7), height: 1.35),
            ),
            const SizedBox(height: 20),

            // Google
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, const EmailVerifyChoice.google()),
                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), side: const BorderSide(color: Color(0xFFCBD3CB))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const GoogleMark(size: 20),
                    const SizedBox(width: 10),
                    Text('Continue with Google', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('Quickest – uses your Google account\'s email, no code needed.', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: AppColors.ink.withValues(alpha: .6))),

            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: t.bodySmall)),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 18),

            // Email code
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _emailMeACode(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(labelText: 'Your email', prefixIcon: const Icon(Icons.email_outlined), border: const OutlineInputBorder(), errorText: _error),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _emailMeACode,
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.mark_email_read_outlined, size: 20),
                label: const Text('Email me a code'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result of the code sheet.
enum EmailCodeOutcome { verified, switchToGoogle }

/// Enter the 6-digit code that was emailed. [onVerify] returns null when the code is right,
/// otherwise an error message. [onResend] returns (sent, message, retryAfterSeconds).
Future<EmailCodeOutcome?> showEmailCodeSheet(
  BuildContext context, {
  required String email,
  required Future<String?> Function(String code) onVerify,
  required Future<(bool, String, int)> Function() onResend,
  int initialCooldown = 60,
  String verifyLabel = 'Verify',
}) {
  return showModalBottomSheet<EmailCodeOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => EmailCodeSheet(email: email, onVerify: onVerify, onResend: onResend, initialCooldown: initialCooldown, verifyLabel: verifyLabel),
  );
}

class EmailCodeSheet extends StatefulWidget {
  final String email;
  final Future<String?> Function(String code) onVerify;
  final Future<(bool, String, int)> Function() onResend;
  final int initialCooldown;
  final String verifyLabel;

  const EmailCodeSheet({super.key, required this.email, required this.onVerify, required this.onResend, this.initialCooldown = 60, this.verifyLabel = 'Verify'});

  @override
  State<EmailCodeSheet> createState() => _EmailCodeSheetState();
}

class _EmailCodeSheetState extends State<EmailCodeSheet> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;
  Timer? _timer;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _startCooldown(widget.initialCooldown);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    _cooldown = seconds;
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final err = await widget.onVerify(code);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, EmailCodeOutcome.verified);
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final (sent, message, retryAfter) = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (sent) {
        _info = 'New code sent. Earlier codes no longer work.';
        _codeCtrl.clear();
      } else {
        _error = message;
      }
    });
    if (retryAfter > 0) setState(() => _startCooldown(retryAfter));
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
            Text('Check your email', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'We sent a 6-digit code to '),
                TextSpan(text: widget.email, style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: '. Can\'t see it? Check your spam or junk folder.'),
              ]),
              style: t.bodyMedium?.copyWith(color: AppColors.ink.withValues(alpha: .75), height: 1.35),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _codeCtrl,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.w700),
              onChanged: (v) {
                if (v.length == 6 && !_busy) _verify(); // auto-submit when complete
              },
              decoration: InputDecoration(hintText: '••••••', counterText: '', border: const OutlineInputBorder(), errorText: _error),
            ),
            if (_info != null) ...[
              const SizedBox(height: 6),
              Text(_info!, style: t.bodySmall?.copyWith(color: AppColors.primary)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _busy ? null : _verify,
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.verifyLabel),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(onPressed: (_busy || _cooldown > 0) ? null : _resend, child: Text(_cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend code')),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy ? null : () => Navigator.pop(context, EmailCodeOutcome.switchToGoogle),
                  icon: const GoogleMark(size: 16),
                  label: const Text('Use Google instead'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
