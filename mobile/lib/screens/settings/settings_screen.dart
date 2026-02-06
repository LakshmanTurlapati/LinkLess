import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/ble_proximity_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final bleState = ref.watch(bleProximityServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // BLE Settings
          _sectionHeader(context, 'Proximity Detection'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Bluetooth Scanning'),
                  subtitle: const Text('Detect nearby LinkLess users'),
                  secondary: Icon(
                    Icons.bluetooth,
                    color: bleState.isScanning
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  value: bleState.isScanning,
                  onChanged: (enabled) {
                    final service =
                        ref.read(bleProximityServiceProvider.notifier);
                    if (enabled) {
                      service.startProximityDetection();
                    } else {
                      service.stopProximityDetection();
                    }
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Auto-Record'),
                  subtitle: const Text(
                    'Automatically start recording when a nearby user is detected',
                  ),
                  secondary: const Icon(Icons.mic),
                  value: true, // TODO: make this configurable
                  onChanged: (enabled) {
                    // TODO: implement toggle
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Transcription Settings
          _sectionHeader(context, 'Transcription'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('AI Provider'),
                  subtitle: const Text('OpenAI Whisper'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: AI provider selection
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Language'),
                  subtitle: const Text('Auto-detect'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: language selection
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Notifications
          _sectionHeader(context, 'Notifications'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Encounter Notifications'),
                  subtitle: const Text('Notify when a new encounter starts'),
                  secondary: const Icon(Icons.notifications_outlined),
                  value: true,
                  onChanged: (enabled) {
                    // TODO: implement
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Summary Ready'),
                  subtitle: const Text(
                      'Notify when AI summary is generated'),
                  secondary: const Icon(Icons.summarize_outlined),
                  value: true,
                  onChanged: (enabled) {
                    // TODO: implement
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // About
          _sectionHeader(context, 'About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Version'),
                  subtitle: const Text('1.0.0'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () {
                    // TODO: open privacy policy
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () {
                    // TODO: open ToS
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Logout
          FilledButton.tonal(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out'),
                  content:
                      const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                ref.read(authServiceProvider.notifier).logout();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
              foregroundColor: colorScheme.onErrorContainer,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Sign Out'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
