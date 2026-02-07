import 'dart:async';

import 'package:linkless/ble/rssi_filter.dart';

/// Proximity states for a tracked peer.
enum ProximityState {
  /// No peer nearby or peer signal lost.
  idle,

  /// Peer is within proximity range (filtered RSSI above enter threshold).
  detected,

  /// Peer is connected for data exchange (set externally).
  connected,
}

/// Types of proximity events emitted by the state machine.
enum ProximityEventType {
  /// Peer entered proximity range.
  detected,

  /// Peer left proximity range (after debounce).
  lost,
}

/// Event emitted when proximity state changes.
class ProximityEvent {
  final String peerId;
  final ProximityEventType type;
  final DateTime timestamp;

  ProximityEvent({
    required this.peerId,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'ProximityEvent($peerId, $type)';
}

/// Internal tracking state for a single peer.
class _PeerState {
  final String peerId;
  final RssiFilter rssiFilter;
  ProximityState state = ProximityState.idle;
  Timer? debounceTimer;
  DateTime? lastSeenAt;

  _PeerState({
    required this.peerId,
    required this.rssiFilter,
  });

  void dispose() {
    debounceTimer?.cancel();
  }
}

/// State machine that tracks proximity of BLE peers using filtered RSSI
/// with hysteresis thresholds and debounce timers.
///
/// - Transitions IDLE -> DETECTED when filtered RSSI >= [enterThreshold].
/// - Transitions DETECTED -> IDLE when filtered RSSI < [exitThreshold]
///   AND debounce timer expires.
/// - The gap between enter and exit thresholds (hysteresis) prevents
///   rapid state toggling from noisy RSSI.
/// - The debounce timer prevents brief RSSI dips from causing state change.
class ProximityStateMachine {
  /// RSSI threshold to enter detected state (closer = less negative).
  final int enterThreshold;

  /// RSSI threshold to exit detected state (further = more negative).
  /// Must be less than (more negative than) [enterThreshold].
  final int exitThreshold;

  /// Duration to wait before transitioning from detected to idle.
  final Duration debounceDuration;

  /// EMA smoothing factor for RSSI filtering.
  final double rssiAlpha;

  final Map<String, _PeerState> _peers = {};
  final StreamController<ProximityEvent> _eventController =
      StreamController<ProximityEvent>.broadcast();
  bool _disposed = false;

  ProximityStateMachine({
    this.enterThreshold = -70,
    this.exitThreshold = -80,
    this.debounceDuration = const Duration(seconds: 10),
    this.rssiAlpha = 0.3,
  });

  /// Stream of proximity events (detected/lost).
  Stream<ProximityEvent> get events => _eventController.stream;

  /// Get the current proximity state for a peer.
  /// Returns [ProximityState.idle] for unknown peers.
  ProximityState getState(String peerId) {
    return _peers[peerId]?.state ?? ProximityState.idle;
  }

  /// Called when a BLE scan discovers a peer with an RSSI reading.
  ///
  /// Updates the RSSI filter and evaluates state transitions.
  void onPeerDiscovered(String peerId, int rawRssi) {
    if (_disposed) return;

    final peer = _getOrCreatePeer(peerId);
    peer.lastSeenAt = DateTime.now();

    final filteredRssi = peer.rssiFilter.update(rawRssi);

    _evaluateTransition(peer, filteredRssi);
  }

  /// Called when a BLE scan no longer detects a peer.
  ///
  /// Starts the debounce timer if peer was in detected state.
  void onPeerLost(String peerId) {
    if (_disposed) return;

    final peer = _peers[peerId];
    if (peer == null) return;

    if (peer.state == ProximityState.detected) {
      _startDebounce(peer);
    }
  }

  /// Clean up all timers and close the event stream.
  void dispose() {
    _disposed = true;
    for (final peer in _peers.values) {
      peer.dispose();
    }
    _peers.clear();
    _eventController.close();
  }

  _PeerState _getOrCreatePeer(String peerId) {
    return _peers.putIfAbsent(
      peerId,
      () => _PeerState(
        peerId: peerId,
        rssiFilter: RssiFilter(alpha: rssiAlpha),
      ),
    );
  }

  void _evaluateTransition(_PeerState peer, double filteredRssi) {
    switch (peer.state) {
      case ProximityState.idle:
        if (filteredRssi >= enterThreshold) {
          peer.state = ProximityState.detected;
          _cancelDebounce(peer);
          _emitEvent(peer.peerId, ProximityEventType.detected);
        }
        break;

      case ProximityState.detected:
        if (filteredRssi >= enterThreshold) {
          // Strong signal -- cancel any pending debounce
          _cancelDebounce(peer);
        } else if (filteredRssi < exitThreshold) {
          // Below exit threshold -- start debounce if not already running
          _startDebounce(peer);
        }
        // Between exit and enter (hysteresis gap): do nothing, stay detected
        break;

      case ProximityState.connected:
        // Connected state is managed externally; no automatic transitions here
        break;
    }
  }

  void _startDebounce(_PeerState peer) {
    if (peer.debounceTimer?.isActive ?? false) {
      // Debounce already running
      return;
    }

    peer.debounceTimer = Timer(debounceDuration, () {
      if (_disposed) return;
      if (peer.state == ProximityState.detected) {
        peer.state = ProximityState.idle;
        peer.rssiFilter.reset();
        _emitEvent(peer.peerId, ProximityEventType.lost);
      }
    });
  }

  void _cancelDebounce(_PeerState peer) {
    peer.debounceTimer?.cancel();
    peer.debounceTimer = null;
  }

  void _emitEvent(String peerId, ProximityEventType type) {
    if (!_eventController.isClosed) {
      _eventController.add(ProximityEvent(peerId: peerId, type: type));
    }
  }
}
