import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'package:linkless/core/config/app_config.dart';
import 'package:linkless/features/map/data/services/marker_image_service.dart';
import 'package:linkless/features/map/domain/models/map_conversation.dart';
import 'package:linkless/features/map/presentation/providers/date_navigation_provider.dart';
import 'package:linkless/features/map/presentation/providers/map_provider.dart';
import 'package:linkless/features/map/presentation/widgets/conversation_detail_sheet.dart';
import 'package:linkless/features/map/presentation/widgets/date_navigation_bar.dart';

/// Interactive map screen powered by Mapbox Maps SDK.
///
/// Displays conversation pins for the selected date using a dual-mode rendering
/// strategy:
/// - **Low density** (<=20 pins): Individual [PointAnnotation]s with circular
///   face-pin images (peer photos or initials).
/// - **High density** (>20 pins): GeoJSON source with clustering enabled,
///   rendering cluster bubbles with counts and individual colored dots.
///
/// Tapping a pin or unclustered point opens a [ConversationDetailSheet]
/// bottom sheet showing peer info, transcript, and AI summary.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// Reference to the Mapbox map controller.
  MapboxMap? _mapboxMap;

  /// Annotation manager for creating/managing PointAnnotations in low-density mode.
  PointAnnotationManager? _annotationManager;

  /// Maps PointAnnotation ID to its corresponding [MapConversation] for tap lookup.
  final Map<String, MapConversation> _annotationConversationMap = {};

  /// Pin count threshold above which GeoJSON clustering is used instead of
  /// individual PointAnnotations. 20 is a pragmatic v1 default -- most per-day
  /// views will have fewer pins.
  static const int _clusterThreshold = 20;

  /// GeoJSON source and layer IDs for high-density clustering mode.
  static const String _clusterSourceId = 'conversations-cluster-source';
  static const String _clusterCirclesLayerId = 'cluster-circles';
  static const String _clusterCountLayerId = 'cluster-count';
  static const String _unclusteredPointLayerId = 'unclustered-point';

  /// Whether the Mapbox access token has been configured.
  bool _tokenConfigured = false;

  /// Whether conversations are currently loading.
  bool _isLoading = false;

  /// The current rendering mode to track cleanup needs.
  _RenderMode _currentRenderMode = _RenderMode.none;

  @override
  void initState() {
    super.initState();
    _configureAccessToken();
  }

  @override
  void dispose() {
    _annotationConversationMap.clear();
    super.dispose();
  }

  /// Sets the Mapbox public access token from build-time --dart-define.
  Future<void> _configureAccessToken() async {
    final token = AppConfig.mapboxAccessToken;
    if (token.isNotEmpty) {
      MapboxOptions.setAccessToken(token);
    }
    if (mounted) {
      setState(() {
        _tokenConfigured = true;
      });
    }
  }

  /// Called when the MapWidget finishes initialization.
  ///
  /// Creates the [PointAnnotationManager] and registers the tap listener
  /// for pin interactions.
  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Create annotation manager for low-density PointAnnotations
    _annotationManager = await mapboxMap.annotations
        .createPointAnnotationManager();

    // Register tap listener for PointAnnotations
    _annotationManager?.addOnPointAnnotationClickListener(
      _AnnotationClickListener(
        conversationMap: _annotationConversationMap,
        onConversationTapped: _showConversationDetail,
      ),
    );

    // Register map tap listener for GeoJSON cluster/unclustered point taps
    final tapListener = _MapTapListener(
      mapboxMap: mapboxMap,
      clusterSourceId: _clusterSourceId,
      clusterCirclesLayerId: _clusterCirclesLayerId,
      unclusteredPointLayerId: _unclusteredPointLayerId,
      onConversationIdTapped: _handleUnclusteredPointTap,
    );
    mapboxMap.setOnMapTapListener(tapListener.onMapTap);

    // Trigger initial data load for today's date
    if (mounted) {
      _loadConversationsForDate(ref.read(dateNavigationProvider));
    }
  }

  /// Formats a [DateTime] as YYYY-MM-DD for the API query parameter.
  String _formatDateParam(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Loads conversations for the given date and triggers rendering.
  void _loadConversationsForDate(DateTime date) {
    final dateString = _formatDateParam(date);
    // Invalidate to force refetch
    ref.invalidate(mapConversationsProvider(dateString));
  }

  /// Opens the [ConversationDetailSheet] bottom sheet for the tapped
  /// conversation.
  void _showConversationDetail(MapConversation conversation) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ConversationDetailSheet(
        conversation: conversation,
      ),
    );
  }

  /// Handles a tap on an unclustered GeoJSON point by looking up the
  /// conversation ID from the feature properties and fetching the full
  /// conversation from the current provider data.
  void _handleUnclusteredPointTap(String conversationId) {
    final dateString = _formatDateParam(ref.read(dateNavigationProvider));
    final asyncValue = ref.read(mapConversationsProvider(dateString));
    final conversations = asyncValue.valueOrNull;
    if (conversations == null) return;

    final conversation = conversations.cast<MapConversation?>().firstWhere(
          (c) => c?.id == conversationId,
          orElse: () => null,
        );
    if (conversation != null) {
      _showConversationDetail(conversation);
    }
  }

  /// Main rendering method. Decides between low-density (PointAnnotation)
  /// and high-density (GeoJSON clustering) modes based on conversation count.
  Future<void> _renderConversations(
    List<MapConversation> conversations,
  ) async {
    if (_mapboxMap == null) return;

    // Clean up previous rendering regardless of mode
    await _cleanupPreviousRender();

    if (conversations.isEmpty) {
      _currentRenderMode = _RenderMode.none;
      return;
    }

    if (conversations.length <= _clusterThreshold) {
      await _renderLowDensity(conversations);
    } else {
      await _renderHighDensity(conversations);
    }
  }

  /// Cleans up both PointAnnotations and GeoJSON layers/source from any
  /// prior render. Layers must be removed BEFORE the source to avoid errors.
  Future<void> _cleanupPreviousRender() async {
    // Clean up PointAnnotations
    if (_annotationManager != null) {
      await _annotationManager!.deleteAll();
    }
    _annotationConversationMap.clear();

    // Clean up GeoJSON layers and source (layers first, then source)
    if (_currentRenderMode == _RenderMode.cluster) {
      final style = _mapboxMap!.style;
      try {
        await style.removeStyleLayer(_clusterCountLayerId);
      } catch (_) {}
      try {
        await style.removeStyleLayer(_clusterCirclesLayerId);
      } catch (_) {}
      try {
        await style.removeStyleLayer(_unclusteredPointLayerId);
      } catch (_) {}
      try {
        await style.removeStyleSource(_clusterSourceId);
      } catch (_) {}
    }
  }

  /// Low-density rendering: individual PointAnnotations with face-pin images.
  ///
  /// For each conversation, renders a circular face-pin marker (photo or
  /// initials) and creates a PointAnnotation at the conversation's GPS
  /// location. Handles individual photo download failures gracefully.
  Future<void> _renderLowDensity(List<MapConversation> conversations) async {
    _currentRenderMode = _RenderMode.points;

    // Render all face-pin images concurrently
    final futures = conversations.map((conv) async {
      try {
        final imageBytes = await MarkerImageService.renderFacePin(
          photoUrl: conv.peerPhotoUrl,
          initials: conv.peerInitials,
          isAnonymous: conv.peerIsAnonymous,
        );
        return _PinData(conversation: conv, imageBytes: imageBytes);
      } catch (_) {
        // If rendering fails for one pin, create a fallback
        try {
          final fallbackBytes = await MarkerImageService.renderFacePin(
            initials: conv.peerInitials ?? '?',
            isAnonymous: true,
          );
          return _PinData(conversation: conv, imageBytes: fallbackBytes);
        } catch (_) {
          return null;
        }
      }
    });

    final pinDataList = (await Future.wait(futures)).whereType<_PinData>();

    if (_annotationManager == null || !mounted) return;

    for (final pinData in pinDataList) {
      final options = PointAnnotationOptions(
        geometry: Point(
          coordinates: Position(
            pinData.conversation.longitude,
            pinData.conversation.latitude,
          ),
        ),
        image: pinData.imageBytes,
        iconSize: 0.75,
      );

      final annotation = await _annotationManager!.create(options);
      _annotationConversationMap[annotation.id] = pinData.conversation;
    }

    // Animate camera to fit all pins
    _fitCameraToConversations(conversations);
  }

  /// High-density rendering: GeoJSON source with clustering enabled.
  ///
  /// Creates a GeoJSON FeatureCollection, adds it as a clustered source,
  /// and overlays CircleLayer (cluster bubbles), SymbolLayer (cluster counts),
  /// and CircleLayer (unclustered individual points).
  Future<void> _renderHighDensity(List<MapConversation> conversations) async {
    _currentRenderMode = _RenderMode.cluster;

    final features = conversations
        .map((c) => {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [c.longitude, c.latitude],
              },
              'properties': {
                'conversationId': c.id,
                'peerName': c.peerDisplayName ?? 'Unknown',
              },
            })
        .toList();

    final geojson = jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });

    final style = _mapboxMap!.style;

    // Add GeoJSON source with clustering enabled
    await style.addSource(
      GeoJsonSource(
        id: _clusterSourceId,
        data: geojson,
        cluster: true,
        clusterRadius: 50,
        clusterMaxZoom: 14,
      ),
    );

    // Layer 1: Cluster circles (grouped points)
    await style.addLayer(
      CircleLayer(
        id: _clusterCirclesLayerId,
        sourceId: _clusterSourceId,
        filter: ['has', 'point_count'],
        circleColor: const Color(0xFF2196F3).value,
        circleRadius: 18.0,
        circleOpacity: 0.8,
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    // Layer 2: Cluster count text
    await style.addLayer(
      SymbolLayer(
        id: _clusterCountLayerId,
        sourceId: _clusterSourceId,
        filter: ['has', 'point_count'],
        textFieldExpression: ['get', 'point_count_abbreviated'],
        textSize: 12.0,
        textColor: Colors.white.value,
      ),
    );

    // Layer 3: Unclustered individual points
    await style.addLayer(
      CircleLayer(
        id: _unclusteredPointLayerId,
        sourceId: _clusterSourceId,
        filter: [
          '!',
          ['has', 'point_count'],
        ],
        circleColor: const Color(0xFF2196F3).value,
        circleRadius: 8.0,
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    // Animate camera to fit all points
    _fitCameraToConversations(conversations);
  }

  /// Animates the camera to encompass all conversation locations with padding.
  void _fitCameraToConversations(List<MapConversation> conversations) {
    if (conversations.isEmpty || _mapboxMap == null) return;

    if (conversations.length == 1) {
      final conv = conversations.first;
      _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(conv.longitude, conv.latitude),
          ),
          zoom: 14.0,
        ),
        MapAnimationOptions(duration: 500),
      );
      return;
    }

    // Calculate bounding box
    var minLat = conversations.first.latitude;
    var maxLat = conversations.first.latitude;
    var minLng = conversations.first.longitude;
    var maxLng = conversations.first.longitude;

    for (final conv in conversations) {
      if (conv.latitude < minLat) minLat = conv.latitude;
      if (conv.latitude > maxLat) maxLat = conv.latitude;
      if (conv.longitude < minLng) minLng = conv.longitude;
      if (conv.longitude > maxLng) maxLng = conv.longitude;
    }

    _mapboxMap!.cameraForCoordinateBounds(
      CoordinateBounds(
        southwest: Point(coordinates: Position(minLng, minLat)),
        northeast: Point(coordinates: Position(maxLng, maxLat)),
        infiniteBounds: false,
      ),
      MbxEdgeInsets(top: 80, left: 40, bottom: 40, right: 40),
      null, // bearing
      null, // pitch
      null, // maxZoom
      null, // offset
    ).then((cameraOptions) {
      _mapboxMap!.flyTo(
        cameraOptions,
        MapAnimationOptions(duration: 500),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(dateNavigationProvider);
    final dateString = _formatDateParam(selectedDate);
    final conversationsAsync = ref.watch(mapConversationsProvider(dateString));

    // Listen for date changes to trigger re-rendering
    ref.listen<DateTime>(dateNavigationProvider, (previous, next) {
      if (previous != next) {
        _loadConversationsForDate(next);
      }
    });

    // React to conversation data changes
    ref.listen(mapConversationsProvider(dateString), (previous, next) {
      next.whenData((conversations) {
        _renderConversations(conversations);
      });
    });

    // Track loading state
    final isLoading = conversationsAsync.isLoading;
    final conversations = conversationsAsync.valueOrNull ?? [];
    final hasError = conversationsAsync.hasError;

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: const DateNavigationBar(),
          ),
          Expanded(
            child: _tokenConfigured
                ? Stack(
                    children: [
                      _buildMap(),

                      // Loading indicator overlay
                      if (isLoading)
                        const Positioned(
                          top: 8,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),

                      // Empty state overlay
                      if (!isLoading && !hasError && conversations.isEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'No conversations on this date',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Error overlay
                      if (hasError)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Failed to load conversations',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
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

// ---------------------------------------------------------------------------
// Private helper types
// ---------------------------------------------------------------------------

/// Tracks which rendering mode is currently active for cleanup.
enum _RenderMode { none, points, cluster }

/// Bundles a conversation with its rendered face-pin image bytes.
class _PinData {
  final MapConversation conversation;
  final Uint8List imageBytes;

  const _PinData({required this.conversation, required this.imageBytes});
}

/// Handles tap events on PointAnnotations (low-density mode).
///
/// Looks up the tapped annotation's ID in the conversation map and
/// invokes the callback with the matched [MapConversation].
class _AnnotationClickListener
    extends OnPointAnnotationClickListener {
  final Map<String, MapConversation> conversationMap;
  final void Function(MapConversation) onConversationTapped;

  _AnnotationClickListener({
    required this.conversationMap,
    required this.onConversationTapped,
  });

  @override
  void onPointAnnotationClick(PointAnnotation annotation) {
    final conversation = conversationMap[annotation.id];
    if (conversation != null) {
      onConversationTapped(conversation);
    }
  }
}

/// Handles tap events on the map for GeoJSON cluster/unclustered point
/// interactions (high-density mode).
///
/// When a cluster circle is tapped, the map zooms in to expand it.
/// When an unclustered point is tapped, the conversation detail sheet opens.
class _MapTapListener {
  final MapboxMap mapboxMap;
  final String clusterSourceId;
  final String clusterCirclesLayerId;
  final String unclusteredPointLayerId;
  final void Function(String conversationId) onConversationIdTapped;

  _MapTapListener({
    required this.mapboxMap,
    required this.clusterSourceId,
    required this.clusterCirclesLayerId,
    required this.unclusteredPointLayerId,
    required this.onConversationIdTapped,
  });

  void onMapTap(MapContentGestureContext context) {
    final screenPoint = context.touchPosition;

    // Query for cluster circles at tap point
    mapboxMap
        .queryRenderedFeatures(
      RenderedQueryGeometry.fromScreenCoordinate(
        ScreenCoordinate(x: screenPoint.x, y: screenPoint.y),
      ),
      RenderedQueryOptions(layerIds: [clusterCirclesLayerId]),
    )
        .then((clusterFeatures) {
      if (clusterFeatures.isNotEmpty) {
        final feature = clusterFeatures.first;
        if (feature != null) {
          _handleClusterTap(feature, screenPoint);
        }
        return;
      }

      // Query for unclustered points at tap point
      mapboxMap
          .queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(
          ScreenCoordinate(x: screenPoint.x, y: screenPoint.y),
        ),
        RenderedQueryOptions(layerIds: [unclusteredPointLayerId]),
      )
          .then((pointFeatures) {
        if (pointFeatures.isNotEmpty) {
          final feature = pointFeatures.first;
          if (feature != null) {
            _handleUnclusteredPointTap(feature);
          }
        }
      });
    });
  }

  /// Zooms in on a cluster tap to expand it to individual points.
  void _handleClusterTap(
    QueriedRenderedFeature feature,
    ScreenCoordinate screenPoint,
  ) {
    final featureData = feature.queriedFeature.feature;
    final properties = featureData['properties'];
    if (properties == null || properties is! Map) return;

    final geometry = featureData['geometry'];
    if (geometry == null || geometry is! Map) return;

    final coordinates = (geometry as Map)['coordinates'];
    if (coordinates == null || coordinates is! List || coordinates.length < 2) {
      return;
    }

    final lng = (coordinates[0] as num).toDouble();
    final lat = (coordinates[1] as num).toDouble();

    // Zoom in closer to the cluster center
    mapboxMap.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lng, lat)),
        zoom: 15.0,
      ),
      MapAnimationOptions(duration: 300),
    );
  }

  /// Opens the conversation detail sheet for an unclustered point tap.
  void _handleUnclusteredPointTap(QueriedRenderedFeature feature) {
    final featureData = feature.queriedFeature.feature;
    final properties = featureData['properties'];
    if (properties == null || properties is! Map) return;

    final conversationId = (properties as Map)['conversationId'];
    if (conversationId != null && conversationId is String) {
      onConversationIdTapped(conversationId);
    }
  }
}
