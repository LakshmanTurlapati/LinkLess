import 'package:flutter_test/flutter_test.dart';
import 'package:linkless/ble/rssi_filter.dart';

void main() {
  group('RssiFilter', () {
    late RssiFilter filter;

    setUp(() {
      filter = RssiFilter();
    });

    group('first reading', () {
      test('returns raw value without smoothing', () {
        final result = filter.update(-70);
        expect(result, -70.0);
      });

      test('sets currentRssi to first value', () {
        filter.update(-65);
        expect(filter.currentRssi, -65.0);
      });
    });

    group('exponential moving average', () {
      test('smooths second reading with default alpha 0.3', () {
        filter.update(-70);
        final result = filter.update(-60);
        // 0.3 * (-60) + 0.7 * (-70) = -18 + -49 = -67.0
        expect(result, closeTo(-67.0, 0.001));
      });

      test('smooths third reading correctly', () {
        filter.update(-70);
        filter.update(-60); // -> -67.0
        final result = filter.update(-80);
        // 0.3 * (-80) + 0.7 * (-67) = -24 + -46.9 = -70.9
        expect(result, closeTo(-70.9, 0.001));
      });

      test('converges toward repeated values', () {
        filter.update(-70);
        // Feed many -50 readings, should converge toward -50
        double last = -70.0;
        for (int i = 0; i < 50; i++) {
          last = filter.update(-50);
        }
        expect(last, closeTo(-50.0, 0.1));
      });
    });

    group('configurable alpha', () {
      test('alpha=1.0 means no smoothing (raw passthrough)', () {
        final noSmooth = RssiFilter(alpha: 1.0);
        noSmooth.update(-70);
        final result = noSmooth.update(-60);
        expect(result, -60.0);
      });

      test('alpha=0.0 means infinite smoothing (stuck at first)', () {
        final maxSmooth = RssiFilter(alpha: 0.0);
        maxSmooth.update(-70);
        final result = maxSmooth.update(-60);
        expect(result, -70.0);
      });

      test('alpha=0.5 gives equal weight', () {
        final half = RssiFilter(alpha: 0.5);
        half.update(-70);
        final result = half.update(-60);
        // 0.5 * (-60) + 0.5 * (-70) = -65
        expect(result, closeTo(-65.0, 0.001));
      });
    });

    group('reset', () {
      test('clears state so next update is treated as first', () {
        filter.update(-70);
        filter.update(-60); // -> -67
        filter.reset();

        final result = filter.update(-50);
        expect(result, -50.0);
      });

      test('currentRssi is null after reset', () {
        filter.update(-70);
        filter.reset();
        expect(filter.currentRssi, isNull);
      });
    });

    group('currentRssi getter', () {
      test('returns null before any update', () {
        expect(filter.currentRssi, isNull);
      });

      test('returns last filtered value', () {
        filter.update(-70);
        filter.update(-60);
        expect(filter.currentRssi, closeTo(-67.0, 0.001));
      });
    });
  });
}
