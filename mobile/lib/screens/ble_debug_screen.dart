import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'package:linkless/ble/ble_constants.dart';
import 'package:linkless/ble/ble_manager.dart';
import 'package:linkless/ble/proximity_state_machine.dart';
import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/recording/domain/models/conversation_local.dart';
import 'package:linkless/features/recording/presentation/providers/conversation_detail_provider.dart';
import 'package:linkless/features/recording/presentation/providers/database_provider.dart';
import 'package:linkless/features/recording/presentation/providers/recording_provider.dart';
import 'package:linkless/features/profile/presentation/providers/peer_profile_provider.dart';
import 'package:linkless/features/profile/presentation/view_models/profile_view_model.dart';
import 'package:linkless/features/sync/presentation/providers/sync_provider.dart';

// ---------------------------------------------------------------------------
// Log entry model
// ---------------------------------------------------------------------------

enum LogCategory {
  scan,
  gatt,
  proximity,
  permission,
  mic,
  error,
}

class _LogEntry {
  final String message;
  final LogCategory category;
  final DateTime timestamp;

  _LogEntry({
    required this.message,
    required this.category,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get formatted {
    final t = timestamp;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '[$hh:$mm:$ss] $message';
  }

  Color get color {
    switch (category) {
      case LogCategory.scan:
        return Colors.cyanAccent;
      case LogCategory.gatt:
        return Colors.yellowAccent;
      case LogCategory.proximity:
        return Colors.greenAccent;
      case LogCategory.permission:
        return Colors.purpleAccent;
      case LogCategory.mic:
        return Colors.lightBlueAccent;
      case LogCategory.error:
        return Colors.redAccent;
    }
  }

  String get categoryLabel {
    switch (category) {
      case LogCategory.scan:
        return 'SCAN';
      case LogCategory.gatt:
        return 'GATT';
      case LogCategory.proximity:
        return 'PROX';
      case LogCategory.permission:
        return 'PERM';
      case LogCategory.mic:
        return 'MIC';
      case LogCategory.error:
        return 'ERR';
    }
  }
}

// ---------------------------------------------------------------------------
// BLE Debug Screen
// ---------------------------------------------------------------------------

/// Enhanced development debug screen for testing BLE proximity detection,
/// permissions, and microphone availability on physical devices.
class BleDebugScreen extends ConsumerStatefulWidget {
  const BleDebugScreen({super.key});

  @override
  ConsumerState<BleDebugScreen> createState() => _BleDebugScreenState();
}

class _BleDebugScreenState extends ConsumerState<BleDebugScreen> {
  final BleManager _bleManager = BleManager.instance;

  // -- User ID --
  late final TextEditingController _userIdController;
  String _userId = 'test-user-001';

  // -- Log --
  final List<_LogEntry> _logEntries = [];
  static const int _logCap = 500;
  bool _autoScroll = true;
  final ScrollController _logScrollController = ScrollController();
  final Set<LogCategory> _visibleCategories = Set.of(LogCategory.values);

  // -- Peers --
  final Map<String, BleProximityEvent> _discoveredPeers = {};
  final Map<String, DateTime> _firstSeenMap = {};

  // -- Permissions --
  final Map<Permission, PermissionStatus> _permissionStatuses = {};

  // -- Mic test --
  bool _micTesting = false;
  String? _micTestResult;

  // -- Recordings --
  final Set<String> _expandedConversationIds = {};
  final Set<String> _forceTranscribingIds = {};

  // -- BLE init --
  bool _isInitializing = false;

  // -- Subscriptions --
  StreamSubscription<BleProximityEvent>? _proximitySubscription;
  StreamSubscription<ProximityEvent>? _stateSubscription;
  StreamSubscription<String>? _logSubscription;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // Use the real userId: try BleManager first, then profileProvider
    if (_bleManager.isRunning && _bleManager.currentUserId.isNotEmpty) {
      _userId = _bleManager.currentUserId;
    } else {
      final profile = ref.read(profileProvider).profile;
      if (profile != null) {
        _userId = profile.id;
      }
    }
    _userIdController = TextEditingController(text: _userId);
    _initializeBle();
    _refreshPermissions();
  }

  @override
  void dispose() {
    _proximitySubscription?.cancel();
    _stateSubscription?.cancel();
    _logSubscription?.cancel();
    _userIdController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BLE initialization
  // ---------------------------------------------------------------------------

  Future<void> _initializeBle() async {
    if (_bleManager.isInitialized) {
      _subscribeToStreams();
      return;
    }

    setState(() => _isInitializing = true);

    try {
      await _bleManager.initialize();
      await _bleManager.requestPermissions();
      _addLog('BLE initialized', LogCategory.scan);
    } catch (e) {
      _addLog('Initialization error: $e', LogCategory.error);
    } finally {
      setState(() => _isInitializing = false);
    }

    _subscribeToStreams();
  }

  void _subscribeToStreams() {
    _proximitySubscription = _bleManager.proximityStream.listen((event) {
      if (event.deviceId.isEmpty) return; // skip peripheral-only events
      setState(() {
        _discoveredPeers[event.deviceId] = event;
        _firstSeenMap.putIfAbsent(event.deviceId, () => DateTime.now());
      });
    });

    _stateSubscription =
        _bleManager.proximityStateStream.listen((event) {
      final isDetected = event.type == ProximityEventType.detected;
      _addLog(
        '${isDetected ? "DETECTED" : "LOST"}: ${event.peerId}',
        LogCategory.proximity,
      );
    });

    _logSubscription = _bleManager.logStream.listen((logLine) {
      // Auto-update userId when BLE is started by app_init_provider
      if (_userId == 'test-user-001' &&
          _bleManager.currentUserId.isNotEmpty &&
          _bleManager.currentUserId != 'test-user-001') {
        setState(() {
          _userId = _bleManager.currentUserId;
          _userIdController.text = _userId;
        });
      }
      // Classify incoming BLE log lines
      final category = _classifyBleLog(logLine);
      _addLog(logLine, category);
    });
  }

  LogCategory _classifyBleLog(String log) {
    final lower = log.toLowerCase();
    if (lower.contains('error') || lower.contains('fail')) {
      return LogCategory.error;
    }
    if (lower.contains('exchange') || lower.contains('gatt')) {
      return LogCategory.gatt;
    }
    if (lower.contains('proximity') ||
        lower.contains('detected') ||
        lower.contains('lost')) {
      return LogCategory.proximity;
    }
    return LogCategory.scan;
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  void _addLog(String message, LogCategory category) {
    final entry = _LogEntry(message: message, category: category);
    debugPrint('[BleDebug][${entry.categoryLabel}] ${entry.formatted}');
    setState(() {
      _logEntries.insert(0, entry);
      if (_logEntries.length > _logCap) {
        _logEntries.removeLast();
      }
    });
    if (_autoScroll && _logScrollController.hasClients) {
      // Scroll to top since newest is at index 0
      _logScrollController.jumpTo(0);
    }
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  Future<void> _refreshPermissions() async {
    final permissions = _allPermissions;
    final statuses = <Permission, PermissionStatus>{};
    for (final p in permissions) {
      statuses[p] = await p.status;
    }
    setState(() {
      _permissionStatuses
        ..clear()
        ..addAll(statuses);
    });
  }

  List<Permission> get _allPermissions {
    final perms = <Permission>[
      Permission.microphone,
      Permission.locationWhenInUse,
      Permission.notification,
    ];
    if (Platform.isAndroid) {
      perms.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ]);
    }
    // On iOS, Permission.bluetooth does not correspond to a real runtime
    // permission and falsely reports "permanentlyDenied". The actual
    // Bluetooth state is already shown in the BLE Status section via
    // FlutterBluePlus.adapterState.
    return perms;
  }

  Future<void> _requestAllPermissions() async {
    _addLog('Requesting all permissions...', LogCategory.permission);
    final statuses = await _allPermissions.request();
    setState(() {
      _permissionStatuses
        ..clear()
        ..addAll(statuses);
    });
    for (final entry in statuses.entries) {
      _addLog(
        '${_permissionLabel(entry.key)}: ${_statusLabel(entry.value)}',
        LogCategory.permission,
      );
    }
  }

  Future<void> _requestPermission(Permission permission) async {
    _addLog(
      'Requesting ${_permissionLabel(permission)}...',
      LogCategory.permission,
    );
    final status = await permission.request();
    setState(() => _permissionStatuses[permission] = status);
    _addLog(
      '${_permissionLabel(permission)}: ${_statusLabel(status)}',
      LogCategory.permission,
    );
  }

  String _permissionLabel(Permission p) {
    if (p == Permission.microphone) return 'Microphone';
    if (p == Permission.locationWhenInUse) return 'Location';
    if (p == Permission.notification) return 'Notification';
    if (p == Permission.bluetoothScan) return 'BT Scan';
    if (p == Permission.bluetoothConnect) return 'BT Connect';
    if (p == Permission.bluetoothAdvertise) return 'BT Advertise';
    if (p == Permission.bluetooth) return 'Bluetooth';
    return p.toString();
  }

  String _statusLabel(PermissionStatus s) {
    switch (s) {
      case PermissionStatus.granted:
        return 'Granted';
      case PermissionStatus.denied:
        return 'Denied';
      case PermissionStatus.permanentlyDenied:
        return 'Permanently Denied';
      case PermissionStatus.restricted:
        return 'Restricted';
      case PermissionStatus.limited:
        return 'Limited';
      case PermissionStatus.provisional:
        return 'Provisional';
    }
  }

  Color _statusColor(PermissionStatus s) {
    switch (s) {
      case PermissionStatus.granted:
      case PermissionStatus.limited:
      case PermissionStatus.provisional:
        return Colors.green;
      case PermissionStatus.denied:
        return Colors.orange;
      case PermissionStatus.permanentlyDenied:
      case PermissionStatus.restricted:
        return Colors.red;
    }
  }

  // ---------------------------------------------------------------------------
  // Microphone test
  // ---------------------------------------------------------------------------

  Future<void> _testMicrophone() async {
    setState(() {
      _micTesting = true;
      _micTestResult = null;
    });
    _addLog('Mic test: starting 3s recording...', LogCategory.mic);

    final recorder = AudioRecorder();
    try {
      final hasPermission = await recorder.hasPermission();
      _addLog('Mic hasPermission: $hasPermission', LogCategory.mic);

      if (!hasPermission) {
        setState(() {
          _micTesting = false;
          _micTestResult = 'FAILED - no permission';
        });
        _addLog('Mic test: FAILED - no permission', LogCategory.mic);
        await recorder.dispose();
        return;
      }

      // Get temp directory for test recording
      final dir = Directory.systemTemp;
      final testPath =
          '${dir.path}/linkless_mic_test_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: testPath,
      );

      await Future<void>.delayed(const Duration(seconds: 3));

      final path = await recorder.stop();
      await recorder.dispose();

      // Clean up test file
      if (path != null) {
        final testFile = File(path);
        if (await testFile.exists()) {
          final size = await testFile.length();
          await testFile.delete();
          setState(() {
            _micTestResult = 'SUCCESS ($size bytes recorded)';
          });
          _addLog(
            'Mic test: SUCCESS - $size bytes recorded',
            LogCategory.mic,
          );
        } else {
          setState(() => _micTestResult = 'FAILED - no output file');
          _addLog('Mic test: FAILED - no output file', LogCategory.mic);
        }
      } else {
        setState(() => _micTestResult = 'FAILED - stop returned null');
        _addLog('Mic test: FAILED - stop returned null', LogCategory.mic);
      }
    } catch (e) {
      await recorder.dispose();
      setState(() => _micTestResult = 'ERROR: $e');
      _addLog('Mic test: ERROR - $e', LogCategory.error);
    } finally {
      setState(() => _micTesting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // BLE controls
  // ---------------------------------------------------------------------------

  Future<void> _toggleBle() async {
    if (_bleManager.isRunning) {
      await _bleManager.stop();
    } else {
      _userId = _userIdController.text.trim();
      if (_userId.isEmpty) _userId = 'test-user-001';
      await _bleManager.start(_userId);
    }
    setState(() {});
  }

  void _clearExchangedDevices() {
    _bleManager.clearExchangedDevices();
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Log export
  // ---------------------------------------------------------------------------

  Future<void> _exportLog() async {
    final buffer = StringBuffer();
    // Reverse so oldest is first in export
    for (final entry in _logEntries.reversed) {
      buffer.writeln('[${entry.categoryLabel}] ${entry.formatted}');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${Directory.systemTemp.path}/linkless_ble_debug_$timestamp.log',
    );
    await file.writeAsString(buffer.toString());
    final path = file.path;

    debugPrint('[BleDebug] Log exported to: $path');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Log written to:\n$path'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('BLE Debug'),
        backgroundColor: AppColors.backgroundDarker,
        foregroundColor: AppColors.textPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh permissions',
            onPressed: _refreshPermissions,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all',
            onPressed: () {
              setState(() {
                _logEntries.clear();
                _discoveredPeers.clear();
                _firstSeenMap.clear();
              });
            },
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildPermissionsSection(),
                _buildMicTestSection(),
                _buildBleStatusSection(),
                _buildControlsSection(),
                _buildPeersSection(),
                _buildRecordingsSection(),
                _buildLogSection(),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // A. Permissions Dashboard
  // ---------------------------------------------------------------------------

  Widget _buildPermissionsSection() {
    return _buildSection(
      title: 'Permissions',
      child: Column(
        children: [
          ..._allPermissions.map(_buildPermissionRow),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _requestAllPermissions,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Request All Permissions'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRow(Permission permission) {
    final status = _permissionStatuses[permission];
    final label = _permissionLabel(permission);
    final statusText = status != null ? _statusLabel(status) : 'Unknown';
    final color =
        status != null ? _statusColor(status) : Colors.grey;
    final isPermanentlyDenied =
        status == PermissionStatus.permanentlyDenied;
    final isDenied = status == PermissionStatus.denied;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (isDenied)
            _buildSmallButton('Request', () => _requestPermission(permission)),
          if (isPermanentlyDenied)
            _buildSmallButton('Settings', () => openAppSettings()),
        ],
      ),
    );
  }

  Widget _buildSmallButton(String label, VoidCallback onPressed) {
    return SizedBox(
      height: 26,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: AppColors.accentBlue,
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // B. Microphone Test Section
  // ---------------------------------------------------------------------------

  Widget _buildMicTestSection() {
    final micStatus = _permissionStatuses[Permission.microphone];
    final isGranted = micStatus == PermissionStatus.granted;

    return _buildSection(
      title: 'Microphone Test',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isGranted ? Colors.green : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Microphone: ${micStatus != null ? _statusLabel(micStatus) : "Unknown"}',
                style: TextStyle(
                  color: isGranted ? Colors.green : Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _micTesting ? null : _testMicrophone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _micTesting ? Colors.grey : AppColors.accentBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: _micTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Test Mic (3s)'),
                ),
              ),
            ],
          ),
          if (_micTestResult != null) ...[
            const SizedBox(height: 6),
            Text(
              _micTestResult!,
              style: TextStyle(
                color: _micTestResult!.startsWith('SUCCESS')
                    ? Colors.green
                    : Colors.red,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // C. BLE Status Header
  // ---------------------------------------------------------------------------

  Widget _buildBleStatusSection() {
    return _buildSection(
      title: 'BLE Status',
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
          Builder(builder: (context) {
            final state = _bleManager.adapterState;
            final isOn = state == BluetoothAdapterState.on;
            return _buildStatusRow(
              'Bluetooth',
              _adapterStateLabel(state),
              valueColor: isOn ? Colors.green : Colors.red,
            );
          }),
          _buildStatusRow(
            'Scanning',
            _bleManager.isRunning ? 'Active' : 'Stopped',
            valueColor:
                _bleManager.isRunning ? Colors.green : AppColors.textTertiary,
          ),
          _buildStatusRow(
            'Advertising',
            _bleManager.peripheralService.isAdvertising
                ? 'Active'
                : 'Stopped',
            valueColor: _bleManager.peripheralService.isAdvertising
                ? Colors.green
                : AppColors.textTertiary,
          ),
          _buildStatusRow('User ID', _userId),
          const Divider(color: AppColors.divider, height: 12),
          _buildStatusRow(
            'RSSI Enter',
            '${BleConstants.enterRssiThreshold} dBm',
          ),
          _buildStatusRow(
            'RSSI Exit',
            '${BleConstants.exitRssiThreshold} dBm',
          ),
          _buildStatusRow(
            'Scan Cycle',
            '${BleConstants.scanTimeout.inSeconds}s scan / '
                '${BleConstants.scanInterval.inSeconds}s pause',
          ),
          _buildStatusRow(
            'Exchanged',
            '${_bleManager.exchangedDeviceCount} device(s)',
          ),
          _buildStatusRow(
            'SM Peers',
            '${_bleManager.stateMachine.peerCount}',
          ),
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
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? AppColors.textPrimary,
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
  // D. BLE Controls
  // ---------------------------------------------------------------------------

  Widget _buildControlsSection() {
    return _buildSection(
      title: 'Controls',
      child: Column(
        children: [
          // User ID input
          TextField(
            controller: _userIdController,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              labelText: 'User ID',
              labelStyle: const TextStyle(color: AppColors.textSecondary),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: AppColors.backgroundCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.accentBlue),
              ),
            ),
            onChanged: (v) => _userId = v.trim(),
          ),
          const SizedBox(height: 10),
          // Start/Stop + Clear buttons
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  onPressed: _toggleBle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _bleManager.isRunning
                        ? Colors.red.shade600
                        : Colors.green.shade600,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_bleManager.isRunning ? 'Stop BLE' : 'Start BLE'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: _clearExchangedDevices,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: const Text(
                    'Clear Exchanges',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // E. Discovered Peers
  // ---------------------------------------------------------------------------

  Widget _buildPeersSection() {
    final peers = _discoveredPeers.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return _buildSection(
      title: 'Discovered Peers (${peers.length})',
      child: peers.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No peers discovered yet',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                ),
              ),
            )
          : Column(children: peers.map(_buildPeerTile).toList()),
    );
  }

  Widget _buildPeerTile(BleProximityEvent peer) {
    final userId = _bleManager.deviceToUserIdMap[peer.deviceId];
    // Use resolved userId for state machine lookups since peerId remapping
    // changes the key from deviceId to userId after GATT exchange.
    final resolvedId = userId ?? peer.deviceId;
    final state = _bleManager.stateMachine.getState(resolvedId);
    final filteredRssi = _bleManager.stateMachine.getFilteredRssi(resolvedId);
    final isExchanged = _bleManager.isDeviceExchanged(peer.deviceId);

    // Time since first seen
    final firstSeen = _firstSeenMap[peer.deviceId];
    final timeSinceFirstSeen = firstSeen != null
        ? DateTime.now().difference(firstSeen)
        : Duration.zero;

    // Last seen
    final timeSinceLast = DateTime.now().difference(peer.timestamp);
    final lastSeenText = timeSinceLast.inSeconds < 60
        ? '${timeSinceLast.inSeconds}s ago'
        : '${timeSinceLast.inMinutes}m ago';

    // First seen duration
    final firstSeenText = timeSinceFirstSeen.inMinutes > 0
        ? '${timeSinceFirstSeen.inMinutes}m ${timeSinceFirstSeen.inSeconds % 60}s'
        : '${timeSinceFirstSeen.inSeconds}s';

    // State styling
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

    // GATT exchange status
    String gattStatus;
    Color gattColor;
    if (userId != null) {
      gattStatus = 'OK';
      gattColor = Colors.green;
    } else if (isExchanged) {
      gattStatus = 'FAIL';
      gattColor = Colors.red;
    } else {
      gattStatus = 'PENDING';
      gattColor = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: stateColor, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: name + state badge
          Row(
            children: [
              Expanded(
                child: userId != null
                    ? Consumer(builder: (context, ref, _) {
                        final profileAsync =
                            ref.watch(peerProfileProvider(userId));
                        return profileAsync.when(
                          data: (profile) => Text(
                            profile.displayName ??
                                profile.initials ??
                                userId,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          loading: () => Text(
                            _truncateId(userId),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          error: (_, __) => Text(
                            _truncateId(userId),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      })
                    : Text(
                        _truncateId(peer.deviceId),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                      ),
              ),
              _buildBadge(stateLabel, stateColor),
            ],
          ),
          if (userId != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Device: ${_truncateId(peer.deviceId)}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          const SizedBox(height: 4),
          // Bottom row: RSSI info + timing + GATT
          Row(
            children: [
              // Raw RSSI
              Text(
                'RSSI: ${peer.rssi}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              // Filtered RSSI
              if (filteredRssi != null)
                Text(
                  'Filt: ${filteredRssi.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.cyanAccent,
                  ),
                ),
              const Spacer(),
              // GATT status
              _buildBadge('GATT:$gattStatus', gattColor),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                'Last: $lastSeenText',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Since: $firstSeenText',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // E2. Recordings
  // ---------------------------------------------------------------------------

  Widget _buildRecordingsSection() {
    final conversationsAsync = ref.watch(conversationListProvider);

    return conversationsAsync.when(
      loading: () => _buildSection(
        title: 'Recordings',
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (error, _) => _buildSection(
        title: 'Recordings',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Error: $error',
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ),
      data: (conversations) {
        final failedCount = conversations
            .where((c) => c.syncStatus == 'failed')
            .length;

        return _buildSection(
          title: 'Recordings (${conversations.length})',
          child: conversations.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'No recordings yet',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (failedCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text(
                              '$failedCount failed',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const Spacer(),
                            _buildSmallButton('Retry All', () {
                              ref.read(syncEngineProvider).retryFailed();
                              _addLog(
                                'Retry all failed triggered',
                                LogCategory.gatt,
                              );
                            }),
                          ],
                        ),
                      ),
                    ...conversations
                        .map(_buildConversationTile),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _forceTranscribe(ConversationLocal conversation) async {
    final serverId = conversation.serverId;
    if (serverId == null) return;

    setState(() => _forceTranscribingIds.add(conversation.id));

    try {
      final apiService = ref.read(conversationApiServiceProvider);
      await apiService.confirmUpload(serverId);

      // Reset sync status to 'uploaded' so poll cycle picks up the new transcript
      final dao = ref.read(conversationDaoProvider);
      await dao.updateSyncStatus(conversation.id, 'uploaded');

      // Invalidate the cached detail to force a refresh
      ref.invalidate(conversationDetailProvider(serverId));
    } catch (e) {
      debugPrint('[DebugScreen] Force transcribe failed: $e');
    } finally {
      if (mounted) {
        setState(() => _forceTranscribingIds.remove(conversation.id));
      }
    }
  }

  Widget _buildConversationTile(ConversationLocal conversation) {
    final isExpanded = _expandedConversationIds.contains(conversation.id);

    // Sync status badge
    Color syncColor;
    String syncLabel;
    switch (conversation.syncStatus) {
      case 'pending':
      case 'uploading':
        syncColor = Colors.orange;
        syncLabel = conversation.syncStatus.toUpperCase();
      case 'uploaded':
      case 'transcribing':
        syncColor = Colors.amber;
        syncLabel = conversation.syncStatus.toUpperCase();
      case 'completed':
        syncColor = Colors.green;
        syncLabel = 'COMPLETED';
      case 'failed':
        syncColor = Colors.red;
        syncLabel = 'FAILED';
      default:
        syncColor = Colors.grey;
        syncLabel = conversation.syncStatus.toUpperCase();
    }

    // Format date/time
    final dt = conversation.startedAt;
    final dateStr =
        '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedConversationIds.remove(conversation.id);
          } else {
            _expandedConversationIds.add(conversation.id);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: syncColor, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    _truncateId(conversation.peerId),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (conversation.syncStatus == 'failed')
                  _buildSmallButton('Retry', () async {
                    final dao = ref.read(conversationDaoProvider);
                    await dao.updateSyncStatus(conversation.id, 'pending');
                    ref.read(syncEngineProvider).syncNow();
                    _addLog(
                      'Retry triggered for ${_truncateId(conversation.id)}',
                      LogCategory.gatt,
                    );
                  }),
                if (conversation.syncStatus == 'uploaded' ||
                    conversation.syncStatus == 'transcribing')
                  _buildSmallButton('Poll', () async {
                    await ref
                        .read(syncEngineProvider)
                        .pollSingleConversation(conversation.id);
                    if (conversation.serverId != null) {
                      ref.invalidate(
                        conversationDetailProvider(conversation.serverId!),
                      );
                    }
                    _addLog(
                      'Poll triggered for ${_truncateId(conversation.id)}',
                      LogCategory.gatt,
                    );
                  }),
                const SizedBox(width: 4),
                _buildBadge(syncLabel, syncColor),
              ],
            ),
            const SizedBox(height: 4),
            // Date + duration row
            Row(
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  conversation.displayDuration,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Icon(
                  isExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            // Expanded transcript area
            if (isExpanded) ...[
              const Divider(color: AppColors.divider, height: 12),
              if (conversation.serverId != null)
                _buildTranscriptArea(conversation.serverId!)
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Not uploaded yet -- transcript unavailable',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              if (conversation.serverId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _forceTranscribingIds.contains(conversation.id)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => _forceTranscribe(conversation),
                          icon: const Icon(Icons.refresh, size: 14),
                          label: const Text(
                            'Force Transcribe',
                            style: TextStyle(fontSize: 11),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.cyanAccent,
                            side: const BorderSide(
                              color: Colors.cyanAccent,
                              width: 0.5,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptArea(String conversationId) {
    final detailAsync = ref.watch(conversationDetailProvider(conversationId));

    return detailAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Error loading transcript: $error',
          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
        ),
      ),
      data: (detail) {
        if (detail == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No transcript yet',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          );
        }

        // Extract transcript content
        final transcriptRaw = detail['transcript'];
        final provider = detail['provider'] as String?;

        List<dynamic>? utterances;
        if (transcriptRaw is String && transcriptRaw.isNotEmpty) {
          try {
            utterances = jsonDecode(transcriptRaw) as List<dynamic>;
          } catch (_) {
            // Not valid JSON, show as plain text
          }
        } else if (transcriptRaw is List) {
          utterances = transcriptRaw;
        }

        if (utterances == null || utterances.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No transcript yet',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...utterances.map((u) {
              final speaker = u['speaker'] ?? '??';
              final text = u['text'] ?? '';
              final start = u['start'];
              final timeStr = start != null
                  ? '[${_formatTranscriptTime(start)}] '
                  : '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$timeStr$speaker: ',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(
                        text: '$text',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              );
            }),
            if (provider != null) ...[
              const SizedBox(height: 4),
              Text(
                'Provider: $provider',
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            // Summary display
            _buildSummaryArea(detail),
          ],
        );
      },
    );
  }

  Widget _buildSummaryArea(Map<String, dynamic> detail) {
    final summaryRaw = detail['summary'];
    if (summaryRaw == null || summaryRaw is! Map<String, dynamic>) {
      return const SizedBox.shrink();
    }

    final summary = summaryRaw;
    final content = summary['content'] as String?;
    if (content == null || content.isEmpty) {
      return const SizedBox.shrink();
    }

    final summaryProvider = summary['provider'] as String?;

    // Parse key_topics (handle both String JSON and List)
    final keyTopicsRaw = summary['key_topics'];
    List<String> keyTopics = [];
    if (keyTopicsRaw is List) {
      keyTopics = keyTopicsRaw.map((e) => e.toString()).toList();
    } else if (keyTopicsRaw is String && keyTopicsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(keyTopicsRaw);
        if (decoded is List) {
          keyTopics = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        // Not valid JSON, ignore
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: AppColors.divider, height: 16),
        const Text(
          'Summary:',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
        if (keyTopics.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Topics: ${keyTopics.join(' | ')}',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
        if (summaryProvider != null) ...[
          const SizedBox(height: 2),
          Text(
            'Summarized by $summaryProvider',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }

  String _formatTranscriptTime(dynamic seconds) {
    final totalSeconds = (seconds is num) ? seconds.toInt() : 0;
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // F. Event Log
  // ---------------------------------------------------------------------------

  Widget _buildLogSection() {
    final filteredEntries = _logEntries
        .where((e) => _visibleCategories.contains(e.category))
        .toList();

    return _buildSection(
      title: 'Event Log (${filteredEntries.length}/${_logEntries.length})',
      darkBackground: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter chips + controls
          _buildLogControls(),
          const SizedBox(height: 6),
          // Log list
          SizedBox(
            height: 350,
            child: filteredEntries.isEmpty
                ? const Center(
                    child: Text(
                      'No events yet',
                      style:
                          TextStyle(color: AppColors.textTertiary, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = filteredEntries[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '[${entry.categoryLabel}] ',
                                style: TextStyle(
                                  color: entry.color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: entry.formatted,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogControls() {
    return Column(
      children: [
        // Filter chips
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: LogCategory.values.map((cat) {
            final entry = _LogEntry(message: '', category: cat);
            final isActive = _visibleCategories.contains(cat);
            return FilterChip(
              label: Text(
                entry.categoryLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? Colors.black : AppColors.textTertiary,
                ),
              ),
              selected: isActive,
              selectedColor: entry.color.withValues(alpha: 0.7),
              backgroundColor: AppColors.backgroundCard,
              checkmarkColor: Colors.black,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _visibleCategories.add(cat);
                  } else {
                    _visibleCategories.remove(cat);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        // Auto-scroll toggle + Export
        Row(
          children: [
            SizedBox(
              height: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _autoScroll,
                      onChanged: (v) =>
                          setState(() => _autoScroll = v ?? true),
                      activeColor: AppColors.accentBlue,
                      side: const BorderSide(color: AppColors.textTertiary),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Auto-scroll',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 26,
              child: TextButton.icon(
                onPressed: _logEntries.isEmpty ? null : _exportLog,
                icon: const Icon(Icons.save_alt, size: 14),
                label: const Text('Export', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.accentBlue,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared section wrapper
  // ---------------------------------------------------------------------------

  Widget _buildSection({
    required String title,
    required Widget child,
    bool darkBackground = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: darkBackground
            ? AppColors.backgroundDarker
            : AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
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
