import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

/// Root navigator key for the app shell.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Provides the app-level GoRouter configuration.
///
/// Uses StatefulShellRoute.indexedStack for bottom tab navigation
/// with three branches: Conversations, Map, Profile.
@riverpod
GoRouter appRouter(Ref ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/conversations',
    routes: [
      // Placeholder -- full StatefulShellRoute added in Task 2
      GoRoute(
        path: '/conversations',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Loading...')),
        ),
      ),
    ],
  );
}
