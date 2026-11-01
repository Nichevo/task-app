import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'models.dart';

/// Gets the phone's location when a task is added or ticked off (if switched on in Settings).
/// Phones and tablets only: desktops have no GPS and would only guess from the network.
class LocationRecorder {
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Asks for "while using the app" location access if needed; true when allowed.
  Future<bool> requestAccess() async {
    if (!supported) return false;
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (e) {
      debugPrint('location permission: $e');
      return false;
    }
  }

  /// The current location, or null when it is off, not allowed or takes too long. Never asks
  /// for permission, so it can't pop up a prompt while adding a task.
  Future<GeoPoint?> current() async {
    if (!supported) return null;
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      // A fix from the last couple of minutes is good enough and instant.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 2) return _point(last);
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      return _point(pos);
    } catch (e) {
      debugPrint('location: $e');
      return null;
    }
  }

  static GeoPoint _point(Position p) =>
      GeoPoint(lat: p.latitude, lng: p.longitude, accuracy: p.accuracy, at: p.timestamp.toLocal());
}
