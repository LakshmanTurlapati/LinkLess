import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/providers/app_init_provider.dart';
import 'package:linkless/core/theme/app_theme.dart';
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

    return MaterialApp.router(
      title: 'LinkLess',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
