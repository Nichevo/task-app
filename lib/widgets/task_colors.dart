import 'package:flutter/material.dart';

import '../models.dart';

/// Green when new, through yellow and orange, to red after [hoursToRed].
Color ageColor(Task t, double hoursToRed, [DateTime? now]) {
  final age = (now ?? DateTime.now()).difference(t.createdAt).inMinutes / 60;
  final progress = (age / hoursToRed).clamp(0.0, 1.0);
  return HSVColor.fromAHSV(1, 120 * (1 - progress), 0.6, 0.88).toColor();
}

/// Labels for the colour-speed slider, in hours.
const speedSteps = <double>[1, 6, 12, 24, 48, 72, 120, 168, 240, 336, 504, 720, 1080, 1440, 2160];

String describeHours(double h) {
  if (h < 24) return '${h.round()} hour${h == 1 ? '' : 's'}';
  final days = h / 24;
  if (days % 7 == 0 && days >= 7 && days < 30) {
    final w = days ~/ 7;
    return '$w week${w == 1 ? '' : 's'}';
  }
  return '${days.round()} day${days == 1 ? '' : 's'}';
}
