import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_form_field/phone_form_field.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';

/// Screen where users enter their phone number to receive an OTP.
///
/// Uses [PhoneFormField] for international phone input with country selector.
/// On successful OTP send, navigates to the OTP verification screen.
class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = PhoneController(
    initialValue: const PhoneNumber(isoCode: IsoCode.US, nsn: ''),
  );
  bool _hasNavigated = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Listen for state changes to navigate or show errors.
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.status == AuthStatus.otpSent && !_hasNavigated) {
        _hasNavigated = true;
        final phone = next.phoneNumber;
        if (phone != null && mounted) {
          context.push('/auth/otp?phone=${Uri.encodeComponent(phone)}');
        }
      }
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        _hasNavigated = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.errorMessage!),
              behavior: SnackBarBehavior.floating,
            ),
          );
          ref.read(authProvider.notifier).clearError();
        }
      }
    });

    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Spacer(flex: 3),

                          // Logo and heading grouped as one unit
                          Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Image.asset(
                                'assets/Wordmark - No BG.png',
                                height: 320,
                                fit: BoxFit.contain,
                              ),
                              Positioned(
                                bottom: 50,
                                left: 0,
                                right: 0,
                                child: Text(
                                  "Let's get started",
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.backgroundDark,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Phone input with pill shape
                          PhoneFormField(
                            controller: _phoneController,
                            style: const TextStyle(
                                color: AppColors.backgroundDark),
                            countryButtonStyle: const CountryButtonStyle(
                              textStyle:
                                  TextStyle(color: AppColors.backgroundDark),
                              dropdownIconColor: AppColors.backgroundDark,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              labelStyle: const TextStyle(
                                  color: AppColors.backgroundDark),
                              filled: true,
                              fillColor: AppColors.inputBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: const BorderSide(
                                  color: AppColors.accentBlue,
                                  width: 2,
                                ),
                              ),
                            ),
                            countrySelectorNavigator:
                                const CountrySelectorNavigator
                                    .modalBottomSheet(),
                            validator: PhoneValidator.compose([
                              PhoneValidator.required(context),
                              PhoneValidator.validMobile(context),
                            ]),
                            enabled: !isLoading,
                          ),
                          const SizedBox(height: 24),

                          FilledButton(
                            onPressed: isLoading ? null : _onContinue,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.backgroundDark,
                              foregroundColor: Colors.white,
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Continue'),
                            ),
                          ),
                          const Spacer(flex: 3),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _onContinue() {
    if (_formKey.currentState?.validate() ?? false) {
      final phoneNumber = _phoneController.value;
      // Format as international E.164 string: +{countryCode}{nsn}
      final formatted = '+${phoneNumber.countryCode}${phoneNumber.nsn}';
      _hasNavigated = false;
      ref.read(authProvider.notifier).sendOtp(formatted);
    }
  }
}
