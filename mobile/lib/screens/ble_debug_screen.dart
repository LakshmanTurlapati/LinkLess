import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/ble/proximity_state_machine.dart';

/// Development debug screen for testing BLE proximity detection on physical devices.
///
/// Shows real-time BLE status including:
/// - Bluetooth adapter state, scanning/advertising status, platform
/// - Start/Stop controls
/// - Discovered peers with RSSI values and proximity state
/// - Timestamped event log
///
/// This screen is a DEVELOPMENT TOOL, not a user-facing feature.
class BleDebugScreen extends StatefulWidget {
  const BleDebugScreen({super.key});

  @override
  State<BleDebugScreen> createState() => _BleDebugScreenState();
}

class _BleDebugScreenState extends State<BleDebugScreen> {
  final BleManager _bleManager = BleManager.instance;

  /// Hardcoded test user ID for development/testing.
  static const String _testUserId = 'test-user-001';

  /// Log entries (most recent first). Capped at 100.
  final List<String> _logEntries = [];

  /// Discovered peers: deviceId -> latest proximity event.
  final Map<String, BleProximityEvent> _discoveredPeers = {};

  StreamSubscription<BleProximityEvent>? _proximitySubscription;
  StreamSubscription<ProximityEvent>? _stateSubscription;
  StreamSubscription<String>? _logSubscription;

  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _initializeBle();
  }

  Future<void> _initializeBle() async {
    if (_bleManager.isInitialized) {
      _subscribeToStreams();
      return;
    }

    setState(() => _isInitializing = true);

    try {
      await _bleManager.initialize();
      await _bleManager.requestPermissions();
    } catch (e) {
      _addLog('Initialization error: $e');
    } finally {
      setState(() => _isInitializing = false);
    }

    _subscribeToStreams();
  }

  void _subscribeToStreams() {
    _proximitySubscription = _bleManager.proximityStream.listen((event) {
      setState(() {
        _discoveredPeers[event.deviceId] = event;
      });
    });

    _stateSubscription =
        _bleManager.proximityStateStream.listen((event) {
      final eventType =
          event.type == ProximityEventType.detected ? 'DETECTED' : 'LOST';
      _addLog('Proximity $eventType: ${event.peerId}');
    });

    _logSubscription = _bleManager.logStream.listen((logLine) {
      _addLog(logLine);
    });
  }

  void _addLog(String message) {
    setState(() {
      _logEntries.insert(0, message);
      if (_logEntries.length > 100) {
        _logEntries.removeLast();
      }
    });
  }

  Future<void> _toggleBle() async {
    if (_bleManager.isRunning) {
      await _bleManager.stop();
    } else {
      await _bleManager.start(_testUserId);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _proximitySubscription?.cancel();
    _stateSubscription?.cancel();
    _logSubscription?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: () {
              setState(() {
                _logEntries.clear();
                _discoveredPeers.clear();
              });
            },
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeaderSection(),
                _buildControlSection(),
                const Divider(height: 1),
                _buildPeersHeader(),
                _buildPeersList(),
                const Divider(height: 1),
                _buildLogHeader(),
                _buildLogList(),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header Section
  // ---------------------------------------------------------------------------

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade100,
      child: Column(
        children: [
          _buildStatusRow(
            'Platform',
            Platform.isIOS
                ? 'iOS'
                : Platform.isAndroid
                    ? 'Android'
                    : 'Unknown',
          ),
          StreamBuilder<BluetoothAdapterState>(
            stream: FlutterBluePlus.adapterState,
            initialData: FlutterBluePlus.adapterStateNow,
            builder: (context, snapshot) {
              final state = snapshot.data ?? BluetoothAdapterState.unknown;
              final isOn = state == BluetoothAdapterState.on;
              return _buildStatusRow(
                'Bluetooth',
                _adapterStateLabel(state),
                valueColor: isOn ? Colors.green.shade700 : Colors.red.shade700,
              );
            },
          ),
          _buildStatusRow(
            'Scanning',
            _bleManager.isRunning ? 'Active' : 'Stopped',
            valueColor: _bleManager.isRunning
                ? Colors.green.shade700
                : Colors.grey.shade600,
          ),
          _buildStatusRow(
            'Advertising',
            _bleManager.peripheralService.isAdvertising
                ? 'Active'
                : 'Stopped',
            valueColor: _bleManager.peripheralService.isAdvertising
                ? Colors.green.shade700
                : Colors.grey.shade600,
          ),
          _buildStatusRow('User ID', _testUserId),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? Colors.black87,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _adapterStateLabel(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.on:
        return 'ON';
      case BluetoothAdapterState.off:
        return 'OFF';
      case BluetoothAdapterState.turningOn:
        return 'Turning On';
      case BluetoothAdapterState.turningOff:
        return 'Turning Off';
      case BluetoothAdapterState.unauthorized:
        return 'Unauthorized';
      case BluetoothAdapterState.unavailable:
        return 'Unavailable';
      case BluetoothAdapterState.unknown:
        return 'Unknown';
    }
  }

  // ---------------------------------------------------------------------------
  // Control Section
  // ---------------------------------------------------------------------------

  Widget _buildControlSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _toggleBle,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _bleManager.isRunning ? Colors.red.shade600 : Colors.green.shade600,
            foregroundColor: Colors.white,
          ),
          child: Text(_bleManager.isRunning ? 'Stop' : 'Start'),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Discovered Peers Section
  // ---------------------------------------------------------------------------

  Widget _buildPeersHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Text(
            'Discovered Peers',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Text(
            '(${_discoveredPeers.length})',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPeersList() {
    if (_discoveredPeers.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text(
            'No peers discovered yet',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }

    final peers = _discoveredPeers.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return SizedBox(
      height: 140,
      child: ListView.builder(
        itemCount: peers.length,
        itemBuilder: (context, index) {
          final peer = peers[index];
          return _buildPeerTile(peer);
        },
      ),
    );
  }

  Widget _buildPeerTile(BleProximityEvent peer) {
    final state = _bleManager.stateMachine.getState(peer.deviceId);
    final userId = _bleManager.deviceToUserIdMap[peer.deviceId];
    final timeSince = DateTime.now().difference(peer.timestamp);
    final lastSeenText = timeSince.inSeconds < 60
        ? '${timeSince.inSeconds}s ago'
        : '${timeSince.inMinutes}m ago';

    Color stateColor;
    String stateLabel;
    switch (state) {
      case ProximityState.idle:
        stateColor = Colors.grey;
        stateLabel = 'IDLE';
      case ProximityState.detected:
        stateColor = Colors.green;
        stateLabel = 'DETECTED';
      case ProximityState.connected:
        stateColor = Colors.blue;
        stateLabel = 'CONNECTED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: stateColor, width: 4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userId ?? _truncateId(peer.deviceId),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight:
                        userId != null ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (userId != null)
                  Text(
                    'Device: ${_truncateId(peer.deviceId)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RSSI: ${peer.rssi}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              Text(
                lastSeenText,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              stateLabel,
              style: TextStyle(
                color: stateColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Event Log Section
  // ---------------------------------------------------------------------------

  Widget _buildLogHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Text(
            'Event Log',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Text(
            '(${_logEntries.length})',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    return Expanded(
      child: Container(
        color: Colors.grey.shade900,
        child: _logEntries.isEmpty
            ? const Center(
                child: Text(
                  'No events yet',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            : ListView.builder(
                itemCount: _logEntries.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    child: Text(
                      _logEntries[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.greenAccent,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 8)}...';
  }
}
