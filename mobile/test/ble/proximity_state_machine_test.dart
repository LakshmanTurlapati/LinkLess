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
