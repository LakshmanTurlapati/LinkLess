import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:linkless/core/config/app_config.dart';
import 'package:linkless/features/map/presentation/providers/date_navigation_provider.dart';
import 'package:linkless/features/map/presentation/widgets/date_navigation_bar.dart';

/// Interactive map screen powered by Mapbox Maps SDK.
///
/// Replaces the Phase 1 placeholder with a full-bleed Mapbox [MapWidget] and
/// a [DateNavigationBar] for browsing conversations by day. The map defaults
/// to San Francisco at zoom 12. Plan 03 will add conversation pin annotations
/// driven by the selected date.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// Reference to the Mapbox map controller, set in [_onMapCreated].
  /// Plan 03 will use this to manage annotation layers for conversation pins.
  MapboxMap? _mapboxMap;

  /// Whether the Mapbox access token has been configured.
  bool _tokenConfigured = false;

  @override
  void initState() {
    super.initState();
    _configureAccessToken();
  }

  /// Sets the Mapbox public access token from build-time --dart-define.
  ///
  /// Must be called before the [MapWidget] is created. The token is read from
  /// [AppConfig.mapboxAccessToken] which comes from the MAPBOX_ACCESS_TOKEN
  /// dart-define flag.
  Future<void> _configureAccessToken() async {
    final token = AppConfig.mapboxAccessToken;
    if (token.isNotEmpty) {
      await MapboxOptions.setAccessToken(token);
    }
    if (mounted) {
      setState(() {
        _tokenConfigured = true;
      });
    }
  }

  /// Stores the map controller reference for later use by annotation layers.
  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to date changes. For now, just observe the selected date.
    // Plan 03 will wire this to API calls to fetch conversation pins.
    ref.listen<DateTime>(dateNavigationProvider, (previous, next) {
      // Will be used by Plan 03 to reload pins for the new date.
    });

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: const DateNavigationBar(),
          ),
          Expanded(
            child: _tokenConfigured
                ? _buildMap()
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
          ),
        ],
      ),
    );
  }

  /// Builds the Mapbox [MapWidget] centered on San Francisco at zoom 12.
  Widget _buildMap() {
    if (AppConfig.mapboxAccessToken.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.map_outlined,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'Mapbox access token not configured.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Pass --dart-define=MAPBOX_ACCESS_TOKEN=pk.xxx when building.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return MapWidget(
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(-122.4194, 37.7749)),
        zoom: 12.0,
      ),
      onMapCreated: _onMapCreated,
    );
  }
}
