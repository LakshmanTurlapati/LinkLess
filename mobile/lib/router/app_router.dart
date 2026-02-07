import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:linkless/features/conversations/presentation/views/conversations_screen.dart';
import 'package:linkless/features/map/presentation/views/map_screen.dart';
import 'package:linkless/features/profile/presentation/views/profile_screen.dart';
import 'package:linkless/router/scaffold_with_nav_bar.dart';

part 'app_router.g.dart';

/// Root navigator key for the app shell.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Provides the app-level GoRouter configuration.
///
/// Uses [StatefulShellRoute.indexedStack] for bottom tab navigation
/// with three branches: Conversations, Map, Profile.
///
/// Tab state is preserved when switching between tabs because
/// indexedStack keeps all branch navigators alive.
@riverpod
GoRouter appRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/conversations',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/conversations',
                builder: (context, state) => const ConversationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (context, state) => const MapScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
