import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Provides one-shot GPS location capture with timeout and graceful fallback.
///
/// GPS capture is designed to never block or fail the recording flow.
/// If location is unavailable for any reason, [getCurrentPosition] returns
/// `null` and recording proceeds without coordinates.
class GpsService {
  /// Captures a single GPS fix with a 5-second timeout.
  ///
  /// Returns `null` if:
  /// - Location services are disabled on the device
  /// - Location permission is denied or denied forever
  /// - GPS fix times out (falls back to last known position)
  /// - Any other error occurs
  ///
  /// This method requests permission if it has not been granted yet,
  /// but returns `null` rather than throwing if permission is denied.
  Future<Position?> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } on TimeoutException {
      // GPS cold start can take too long indoors; fall back to cached position
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      // GPS should never block recording -- swallow all errors
      return null;
    }
  }
}
