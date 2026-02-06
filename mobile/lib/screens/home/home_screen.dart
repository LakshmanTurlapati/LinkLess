import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/ble_proximity_service.dart';
import '../../services/transcription_service.dart';
import '../../services/auth_service.dart';
import '../../services/api_client.dart';
import '../encounters/encounter_detail_screen.dart';

/// The main screen — shows BLE scanning status and nearby LinkLess users.
/// When two users are in proximity, auto-triggers transcription recording.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  StreamSubscription<NearbyPeer>? _proximityTriggerSub;
  StreamSubscription<NearbyPeer>? _proximityLostSub;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _proximityTriggerSub?.cancel();
    _proximityLostSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bleService = ref.read(bleProximityServiceProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      bleService.startProximityDetection();
    } else if (state == AppLifecycleState.paused) {
      // Keep scanning in background on supported platforms
    }
  }

  Future<void> _initBle() async {
    if (_isInitialized) return;
    _isInitialized = true;

    final bleService = ref.read(bleProximityServiceProvider.notifier);
    await bleService.startProximityDetection();

    // Listen for proximity triggers — auto-start transcription
    _proximityTriggerSub = bleService.onProximityTriggered.listen((peer) async {
      if (peer.userId == null) return;

      // Create encounter on the backend
      final apiClient = ref.read(apiClientProvider);
      final encounter = await apiClient.createEncounter(
        peerId: peer.userId!,
        proximityDistance: peer.estimatedDistance,
      );

      if (encounter != null) {
        // Start recording and transcribing
        final transcription = ref.read(transcriptionServiceProvider.notifier);
        await transcription.startRecording(
          encounterId: encounter.id,
          peerId: peer.userId!,
        );
      }
    });

    // Listen for proximity lost — auto-stop transcription
    _proximityLostSub = bleService.onProximityLost.listen((peer) async {
      final transcription = ref.read(transcriptionServiceProvider.notifier);
      final transcriptionState = ref.read(transcriptionServiceProvider);

      if (transcriptionState.isRecording) {
        await transcription.stopRecording();

        // End the encounter on the backend
        if (transcriptionState.currentEncounterId != null) {
          final apiClient = ref.read(apiClientProvider);
          await apiClient.endEncounter(transcriptionState.currentEncounterId!);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleProximityServiceProvider);
    final transcriptionState = ref.watch(transcriptionServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LinkLess'),
        actions: [
          // Scanning indicator
          if (bleState.isScanning)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Scanning',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Active recording banner
          if (transcriptionState.isRecording)
            _buildRecordingBanner(transcriptionState, colorScheme),

          // Error banner
          if (bleState.error != null)
            _buildErrorBanner(bleState.error!, colorScheme),

          // Main content
          Expanded(
            child: bleState.nearbyPeers.isEmpty
                ? _buildEmptyState(bleState, colorScheme)
                : _buildNearbyPeersList(bleState, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBanner(
      TranscriptionState state, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(Icons.mic, color: colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recording conversation...',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatDuration(state.recordingDuration),
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer.withAlpha(179),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (state.isTranscribing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String error, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.warning_rounded, color: colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: colorScheme.onErrorContainer),
            onPressed: () {
              ref
                  .read(bleProximityServiceProvider.notifier)
                  .startProximityDetection();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BleProximityState state, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated scanning indicator
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primaryContainer.withAlpha(128),
              ),
              child: Icon(
                state.isScanning
                    ? Icons.bluetooth_searching_rounded
                    : Icons.bluetooth_disabled_rounded,
                size: 56,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              state.isScanning
                  ? 'Looking for nearby LinkLess users...'
                  : 'Bluetooth scanning is off',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              state.isScanning
                  ? 'Make sure the other person also has LinkLess open'
                  : 'Enable Bluetooth to discover nearby users',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (!state.isScanning) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  ref
                      .read(bleProximityServiceProvider.notifier)
                      .startProximityDetection();
                },
                icon: const Icon(Icons.bluetooth),
                label: const Text('Start Scanning'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyPeersList(
      BleProximityState state, ColorScheme colorScheme) {
    final peers = state.nearbyPeers.values.toList()
      ..sort((a, b) => a.estimatedDistance.compareTo(b.estimatedDistance));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: peers.length + 1, // +1 for header
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${peers.length} nearby ${peers.length == 1 ? 'user' : 'users'}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }

        final peer = peers[index - 1];
        return _buildPeerCard(peer, colorScheme);
      },
    );
  }

  Widget _buildPeerCard(NearbyPeer peer, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: peer.isInProximity
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          child: Icon(
            peer.isInProximity
                ? Icons.person_rounded
                : Icons.person_outline_rounded,
            color: peer.isInProximity
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          peer.displayName ?? 'LinkLess User',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '~${peer.estimatedDistance.toStringAsFixed(1)}m away',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        trailing: peer.isInProximity
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'In Range',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
