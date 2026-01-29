import 'dart:async'; // for Timer
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../common/widgets/auth_frame.dart';
import '../controller/auth_controller.dart';
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
  bool _verificationSent = false;
  bool _isVerified = false;
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
    if (!_form.currentState!.validate()) return;

    if (_postOtpMode) {
      if (!_isVerified) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please verify your email to continue.')));
        return;
      }
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

  Future<void> _sendVerification() async {
    final email = _email.text.trim();
    if (email.isEmpty || _auth.validateEmail(email) != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid email first')));
      return;
    }

    setState(() => _busy = true);
    final sent = await _auth.sendEmailOtp(email);
    setState(() => _busy = false);

    if (sent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OTP sent to $email')));

      // Show OTP Input Dialog
      _showEmailOtpDialog(email);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send OTP. Please try again.')));
    }
  }

  // Show Email OTP Dialog
  void _showEmailOtpDialog(String email) {
    final otpCtrl = TextEditingController();
    bool localBusy = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Verify Email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Enter the code sent to $email'),
                  const SizedBox(height: 12),
                  TextField(controller: otpCtrl, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'OTP')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
                FilledButton(
                  onPressed:
                      localBusy
                          ? null
                          : () async {
                            final code = otpCtrl.text.trim();
                            if (code.length < 4) return;

                            setDialogState(() => localBusy = true);
                            final ok = await _auth.verifyEmailOtp(email, code);
                            setDialogState(() => localBusy = false);

                            if (ok) {
                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              setState(() {
                                _isVerified = true;
                                _verificationSent = true;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email verified! ✅')));
                            } else {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid code')));
                            }
                          },
                  child: localBusy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );
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
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                validator: _auth.validateEmail,
              ),
              if (_postOtpMode && !_isVerified) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child:
                      _verificationSent
                          ? TextButton.icon(
                            onPressed: null, // polling will handle it
                            icon: const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                            label: const Text('Verifying... (check inbox)'),
                          )
                          : TextButton(onPressed: _sendVerification, child: const Text('Verify Email')),
                ),
              ] else if (_postOtpMode && _isVerified) ...[
                const SizedBox(height: 6),
                const Align(alignment: Alignment.centerRight, child: Text('✅ Email Verified', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
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
