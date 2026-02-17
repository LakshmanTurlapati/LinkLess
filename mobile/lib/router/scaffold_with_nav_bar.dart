import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:linkless/core/theme/app_colors.dart';

/// Navigation shell widget that provides the bottom NavigationBar.
///
/// Receives the [StatefulNavigationShell] from GoRouter's
/// StatefulShellRoute and renders it as the body with a
/// three-tab bottom navigation bar.
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({
    super.key,
    required this.navigationShell,
  });

  /// The navigation shell from GoRouter's StatefulShellRoute.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.backgroundDarker,
        indicatorColor: AppColors.accentBlue.withOpacity(0.15),
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.link_outlined, color: AppColors.textTertiary),
            selectedIcon: Icon(Icons.link, color: AppColors.accentBlue),
            label: 'Links',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined, color: AppColors.textTertiary),
            selectedIcon: Icon(Icons.map, color: AppColors.accentBlue),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: AppColors.textTertiary),
            selectedIcon: Icon(Icons.person, color: AppColors.accentBlue),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.bug_report_outlined, color: AppColors.textTertiary),
            selectedIcon: Icon(Icons.bug_report, color: AppColors.accentBlue),
            label: 'Debug',
          ),
        ],
      ),
    );
  }
}
