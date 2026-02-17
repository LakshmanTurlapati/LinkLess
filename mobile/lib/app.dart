import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/providers/app_init_provider.dart';
import 'package:linkless/core/theme/app_theme.dart';
import 'package:linkless/features/proximity/presentation/widgets/live_recording_banner.dart';
import 'package:linkless/features/proximity/presentation/widgets/live_recording_overlay.dart';
import 'package:linkless/features/recording/presentation/providers/live_recording_provider.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';
import 'package:linkless/features/sync/presentation/providers/sync_provider.dart';
import 'package:linkless/router/app_router.dart';

class LinkLessApp extends ConsumerWidget {
  const LinkLessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    ref.watch(syncEngineProvider);
    ref.watch(recordingServiceProvider);
    ref.watch(appInitProvider);
    ref.watch(liveRecordingStateListenerProvider);

    return MaterialApp.router(
      title: 'LinkLess',
      theme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return _LiveRecordingShell(child: child!);
      },
    );
  }
}

class _LiveRecordingShell extends ConsumerWidget {
  final Widget child;

  const _LiveRecordingShell({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showOverlay = ref.watch(liveRecordingOverlayProvider);
    final showBanner = ref.watch(liveRecordingBannerProvider);

    return Stack(
      children: [
        child,
        if (showBanner) const LiveRecordingBanner(),
        if (showOverlay) const LiveRecordingOverlay(),
      ],
    );
  }
}
