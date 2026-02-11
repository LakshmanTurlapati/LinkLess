import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';

/// Screen where users enter the 4-digit OTP sent to their phone.
///
/// Features:
/// - Pinput widget with SMS autofill support
/// - Masked phone number display
/// - Resend code button with 60s countdown
/// - Inline error message below the pin input
class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String phoneNumber;

  const OtpVerificationScreen({super.key, required this.phoneNumber});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState
    extends ConsumerState<OtpVerificationScreen> {
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _resendTimer;
  int _resendCountdown = 60;
  bool _canResend = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  /// Masks the phone number, showing only the last 4 digits.
  /// Example: +1234567890 -> *******7890
  String get _maskedPhone {
    final phone = widget.phoneNumber;
    if (phone.length <= 4) return phone;
    final visible = phone.substring(phone.length - 4);
    final masked = '*' * (phone.length - 4);
    return '$masked$visible';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    // Listen for error state changes.
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        setState(() {
          _errorText = next.errorMessage;
        });
        _pinController.clear();
        ref.read(authProvider.notifier).clearError();
      }
      // On authenticated, GoRouter redirect handles navigation.
    });

    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColors.backgroundDark,
          ),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _errorText != null
              ? AppColors.error
              : const Color(0xFFD0D0D0),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Verify Phone'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.backgroundDark,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                'Enter verification code',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.backgroundDark,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a 4-digit code to\n$_maskedPhone',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Center(
                child: Pinput(
                  controller: _pinController,
                  focusNode: _focusNode,
                  length: 4,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: defaultPinTheme.copyWith(
                    decoration: BoxDecoration(
                      color: AppColors.inputBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.accentBlue,
                        width: 2,
                      ),
                    ),
                  ),
                  enabled: !isLoading,
                  autofocus: true,
                  onCompleted: (pin) => _onVerify(pin),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _pinController.text.length == 4
                      ? () => _onVerify(_pinController.text)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.backgroundDark,
                    foregroundColor: Colors.white,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Verify'),
                  ),
                ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _canResend && !isLoading ? _onResend : null,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.backgroundDark,
                  ),
                  child: Text(
                    _canResend
                        ? 'Resend Code'
                        : 'Resend in ${_resendCountdown}s',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onVerify(String code) {
    setState(() {
      _errorText = null;
    });
    ref.read(authProvider.notifier).verifyOtp(code);
  }

  void _onResend() {
    _pinController.clear();
    setState(() {
      _errorText = null;
    });
    _startResendTimer();
    ref.read(authProvider.notifier).sendOtp(widget.phoneNumber);
  }
}
