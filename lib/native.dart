import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Text handed to the app by another app (Android's Share sheet, or "note to self").
class SharedText {
  const SharedText(this.text, {this.subject, this.voice = false});
  final String text;
  final String? subject;

  /// Spoken to Google Assistant ("note to self") rather than shared from an app.
  final bool voice;
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
    DateTime? end,
  }) : end = end ?? start;

  final String id;
  final String calendarId;
  final String title;
  final DateTime start;

  /// Item 101: when it ends (the same as [start] from older native code).
  final DateTime end;
  final bool allDay;
  final String? location;
}

/// Item 110: a photo of a screen as read by [Native.readScreen].
class ScreenPhoto {
  const ScreenPhoto({required this.path, required this.width, required this.height, required this.words});
  final String path;
  final int width, height;
  final List<({String text, double l, double t, double r, double b})> words;
}

/// The small amount of native plumbing: shared text, the phone's calendars and on-device text
/// recognition. Android has it in MainActivity.kt, the iPad in ios/Runner/AppDelegate.swift.
class Native {
  static const _channel = MethodChannel('app.taskblocks/native');

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Item 102: whether the app may turn Do not disturb on and off (Android only).
  static bool get dndSupported => !kIsWeb && Platform.isAndroid;

  static Future<bool> dndAllowed() async {
    if (!dndSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('dndAllowed') ?? false;
    } catch (e) {
      debugPrint('dndAllowed: $e');
      return false;
    }
  }

  /// Opens Android's page for allowing Do not disturb access.
  static Future<void> askDnd() async {
    if (!dndSupported) return;
    try {
      await _channel.invokeMethod('askDnd');
    } catch (e) {
      debugPrint('askDnd: $e');
    }
  }

  /// Turns Do not disturb (priority only) on or off; false when not allowed.
  static Future<bool> setDoNotDisturb(bool on) async {
    if (!dndSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('setDnd', {'on': on}) ?? false;
    } catch (e) {
      debugPrint('setDnd: $e');
      return false;
    }
  }

  /// Text shared to the app since it last asked, if any. On iPad it comes from the "Add to Task
  /// Blocks" action (Siri, Shortcuts or a Share sheet shortcut), see AppDelegate.swift.
  static Future<SharedText?> takeShared() async {
    if (!supported) return null;
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('takeShared');
      final text = m?['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return SharedText(text, subject: m?['subject'] as String?, voice: m?['voice'] == true);
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
          end: e['end'] is num ? DateTime.fromMillisecondsSinceEpoch((e['end'] as num).toInt()) : null,
        ),
    ];
  }

  /// Item 110: the words in a photo of a screen and where each one is, read on the phone, with
  /// the photo turned upright and saved again ([ScreenPhoto.path]) so its colours line up.
  static Future<ScreenPhoto> readScreen(String imagePath) async {
    final m = await _channel.invokeMapMethod<String, dynamic>('readScreen', {'path': imagePath});
    if (m == null) throw Exception('The photo could not be read');
    double n(Object? v) => (v as num).toDouble();
    return ScreenPhoto(
      path: m['path'] as String,
      width: (m['width'] as num).toInt(),
      height: (m['height'] as num).toInt(),
      words: [
        for (final w in m['words'] as List? ?? const [])
          if (w is Map) (text: '${w['t']}', l: n(w['l']), t: n(w['top']), r: n(w['r']), b: n(w['b'])),
      ],
    );
  }

  /// Lines of text found in a photo, read on the phone.
  static Future<List<String>> recognizeText(String imagePath) async {
    if (!supported) return const [];
    final list = await _channel.invokeListMethod<String>('recognizeText', {'path': imagePath});
    return list ?? const [];
  }
}
