import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/auth/presentation/views/otp_verification_screen.dart';
import 'package:linkless/features/auth/presentation/views/phone_input_screen.dart';
import 'package:linkless/features/connections/presentation/views/connections_list_screen.dart';
import 'package:linkless/features/conversations/presentation/views/conversations_screen.dart';
import 'package:linkless/features/map/presentation/views/map_screen.dart';
import 'package:linkless/features/recording/presentation/views/playback_screen.dart';
import 'package:linkless/features/profile/presentation/views/encounter_card_screen.dart';
import 'package:linkless/features/profile/presentation/views/profile_creation_screen.dart';
import 'package:linkless/features/profile/presentation/views/profile_edit_screen.dart';
import 'package:linkless/features/profile/presentation/views/profile_screen.dart';
import 'package:linkless/features/search/presentation/views/search_screen.dart';
import 'package:linkless/router/scaffold_with_nav_bar.dart';
import 'package:linkless/screens/ble_debug_screen.dart';

part 'app_router.g.dart';

/// Root navigator key for the app shell.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Provides the app-level GoRouter configuration.
///
/// Uses [StatefulShellRoute.indexedStack] for bottom tab navigation
/// with three branches: Conversations, Map, Profile.
///
/// Auth guard redirects unauthenticated users to the phone input screen.
/// Authenticated users are redirected away from auth screens.
@riverpod
GoRouter appRouter(Ref ref) {
  // Trigger initial auth check (deferred to avoid modifying authProvider
  // state during appRouterProvider initialization).
  final notifier = ref.read(authProvider.notifier);
  Future.microtask(() => notifier.checkAuthStatus());

  // Listenable adapter so GoRouter re-evaluates redirect on auth changes.
  final authListenable = AuthStateListenable(ref);

  // Clean up the listenable when the provider is disposed.
  ref.onDispose(() => authListenable.dispose());

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/conversations',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isAuthenticated = authState.status == AuthStatus.authenticated;
      final isOnAuthRoute = state.matchedLocation.startsWith('/auth');
      final isOnDebugRoute = state.matchedLocation.startsWith('/ble-debug');
      final isInitialOrLoading = authState.status == AuthStatus.initial ||
          authState.status == AuthStatus.loading;

      // While checking initial auth status, don't redirect.
      if (isInitialOrLoading) return null;

      // Debug routes bypass auth guard (dev tool only).
      if (isOnDebugRoute) return null;

      // If not authenticated, redirect to phone input (unless already on auth route).
      if (!isAuthenticated && !isOnAuthRoute) {
        return '/auth/phone-input';
      }

      // If authenticated but on an auth route, redirect to conversations.
      if (isAuthenticated && isOnAuthRoute) {
        return '/conversations';
      }

      return null;
    },
    routes: [
      // Auth routes (outside the shell, no bottom nav).
      GoRoute(
        path: '/auth/phone-input',
        builder: (context, state) => const PhoneInputScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          return OtpVerificationScreen(phoneNumber: phone);
        },
      ),

      // Profile creation (outside the shell, no bottom nav).
      GoRoute(
        path: '/profile/create',
        builder: (context, state) => const ProfileCreationScreen(),
      ),

      // Profile edit (outside the shell, no bottom nav).
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const ProfileEditScreen(),
      ),

      // Connections list (outside the shell, no bottom nav).
      GoRoute(
        path: '/connections',
        builder: (context, state) => const ConnectionsListScreen(),
      ),

      // Search screen (outside the shell, full-screen focus).
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),

      // Encounter card (view another user's profile, outside the shell).
      GoRoute(
        path: '/profile/encounter/:userId',
        builder: (context, state) => EncounterCardScreen(
          userId: state.pathParameters['userId'] ?? '',
        ),
      ),

      // BLE debug screen (dev tool, outside the shell, no auth required).
      GoRoute(
        path: '/ble-debug',
        builder: (context, state) => const BleDebugScreen(),
      ),

      // Main app shell with bottom navigation.
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
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) {
                      final id = state.pathParameters['id'] ?? '';
                      return PlaybackScreen(conversationId: id);
                    },
                  ),
                ],
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
