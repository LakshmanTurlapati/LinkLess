import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkless/ble/proximity_state_machine.dart';

void main() {
  group('ProximityStateMachine', () {
    late ProximityStateMachine machine;
    final defaultEnterThreshold = -70;
    final defaultExitThreshold = -80;
    final defaultDebounceDuration = Duration(seconds: 10);

    setUp(() {
      machine = ProximityStateMachine(
        enterThreshold: defaultEnterThreshold,
        exitThreshold: defaultExitThreshold,
        debounceDuration: defaultDebounceDuration,
      );
    });

    tearDown(() {
      machine.dispose();
    });

    group('initial state', () {
      test('peer starts in idle state', () {
        expect(machine.getState('peer1'), ProximityState.idle);
      });

      test('events stream is empty initially', () {
        expectLater(
          machine.events,
          neverEmits(anything),
        );
        // Give it a moment then dispose
        machine.dispose();
      });
    });

    group('IDLE -> DETECTED transition', () {
      test('strong RSSI causes transition to detected', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Feed enough strong readings to push filtered RSSI above threshold
          // First reading: -60 (above -70 threshold)
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          expect(machine.getState('peer1'), ProximityState.detected);
          expect(events, hasLength(1));
          expect(events.first.type, ProximityEventType.detected);
          expect(events.first.peerId, 'peer1');
        });
      });

      test('weak RSSI keeps state idle', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // -85 is below enter threshold of -70
          machine.onPeerDiscovered('peer1', -85);
          async.flushMicrotasks();

          expect(machine.getState('peer1'), ProximityState.idle);
          expect(events, isEmpty);
        });
      });

      test('borderline RSSI at exact threshold causes transition', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Exactly at -70 threshold (>= check)
          machine.onPeerDiscovered('peer1', -70);
          async.flushMicrotasks();

          expect(machine.getState('peer1'), ProximityState.detected);
          expect(events, hasLength(1));
        });
      });
    });

    group('hysteresis', () {
      test('RSSI between enter and exit thresholds keeps detected state', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Enter detected state
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();
          expect(machine.getState('peer1'), ProximityState.detected);

          // RSSI drops to -75 (between -70 and -80 -- in hysteresis gap)
          // Filtered RSSI: 0.3*(-75) + 0.7*(-60) = -22.5 + -42 = -64.5
          // Still above exit threshold -80, so stays detected
          machine.onPeerDiscovered('peer1', -75);
          async.flushMicrotasks();

          expect(machine.getState('peer1'), ProximityState.detected);
          // Only the initial detected event
          expect(events, hasLength(1));
        });
      });

      test('RSSI dropping below exit threshold starts debounce', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Enter detected state
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // Feed many weak readings to push filtered RSSI below exit threshold
          for (int i = 0; i < 20; i++) {
            machine.onPeerDiscovered('peer1', -95);
          }
          async.flushMicrotasks();

          // Should still be detected during debounce
          expect(machine.getState('peer1'), ProximityState.detected);

          // After debounce expires -> idle
          async.elapse(defaultDebounceDuration);
          expect(machine.getState('peer1'), ProximityState.idle);
          expect(events.last.type, ProximityEventType.lost);
        });
      });
    });

    group('debounce behavior', () {
      test('strong RSSI during debounce cancels transition to idle', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Enter detected
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // Push below exit threshold
          for (int i = 0; i < 20; i++) {
            machine.onPeerDiscovered('peer1', -95);
          }
          async.flushMicrotasks();

          // Wait 5 seconds (half of debounce)
          async.elapse(Duration(seconds: 5));
          expect(machine.getState('peer1'), ProximityState.detected);

          // Strong signal returns -- push filtered RSSI back above enter threshold
          for (int i = 0; i < 20; i++) {
            machine.onPeerDiscovered('peer1', -50);
          }
          async.flushMicrotasks();

          // Wait full debounce period -- should NOT transition to idle
          async.elapse(defaultDebounceDuration);
          expect(machine.getState('peer1'), ProximityState.detected);

          // Should only have the initial detected event (no lost event)
          expect(events.where((e) => e.type == ProximityEventType.lost), isEmpty);
        });
      });

      test('debounce timer expires emits lost event', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Enter detected
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // Push below exit threshold
          for (int i = 0; i < 20; i++) {
            machine.onPeerDiscovered('peer1', -95);
          }
          async.flushMicrotasks();

          // Debounce not yet expired
          async.elapse(Duration(seconds: 9));
          expect(events.where((e) => e.type == ProximityEventType.lost), isEmpty);

          // Debounce expires
          async.elapse(Duration(seconds: 1));
          expect(events.last.type, ProximityEventType.lost);
          expect(events.last.peerId, 'peer1');
        });
      });

      test('detected state does not re-emit event on continued strong RSSI', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          machine.onPeerDiscovered('peer1', -55);
          async.flushMicrotasks();

          machine.onPeerDiscovered('peer1', -50);
          async.flushMicrotasks();

          // Only one detected event despite multiple strong readings
          expect(events, hasLength(1));
          expect(events.first.type, ProximityEventType.detected);
        });
      });
    });

    group('onPeerLost', () {
      test('starts debounce timer when peer was detected', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Enter detected
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // BLE scan lost the peer
          machine.onPeerLost('peer1');
          async.flushMicrotasks();

          // Still detected during debounce
          expect(machine.getState('peer1'), ProximityState.detected);

          // After debounce -> idle
          async.elapse(defaultDebounceDuration);
          expect(machine.getState('peer1'), ProximityState.idle);
          expect(events.last.type, ProximityEventType.lost);
        });
      });

      test('onPeerLost for idle peer is a no-op', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          machine.onPeerLost('unknown_peer');
          async.flushMicrotasks();
          async.elapse(defaultDebounceDuration);

          expect(events, isEmpty);
        });
      });

      test('peer rediscovered during debounce from onPeerLost cancels idle transition', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Enter detected
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // Peer lost
          machine.onPeerLost('peer1');
          async.flushMicrotasks();

          // Wait 5 seconds
          async.elapse(Duration(seconds: 5));

          // Peer reappears with strong signal
          machine.onPeerDiscovered('peer1', -55);
          async.flushMicrotasks();

          // Full debounce period passes -- should still be detected
          async.elapse(defaultDebounceDuration);
          expect(machine.getState('peer1'), ProximityState.detected);
          expect(events.where((e) => e.type == ProximityEventType.lost), isEmpty);
        });
      });
    });

    group('multiple peers tracked independently', () {
      test('two peers have independent states', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // peer1 enters detected
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // peer2 stays idle (weak signal)
          machine.onPeerDiscovered('peer2', -90);
          async.flushMicrotasks();

          expect(machine.getState('peer1'), ProximityState.detected);
          expect(machine.getState('peer2'), ProximityState.idle);

          final detectedEvents = events.where((e) => e.type == ProximityEventType.detected);
          expect(detectedEvents, hasLength(1));
          expect(detectedEvents.first.peerId, 'peer1');
        });
      });

      test('peer1 debounce does not affect peer2', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Both enter detected
          machine.onPeerDiscovered('peer1', -60);
          machine.onPeerDiscovered('peer2', -55);
          async.flushMicrotasks();

          // peer1 drops signal
          for (int i = 0; i < 20; i++) {
            machine.onPeerDiscovered('peer1', -95);
          }
          async.flushMicrotasks();

          // After debounce, peer1 -> idle, peer2 -> still detected
          async.elapse(defaultDebounceDuration);
          expect(machine.getState('peer1'), ProximityState.idle);
          expect(machine.getState('peer2'), ProximityState.detected);
        });
      });
    });

    group('resetPeer', () {
      test('removed peer can be re-detected with fresh DETECTED event', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Enter detected state
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();
          expect(machine.getState('peer1'), ProximityState.detected);
          expect(events, hasLength(1));
          expect(events.last.type, ProximityEventType.detected);

          // Reset the peer
          machine.resetPeer('peer1');
          expect(machine.getState('peer1'), ProximityState.idle);
          expect(machine.peerCount, 0);

          // Re-discover the same peer -- should emit a fresh DETECTED event
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();
          expect(machine.getState('peer1'), ProximityState.detected);
          expect(events, hasLength(2));
          expect(events.last.type, ProximityEventType.detected);
          expect(events.last.peerId, 'peer1');
        });
      });

      test('resetting unknown peer is a no-op', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Reset a peer that was never tracked
          machine.resetPeer('unknown_peer');
          async.flushMicrotasks();

          expect(events, isEmpty);
          expect(machine.peerCount, 0);
        });
      });

      test('reset cancels active debounce timer (no spurious LOST event)', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Enter detected state
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // Push below exit threshold to start debounce
          for (int i = 0; i < 20; i++) {
            machine.onPeerDiscovered('peer1', -95);
          }
          async.flushMicrotasks();
          expect(machine.getState('peer1'), ProximityState.detected);

          // Reset peer while debounce is running
          machine.resetPeer('peer1');

          // Advance past debounce duration -- should NOT emit LOST event
          async.elapse(defaultDebounceDuration);
          final lostEvents = events.where(
            (e) => e.type == ProximityEventType.lost,
          );
          expect(lostEvents, isEmpty);
        });
      });
    });

    group('resetAllPeers', () {
      test('emits LOST events for all detected peers', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Detect two peers
          machine.onPeerDiscovered('peer1', -60);
          machine.onPeerDiscovered('peer2', -55);
          async.flushMicrotasks();
          expect(events, hasLength(2));
          expect(machine.getState('peer1'), ProximityState.detected);
          expect(machine.getState('peer2'), ProximityState.detected);

          // Reset all peers
          machine.resetAllPeers();
          async.flushMicrotasks();

          // Should have 2 LOST events
          final lostEvents = events.where(
            (e) => e.type == ProximityEventType.lost,
          ).toList();
          expect(lostEvents, hasLength(2));
          final lostPeerIds = lostEvents.map((e) => e.peerId).toSet();
          expect(lostPeerIds, containsAll(['peer1', 'peer2']));
        });
      });

      test('does not emit LOST events for idle peers', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Add an idle peer (weak signal, stays idle)
          machine.onPeerDiscovered('idle_peer', -90);
          async.flushMicrotasks();
          expect(machine.getState('idle_peer'), ProximityState.idle);

          // Add a detected peer
          machine.onPeerDiscovered('detected_peer', -60);
          async.flushMicrotasks();
          expect(machine.getState('detected_peer'), ProximityState.detected);

          events.clear();

          // Reset all peers
          machine.resetAllPeers();
          async.flushMicrotasks();

          // Only 1 LOST event (for the detected peer)
          expect(events, hasLength(1));
          expect(events.first.type, ProximityEventType.lost);
          expect(events.first.peerId, 'detected_peer');
        });
      });

      test('peer map is empty after reset', () {
        fakeAsync((async) {
          machine.onPeerDiscovered('peer1', -60);
          machine.onPeerDiscovered('peer2', -55);
          async.flushMicrotasks();
          expect(machine.peerCount, 2);

          machine.resetAllPeers();
          expect(machine.peerCount, 0);
        });
      });

      test('debounce timers are cancelled (no spurious events after reset)', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          // Detect peer and start debounce
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // Push below exit threshold to start debounce timer
          for (int i = 0; i < 20; i++) {
            machine.onPeerDiscovered('peer1', -95);
          }
          async.flushMicrotasks();

          // Reset all peers (should cancel debounce timer)
          machine.resetAllPeers();
          async.flushMicrotasks();

          final lostCount = events.where(
            (e) => e.type == ProximityEventType.lost,
          ).length;
          expect(lostCount, 1); // Only from resetAllPeers

          // Advance past debounce -- should NOT emit another LOST event
          async.elapse(defaultDebounceDuration);
          final lostCountAfter = events.where(
            (e) => e.type == ProximityEventType.lost,
          ).length;
          expect(lostCountAfter, 1); // Still just 1
        });
      });

      test('no-op when no peers are tracked', () {
        fakeAsync((async) {
          final events = <ProximityEvent>[];
          machine.events.listen(events.add);

          machine.resetAllPeers();
          async.flushMicrotasks();

          expect(events, isEmpty);
          expect(machine.peerCount, 0);
        });
      });
    });

    group('getLastSeenAt', () {
      test('returns null for unknown peer', () {
        expect(machine.getLastSeenAt('unknown_peer'), isNull);
      });

      test('returns timestamp after peer discovered', () {
        fakeAsync((async) {
          final before = DateTime.now();
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();
          final lastSeen = machine.getLastSeenAt('peer1');
          expect(lastSeen, isNotNull);
          expect(
            lastSeen!.isAfter(before) || lastSeen.isAtSameMomentAs(before),
            isTrue,
          );
        });
      });

      test('updates on each discovery', () {
        fakeAsync((async) {
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();
          final firstSeen = machine.getLastSeenAt('peer1');

          async.elapse(Duration(seconds: 1));

          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();
          final secondSeen = machine.getLastSeenAt('peer1');

          expect(secondSeen, isNotNull);
          expect(firstSeen, isNotNull);
          expect(secondSeen!.isAfter(firstSeen!), isTrue);
        });
      });

      test('returns null after resetPeer', () {
        fakeAsync((async) {
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();
          expect(machine.getLastSeenAt('peer1'), isNotNull);

          machine.resetPeer('peer1');
          expect(machine.getLastSeenAt('peer1'), isNull);
        });
      });

      test('returns null after resetAllPeers', () {
        fakeAsync((async) {
          machine.onPeerDiscovered('peer1', -60);
          machine.onPeerDiscovered('peer2', -55);
          async.flushMicrotasks();
          expect(machine.getLastSeenAt('peer1'), isNotNull);
          expect(machine.getLastSeenAt('peer2'), isNotNull);

          machine.resetAllPeers();
          expect(machine.getLastSeenAt('peer1'), isNull);
          expect(machine.getLastSeenAt('peer2'), isNull);
        });
      });
    });

    group('dispose', () {
      test('disposes cleanly without errors', () {
        fakeAsync((async) {
          machine.onPeerDiscovered('peer1', -60);
          async.flushMicrotasks();

          // Should not throw
          expect(() => machine.dispose(), returnsNormally);
        });
      });
    });

    group('configurable thresholds', () {
      test('custom thresholds are respected', () {
        fakeAsync((async) {
          final custom = ProximityStateMachine(
            enterThreshold: -50,
            exitThreshold: -60,
            debounceDuration: Duration(seconds: 5),
          );
          final events = <ProximityEvent>[];
          custom.events.listen(events.add);

          // -55 is below custom enter threshold of -50
          custom.onPeerDiscovered('peer1', -55);
          async.flushMicrotasks();
          expect(custom.getState('peer1'), ProximityState.idle);

          // -45 is above custom enter threshold of -50
          custom.onPeerDiscovered('peer1', -45);
          async.flushMicrotasks();
          // Filtered: 0.3*(-45) + 0.7*(-55) = -13.5 + -38.5 = -52.0
          // Still below -50 threshold due to smoothing
          // Need more strong readings
          for (int i = 0; i < 10; i++) {
            custom.onPeerDiscovered('peer1', -40);
          }
          async.flushMicrotasks();
          expect(custom.getState('peer1'), ProximityState.detected);

          custom.dispose();
        });
      });
    });
  });
}
