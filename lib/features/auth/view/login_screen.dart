import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../common/widgets/back_exit_guard.dart';
import '../../../common/widgets/auth_frame.dart';
import '../controller/auth_controller.dart';
import 'otp_screen.dart';

import 'package:country_code_picker/country_code_picker.dart';

class LoginScreen extends StatefulWidget {
  static const routePath = '/login';
  static const routeName = 'login';
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _auth = AuthController();
  bool _busy = false;
  String _countryCode = '+61';
  int _maxLength = 9;

  final Map<String, int> _countryMaxLength = {
    '+61': 10, // Australia (04xx xxx xxx)
    '+91': 10, // India
    '+1': 10, // USA/Canada
    '+44': 10, // UK
  };

  final Map<String, String> _countryHints = {
    '+61': '0412 345 678',
    '+91': '98765 43210',
    '+1': '202-555-0123',
    '+44': '7700 900077',
  };

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    // 🔎 log input
    var phoneInput = _phone.text.trim();
    if (phoneInput.startsWith('0')) {
      phoneInput = phoneInput.substring(1);
    }
    final rawPhone = '$_countryCode$phoneInput';
    debugPrint('🔎 [Login] Submit tapped with phone="$rawPhone"');

    setState(() => _busy = true);

    try {
      await _auth.startOtpLogin(
        phone: rawPhone,
        onCodeSent: (verificationId) {
          debugPrint('✅ [Login] onCodeSent verificationId=$verificationId');

          if (!mounted) {
            debugPrint('⚠️ [Login] Widget not mounted at onCodeSent');
            return;
          }
          setState(() => _busy = false);

          // Some crashes are from navigating during a build frame; schedule microtask:
          Future.microtask(() {
            if (!mounted) return;
            try {
              context.push(
                OtpScreen.routePath,
                extra: {
                  'verificationId': verificationId,
                  'phone': rawPhone,
                  'name': '',
                  'email': '',
                },
              );
            } catch (e, st) {
              debugPrint('💥 [Login] Navigation failed: $e\n$st');
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Navigation error: $e')));
            }
          });
        },
        onError: (error) {
          debugPrint('❌ [Login] onError: $error');
          if (!mounted) return;
          setState(() => _busy = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        },
      );
    } catch (e, st) {
      debugPrint('💥 [Login] _submit crashed: $e\n$st');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Login error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackExitGuard(
      child: Scaffold(
        body: AuthFrame(
          title: 'Welcome back',
          subtitle: 'Sign in using your mobile number to receive an OTP.',
          heroImageUrl: 'assets/icons/login_concept_hero.png',
          form: Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: _maxLength,
                  decoration: InputDecoration(
                    labelText: 'Mobile number',
                    counterText: '',
                    prefixIcon: CountryCodePicker(
                      onChanged: (country) {
                        setState(() {
                          _countryCode = country.dialCode ?? '+61';
                          _maxLength = _countryMaxLength[_countryCode] ?? 15;
                        });
                      },
                      initialSelection: 'AU',
                      favorite: const ['+61', 'AU'],
                      showCountryOnly: false,
                      showOnlyCountryWhenClosed: false,
                      alignLeft: false,
                    ),
                    hintText: _countryHints[_countryCode] ?? 'Mobile number',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter mobile number';

                    // Specific validation for Australia
                    if (_countryCode == '+61') {
                      if (v.length != 9 && v.length != 10)
                        return 'Enter a valid number';
                      if (v.length == 9 && !v.startsWith('4'))
                        return 'Australian numbers must start with 4';
                      if (v.length == 10 && !v.startsWith('04'))
                        return 'Australian numbers must start with 04';
                    } else {
                      // Default length check for other countries
                      if (v.length != _maxLength) return 'Enter a valid number';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child:
                        _busy
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text('Send OTP'),
                  ),
                ),
                const SizedBox(height: 10),
                const _TrustRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: .8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.lock_outline, size: 18),
          SizedBox(width: 6),
          Text('Secure login — OTP sent to your number'),
        ],
      ),
    );
  }
}
