import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:herbalwisdom/features/auth/view/register_screen.dart';
import 'package:herbalwisdom/features/home/view/home_screen.dart';
import '../controller/auth_controller.dart';
import '../../notifications/view/notifcation_prefs_screen.dart';

class OtpScreen extends StatefulWidget {
  static const routePath = '/otp';
  static const routeName = 'otp';
  final String? phoneNumber;
  final String? fromRoute;
  final Map<String, dynamic>? extra;

  const OtpScreen({super.key, this.phoneNumber, this.fromRoute, this.extra});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpCtrl = TextEditingController();
  final _auth = AuthController();
  bool _busy = false;

  // Timer state for resend OTP
  Timer? _timer;
  int _secondsRemaining = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _secondsRemaining = 60;
      _canResend = false;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    final verificationId = widget.extra?['verificationId'];
    final phone = widget.phoneNumber ?? (widget.extra?['phone'] ?? '');

    if (verificationId == null || verificationId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification ID missing. Please request OTP again.')));
      return;
    }
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter 6-digit OTP')));
      return;
    }

    setState(() => _busy = true);

    // 1) Verify on Firebase
    final ok = await _auth.verifyOtpFirebase(verificationId: verificationId, code: code, phone: phone, name: widget.extra?['name'] ?? '', email: widget.extra?['email'] ?? '');

    if (!ok) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid OTP ❌')));
      return;
    }

    // 2) Login with backend
    final outcome = await _auth.tryLogin(phone);

    if (outcome == LoginOutcome.success) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Welcome back! ✅')));
      context.go(HomeScreen.routePath); // Navigate to Alerts screen after login
      return;
    }

    if (outcome == LoginOutcome.notFound) {
      // Navigate to Register screen with the verified phone
      if (!mounted) return;
      setState(() => _busy = false);

      context.push(
        RegisterScreen.routePath,
        extra: {
          'postOtp': true, // tell the screen to skip OTP and call /register-user
          'phone': phone, // already verified phone
        },
      );
      return;
    }

    // outcome == error
    setState(() => _busy = false);
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;

    final phone = widget.phoneNumber ?? (widget.extra?['phone'] ?? '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number not found. Please go back and try again.')));
      return;
    }

    setState(() => _busy = true);

    try {
      await _auth.startOtpLogin(
        phone: phone,
        onCodeSent: (verificationId) {
          if (!mounted) return;

          // Update the verification ID
          if (widget.extra != null) {
            widget.extra!['verificationId'] = verificationId;
          }

          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New OTP sent successfully! ✅')));

          // Restart timer
          _startTimer();
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to resend OTP: $error')));
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<bool?> _showRegistrationDialog(BuildContext context, String phone) async {
    final formKey = GlobalKey<FormState>();
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // RESTRICT: must provide details
      builder: (_) {
        return AlertDialog(
          title: const Text('Complete your profile'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('We couldn’t find an account for $phone. Please enter your details to continue.'),
                const SizedBox(height: 12),
                TextFormField(controller: firstCtrl, decoration: const InputDecoration(labelText: 'First name'), validator: (v) => _auth.validateFirst(v)),
                const SizedBox(height: 8),
                TextFormField(controller: lastCtrl, decoration: const InputDecoration(labelText: 'Last name'), validator: (v) => _auth.validateLast(v)),
                const SizedBox(height: 8),
                TextFormField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress, validator: (v) => _auth.validateEmail(v)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Do not allow skipping (strict)
                // If you still want a cancel, keep but just close app or go back.
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                // Call register
                final result = await _auth.registerAfterLoginNotFound(firstName: firstCtrl.text.trim(), lastName: lastCtrl.text.trim(), email: emailCtrl.text.trim(), phone: phone);
                if (!context.mounted) return;
                if (result.success) {
                  Navigator.of(context).pop(true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
                }
              },
              child: const Text('Create account'),
            ),
          ],
        );
      },
    );

    return done;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Enter OTP sent to ${widget.phoneNumber ?? ''}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: '6-digit OTP', prefixIcon: Icon(Icons.sms_outlined), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _busy ? null : _verify, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verify')),
            ),
            const SizedBox(height: 20),
            // Resend OTP section
            if (_canResend)
              TextButton(onPressed: _busy ? null : _resendOtp, child: const Text('Resend OTP'))
            else
              Opacity(opacity: 0.6, child: Text('Resend OTP in 0:${_secondsRemaining.toString().padLeft(2, '0')}', style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
