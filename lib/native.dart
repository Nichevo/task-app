import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Text handed to the app by another app (Android's Share sheet, or "note to self").
class SharedText {
  const SharedText(this.text, {this.subject});
  final String text;
  final String? subject;
}

/// A calendar on the phone.
class DeviceCalendar {
  const DeviceCalendar({required this.id, required this.name, required this.account});
  final String id;
  final String name;
  final String account;
}

/// An upcoming event from a phone calendar.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.allDay,
    this.location,
  });

  final String id;
  final String calendarId;
  final String title;
  final DateTime start;
  final bool allDay;
  final String? location;
}

/// The small amount of Android-only plumbing written in Kotlin (see MainActivity.kt):
/// shared text, the phone's calendars and on-device text recognition.
class Native {
  static const _channel = MethodChannel('com.jeff.task_blocks/native');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Text shared to the app since it last asked, if any.
  static Future<SharedText?> takeShared() async {
    if (!supported) return null;
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('takeShared');
      final text = m?['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return SharedText(text, subject: m?['subject'] as String?);
    } catch (e) {
      debugPrint('takeShared: $e');
      return null;
    }
  }

  /// Asks for calendar access; true when granted.
  static Future<bool> requestCalendarAccess() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('calendarPermission') ?? false;
    } catch (e) {
      debugPrint('calendarPermission: $e');
      return false;
    }
  }

  static Future<List<DeviceCalendar>> calendars() async {
    if (!supported) return const [];
    final list = await _channel.invokeListMethod<Map>('calendars') ?? const [];
    return [
      for (final c in list)
        DeviceCalendar(id: '${c['id']}', name: c['name'] as String? ?? '', account: c['account'] as String? ?? ''),
    ];
  }

  /// Events starting between [from] and [to] in the given calendars (all when empty).
  static Future<List<CalendarEvent>> events(DateTime from, DateTime to, Set<String> calendarIds) async {
    if (!supported) return const [];
    final list = await _channel.invokeListMethod<Map>('events', {
          'from': from.millisecondsSinceEpoch,
          'to': to.millisecondsSinceEpoch,
          'calendars': calendarIds.toList(),
        }) ??
        const [];
    return [
      for (final e in list)
        CalendarEvent(
          id: '${e['id']}',
          calendarId: '${e['calendarId']}',
          title: e['title'] as String? ?? '(No title)',
          start: DateTime.fromMillisecondsSinceEpoch((e['start'] as num).toInt()),
          allDay: e['allDay'] as bool? ?? false,
          location: e['location'] as String?,
        ),
    ];
  }

  /// Lines of text found in a photo, read on the phone.
  static Future<List<String>> recognizeText(String imagePath) async {
    if (!supported) return const [];
    final list = await _channel.invokeListMethod<String>('recognizeText', {'path': imagePath});
    return list ?? const [];
  }
}
