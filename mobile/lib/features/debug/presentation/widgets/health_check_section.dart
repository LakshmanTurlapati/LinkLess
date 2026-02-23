import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/debug/presentation/providers/debug_panel_provider.dart';

/// Displays backend health status as compact rows with green/red status dots.
///
/// Shows status for seven components: Database, PostGIS, Redis, Tigris,
/// ARQ Worker, OpenAI Key, and xAI Key. Includes a manual refresh button
/// that invalidates [healthCheckProvider] to trigger a re-fetch.
class HealthCheckSection extends ConsumerWidget {
  const HealthCheckSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(healthCheckProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Backend Health',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              healthAsync.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        ref.invalidate(healthCheckProvider);
                      },
                    ),
            ],
          ),
          const SizedBox(height: 8),

          // Content
          healthAsync.when(
            data: (data) => _buildHealthRows(data),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  'Checking...',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Error: $error',
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthRows(Map<String, dynamic> data) {
    // Extract infrastructure component statuses
    final components = <_HealthComponent>[];

    // Database
    final db = data['database'];
    if (db is Map<String, dynamic>) {
      components.add(_HealthComponent(
        name: 'Database',
        status: db['status'] as String? ?? 'fail',
        message: db['message'] as String?,
      ));
    }

    // PostGIS
    final postgis = data['postgis'];
    if (postgis is Map<String, dynamic>) {
      components.add(_HealthComponent(
        name: 'PostGIS',
        status: postgis['status'] as String? ?? 'fail',
        message: postgis['message'] as String?,
      ));
    }

    // Redis
    final redis = data['redis'];
    if (redis is Map<String, dynamic>) {
      components.add(_HealthComponent(
        name: 'Redis',
        status: redis['status'] as String? ?? 'fail',
        message: redis['message'] as String?,
      ));
    }

    // Tigris
    final tigris = data['tigris'];
    if (tigris is Map<String, dynamic>) {
      components.add(_HealthComponent(
        name: 'Tigris',
        status: tigris['status'] as String? ?? 'fail',
        message: tigris['message'] as String?,
      ));
    }

    // ARQ Worker
    final arq = data['arq_worker'];
    if (arq is Map<String, dynamic>) {
      components.add(_HealthComponent(
        name: 'ARQ Worker',
        status: arq['status'] as String? ?? 'fail',
        message: arq['message'] as String?,
      ));
    }

    // API Keys
    final apiKeys = <_HealthComponent>[];
    final apiKeysData = data['api_keys'];
    if (apiKeysData is Map<String, dynamic>) {
      final keys = apiKeysData['keys'];
      if (keys is Map<String, dynamic>) {
        final openai = keys['openai_api_key'];
        apiKeys.add(_HealthComponent(
          name: 'OpenAI Key',
          status: openai == true ? 'pass' : 'fail',
          message: openai == true ? null : 'Missing',
        ));

        final xai = keys['xai_api_key'];
        apiKeys.add(_HealthComponent(
          name: 'xAI Key',
          status: xai == true ? 'pass' : 'fail',
          message: xai == true ? null : 'Missing',
        ));
      }
    }

    return Column(
      children: [
        // Infrastructure components
        ...components.map((c) => _HealthRow(component: c)),

        // Divider between infrastructure and API keys
        if (apiKeys.isNotEmpty) ...[
          const Divider(
            color: AppColors.divider,
            thickness: 0.5,
            height: 8,
          ),
          ...apiKeys.map((c) => _HealthRow(component: c)),
        ],
      ],
    );
  }
}

/// Data class for a single health component.
class _HealthComponent {
  final String name;
  final String status;
  final String? message;

  const _HealthComponent({
    required this.name,
    required this.status,
    this.message,
  });

  bool get isHealthy => status == 'pass';
}

/// A single health status row with name, optional error, and status dot.
class _HealthRow extends StatelessWidget {
  final _HealthComponent component;

  const _HealthRow({required this.component});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              component.name,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          if (!component.isHealthy && component.message != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  component.message!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 10,
                    fontFamily: 'monospace',
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: component.isHealthy
                  ? AppColors.success
                  : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}
