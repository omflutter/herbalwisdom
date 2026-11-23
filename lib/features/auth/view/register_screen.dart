import 'dart:async'; // for Timer
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../common/widgets/auth_frame.dart';
import '../../../common/widgets/google_mark.dart';
import '../controller/auth_controller.dart';
import '../widgets/email_verify_sheets.dart';
import '../../notifications/view/notifcation_prefs_screen.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  static const routePath = '/register';
  static const routeName = 'register';

  // Accept extras from GoRouter (we'll pass {'postOtp': true, 'phone': '...'})
  final Map<String, dynamic>? extra;
  const RegisterScreen({super.key, this.extra});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _auth = AuthController();

  bool _agree = true;
  bool _busy = false;

  // Mode flags
  late final bool _postOtpMode; // when true: phone is verified, no OTP, call /register-user directly
  late final String _verifiedPhone; // phone from OTP screen (read-only)

  // Step variables for email verification
  bool _isVerified = false;
  bool _verifiedByGoogle = false;
  String? _lastCodeSentTo;
  bool _googleBusy = false;
  Timer? _verificationTimer;

  String? _verificationId;

  @override
  void initState() {
    super.initState();
    _postOtpMode = (widget.extra?['postOtp'] == true);
    _verifiedPhone = (widget.extra?['phone'] ?? '').toString();

    if (_postOtpMode && _verifiedPhone.isNotEmpty) {
      _phone.text = _verifiedPhone;
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _verificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    // Not verified yet? Ask how to verify, then carry on creating the account automatically.
    if (_postOtpMode && !_isVerified) {
      final verified = await _verifyEmailFlow(beforeCreate: true);
      if (!verified || !mounted) return;
    }

    if (!_form.currentState!.validate()) return;

    if (_postOtpMode) {
      // Phone is already verified by OTP screen; just register
      setState(() => _busy = true);
      final result = await _auth.registerAfterLoginNotFound(firstName: _first.text.trim(), lastName: _last.text.trim(), email: _email.text.trim(), phone: _verifiedPhone);
      setState(() => _busy = false);

      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created 🎉')));
        context.go(NotificationPrefsScreen.routePath); // go to alerts tab (index 3)
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      }
      return;
    }

    // -------- Normal flow (pre-OTP): send OTP with warning if email not verified yet logic?
    // Actually, user wants "user cannot register until the email is not verified" which implies the actual registration API call.
    // So blocking _postOtpMode logic (above) is correct.
    // However, if normal flow (just sending OTP), we don't strictly *need* email verified YET,
    // but better to encourage it. Let's stick to blocking only the FINAL registration step.

    // -------- Normal flow (pre-OTP): send OTP and continue as before --------
    if (!_agree) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please agree to Terms & Privacy Policy.')));
      return;
    }

    setState(() => _busy = true);
    await _auth.startOtpLogin(
      phone: "+91${_phone.text.trim()}",
      onCodeSent: (id) {
        _verificationId = id;
        setState(() => _busy = false);
        context.push(
          '${OtpScreen.routePath}?phone=${Uri.encodeComponent(_phone.text.trim())}&from=${Uri.encodeComponent(RegisterScreen.routePath)}',
          extra: {'verificationId': id, 'name': '${_first.text.trim()} ${_last.text.trim()}', 'email': _email.text.trim()},
        );
      },
      onError: (error) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      },
    );
  }

  // ---------------- Email verification (Google or emailed code) ----------------

  /// Asks how to verify (Google or code) and runs it. Returns true once the email is verified.
  Future<bool> _verifyEmailFlow({bool beforeCreate = false}) async {
    if (_isVerified) return true;
    final choice = await showEmailVerifyChoiceSheet(context, initialEmail: _email.text, beforeCreate: beforeCreate);
    if (choice == null || !mounted) return false;
    if (choice.useGoogle) return _verifyWithGoogle();
    setState(() => _email.text = choice.email);
    return _verifyWithEmailCode(choice.email, beforeCreate: beforeCreate);
  }

  /// Emails a code, then shows the code sheet. "Use Google instead" switches to Google.
  Future<bool> _verifyWithEmailCode(String email, {bool beforeCreate = false}) async {
    setState(() => _busy = true);
    final res = await _auth.sendEmailOtp(email);
    if (!mounted) return false;
    setState(() => _busy = false);

    final alreadySent = !res.ok && res.retryAfter > 0 && _lastCodeSentTo == email.toLowerCase();
    if (!res.ok && !alreadySent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
      return false;
    }
    _lastCodeSentTo = email.toLowerCase();

    final outcome = await showEmailCodeSheet(
      context,
      email: email,
      initialCooldown: res.retryAfter,
      verifyLabel: beforeCreate ? 'Verify & create account' : 'Verify',
      onVerify: (code) async => await _auth.verifyEmailOtp(email, code) ? null : 'That code is wrong or has expired.',
      onResend: () async {
        final r = await _auth.sendEmailOtp(email);
        return (r.ok, r.message, r.retryAfter);
      },
    );
    if (!mounted) return false;

    if (outcome == EmailCodeOutcome.switchToGoogle) return _verifyWithGoogle();
    if (outcome != EmailCodeOutcome.verified) return false;

    setState(() {
      _isVerified = true;
      _verifiedByGoogle = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verified ✅')));
    return true;
  }

  /// Verify with Google: uses (and fills in) the Google account's email.
  Future<bool> _verifyWithGoogle() async {
    setState(() => _googleBusy = true);
    final res = await _auth.verifyEmailWithGoogle();
    if (!mounted) return false;
    setState(() => _googleBusy = false);
    if (res.cancelled) return false;
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message ?? 'Google could not verify your email.')));
      return false;
    }
    setState(() {
      _email.text = res.email!;
      if (_first.text.trim().isEmpty) _first.text = res.firstName;
      if (_last.text.trim().isEmpty) _last.text = res.lastName;
      _isVerified = true;
      _verifiedByGoogle = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verified with Google ✅')));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final phoneReadOnly = _postOtpMode; // lock phone field if coming from OTP

    return Scaffold(
      body: AuthFrame(
        title: _postOtpMode ? 'Finish your account' : 'Create your account',
        subtitle: _postOtpMode ? 'We found no account for this number. Add your details to continue.' : 'Join the Herbal Wisdom membership.',
        heroImageUrl: 'https://images.unsplash.com/photo-1505577058444-a3dab90d4253?w=1600',
        topRightAction: IconButton(tooltip: 'Back', onPressed: () => context.pop(), icon: const Icon(Icons.close)),
        form: Form(
          key: _form,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _first,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'First name', prefixIcon: Icon(Icons.person_outline)),
                      validator: _auth.validateFirst,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _last,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Last name', prefixIcon: Icon(Icons.person_outline)),
                      validator: _auth.validateLast,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                readOnly: _isVerified,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                validator: _auth.validateEmail,
              ),
              if (_postOtpMode && !_isVerified) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: (_busy || _googleBusy) ? null : () => _verifyEmailFlow(),
                    icon: _googleBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Verify email'),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const GoogleMark(size: 13),
                    const SizedBox(width: 6),
                    Text('With Google or a code sent to your email', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ] else if (_postOtpMode && _isVerified) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_verifiedByGoogle ? 'Email verified with Google' : 'Email verified', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => setState(() {
                        _isVerified = false;
                        _verifiedByGoogle = false;
                      }),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Phone: editable in normal mode, read-only in post-OTP mode
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                readOnly: phoneReadOnly,
                enabled: !phoneReadOnly,
                decoration: InputDecoration(labelText: 'Mobile number', prefixIcon: const Icon(Icons.phone_outlined), helperText: _postOtpMode ? 'Phone verified via OTP' : null),
                validator: _postOtpMode ? (_) => null : _auth.validatePhone,
              ),

              if (!_postOtpMode) ...[
                const SizedBox(height: 8),
                Row(children: [Checkbox(value: _agree, onChanged: (v) => setState(() => _agree = v ?? false)), const Flexible(child: Text('I agree to the Terms & Privacy Policy'))]),
              ],

              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_postOtpMode ? 'Create account' : 'Send OTP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
