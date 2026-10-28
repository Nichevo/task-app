import 'package:flutter/material.dart';

import '../models.dart';

/// Green when new, through yellow and orange, to red after [hoursToRed].
/// With [byDue], a task that has a due date is red by its due date instead.
Color ageColor(Task t, double hoursToRed, {bool byDue = false, DateTime? now}) {
  now ??= DateTime.now();
  final start = t.colourStart(now);
  final age = now.difference(start).inMinutes / 60;
  final due = t.dueAt;
  final span = byDue && due != null ? due.difference(start).inMinutes / 60 : hoursToRed;
  final progress = span <= 0 ? 1.0 : (age / span).clamp(0.0, 1.0);
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

/// Colour for a task waiting on another one.
const lockedColor = Color(0xFFD5D5D5);
