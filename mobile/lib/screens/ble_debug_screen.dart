import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/debug/presentation/providers/debug_panel_provider.dart';
import 'package:linkless/features/debug/presentation/widgets/debug_record_button.dart';
import 'package:linkless/features/debug/presentation/widgets/debug_recording_tile.dart';
import 'package:linkless/features/debug/presentation/widgets/health_check_section.dart';

/// Debug panel screen with health check, record button, and recordings list.
///
/// Replaces the previous BLE debug screen with a streamlined debug panel
/// that surfaces backend health status, provides manual recording capability,
/// and lists debug recordings with playback, error display, and retranscribe.
///
/// Layout: single scrollable page with three sections top-to-bottom:
/// 1. Backend Health -- always visible status dots for all services
/// 2. Record Button -- tap to record/stop with timer and waveform
/// 3. Debug Recordings -- list of recordings with status and playback
class BleDebugScreen extends ConsumerStatefulWidget {
  const BleDebugScreen({super.key});

  @override
  ConsumerState<BleDebugScreen> createState() => _BleDebugScreenState();
}

class _BleDebugScreenState extends ConsumerState<BleDebugScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-refresh health check when panel opens.
    // Use addPostFrameCallback to avoid modifying providers during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(healthCheckProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final debugConversations = ref.watch(debugConversationListProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('Debug Panel'),
        backgroundColor: AppColors.backgroundDarker,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section 1: Health Check (always visible)
            const HealthCheckSection(),
            const SizedBox(height: 20),

            // Section 2: Record Button
            const DebugRecordButton(),
            const SizedBox(height: 20),

            // Section 3: Recordings List
            const Text(
              'Debug Recordings',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            debugConversations.when(
              data: (conversations) {
                if (conversations.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundCard,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'No debug recordings yet.\nTap Record to create one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }
                return Column(
                  children: conversations
                      .map((c) => DebugRecordingTile(conversation: c))
                      .toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.backgroundCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Error loading recordings: $e',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
