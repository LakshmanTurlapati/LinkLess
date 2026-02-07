/// Exponential Moving Average (EMA) filter for smoothing noisy RSSI values.
///
/// Raw BLE RSSI readings fluctuate significantly. This filter smooths them
/// using the formula: filtered = alpha * raw + (1 - alpha) * previous.
///
/// Lower alpha means more smoothing (slower response to changes).
/// Higher alpha means less smoothing (faster response, more noise).
class RssiFilter {
  /// Smoothing factor. 0.0 = max smoothing, 1.0 = no smoothing.
  final double alpha;

  double? _filteredRssi;
  bool _initialized = false;

  RssiFilter({this.alpha = 0.3});

  /// Feed a raw RSSI reading and get the filtered value.
  ///
  /// First reading initializes the filter (returned as-is).
  /// Subsequent readings are smoothed using EMA.
  double update(int rawRssi) {
    final raw = rawRssi.toDouble();

    if (!_initialized) {
      _filteredRssi = raw;
      _initialized = true;
      return raw;
    }

    _filteredRssi = alpha * raw + (1 - alpha) * _filteredRssi!;
    return _filteredRssi!;
  }

  /// Returns the last filtered RSSI value, or null if no readings yet.
  double? get currentRssi => _filteredRssi;

  /// Reset filter to uninitialized state.
  void reset() {
    _filteredRssi = null;
    _initialized = false;
  }
}
