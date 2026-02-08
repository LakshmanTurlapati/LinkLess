import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/profile/presentation/providers/invisible_mode_provider.dart';

/// Toggle switch for invisible mode on the profile screen.
///
/// When invisible mode is enabled, BLE scanning and advertising are paused
/// so the user is not discoverable by nearby peers. The toggle persists
/// across app restarts via SharedPreferences.
class InvisibleModeToggle extends ConsumerWidget {
  const InvisibleModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInvisible = ref.watch(invisibleModeProvider);
    final authState = ref.watch(authProvider);
    final userId = authState.user?.id;

    return SwitchListTile(
      title: const Text('Invisible Mode'),
      subtitle: const Text('Pause proximity detection'),
      secondary: Icon(
        isInvisible
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
      value: isInvisible,
      onChanged: (value) {
        ref
            .read(invisibleModeProvider.notifier)
            .toggle(value, userId: userId);
      },
    );
  }
}
