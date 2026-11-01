import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// A saved place for place-based reminders. Kept on this phone only (not synced): tasks carry
/// just the place's name.
class Place {
  Place({required this.id, required this.name, required this.lat, required this.lng, this.radius = 150});

  final String id;
  String name;
  final double lat;
  final double lng;

  /// Metres.
  int radius;

  factory Place.create(String name, double lat, double lng, {int radius = 150}) => Place(
      id: 'pl${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}',
      name: name.trim(),
      lat: lat,
      lng: lng,
      radius: radius);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'lat': lat, 'lng': lng, 'radius': radius};

  static Place? tryParse(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'];
    if (lat is! num || lng is! num || j['id'] is! String) return null;
    return Place(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      radius: (j['radius'] as num?)?.toInt() ?? 150,
    );
  }
}

/// Choices for a place's radius, in metres.
const placeRadiusOptions = [100, 150, 250, 500, 1000];

/// What place reminders still need from the phone.
class PlaceSetup {
  const PlaceSetup({required this.alwaysLocation, required this.batteryUnrestricted});

  /// Location "Allow all the time".
  final bool alwaysLocation;

  /// Battery "Unrestricted" (not optimised), so Samsung doesn't hold the alerts back.
  final bool batteryUnrestricted;

  bool get ready => alwaysLocation && batteryUnrestricted;
}

/// Android geofencing for place reminders. The phone watches the saved places itself (also when
/// the app is closed); on arriving or leaving, PlaceReceiver.kt reads the saved task list and
/// shows the matching reminders.
class PlaceReminders {
  static const _channel = MethodChannel('com.jeff.task_blocks/native');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Hands the places (and the folder holding tasks.json) to Android to watch. Returns false when
  /// Android refused, e.g. without "Allow all the time" location access.
  static Future<bool> watch(List<Place> places, {required bool arrivalSummary, required String? dir}) async {
    if (!supported || dir == null) return false;
    try {
      return await _channel.invokeMethod<bool>('setPlaces', {
            'places': jsonEncode([for (final p in places) p.toJson()]),
            'summary': arrivalSummary,
            'dir': dir,
          }) ??
          false;
    } catch (e) {
      debugPrint('setPlaces: $e');
      return false;
    }
  }

  static Future<PlaceSetup> setup() async {
    if (!supported) return const PlaceSetup(alwaysLocation: false, batteryUnrestricted: false);
    var always = false, battery = false;
    try {
      always = await Geolocator.checkPermission() == LocationPermission.always;
      battery = await _channel.invokeMethod<bool>('batteryUnrestricted') ?? false;
    } catch (e) {
      debugPrint('place setup: $e');
    }
    return PlaceSetup(alwaysLocation: always, batteryUnrestricted: battery);
  }

  /// Asks for location access, then "all the time". Android 11 and later can only grant that
  /// on its settings page, which this opens.
  static Future<void> askAlwaysLocation() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.whileInUse) p = await Geolocator.requestPermission();
    if (p != LocationPermission.always) await Geolocator.openAppSettings();
  }

  /// Opens Android's prompt to let the app run unrestricted in the background.
  static Future<void> askBatteryUnrestricted() async {
    try {
      await _channel.invokeMethod('askBatteryUnrestricted');
    } catch (e) {
      debugPrint('battery: $e');
    }
  }
}
