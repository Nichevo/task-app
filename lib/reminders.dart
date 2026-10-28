import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// Phone notifications when a task falls due. Android only: the Windows app may not be
/// running at the time, and a synced phone reminds you anyway.
class Reminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  /// Replaces all scheduled reminders: one at each open task's due time, plus an earlier one
  /// if the task (or the default in Settings) asks for it.
  Future<void> schedule(AppData data) async {
    if (!_ready) return;
    final now = DateTime.now();
    try {
      await _plugin.cancelAllPendingNotifications();
      for (final t in data.active) {
        final due = t.dueAt;
        if (due == null) continue;
        final before = t.remindBefore ?? data.defaultRemindBefore;
        final base = (t.id.hashCode & 0x3fffffff) * 2;
        await _at(base, due, 'Task due', t.title, now);
        if (before > 0) {
          await _at(
            base + 1,
            due.subtract(Duration(minutes: before)),
            'Due ${_describe(before)}',
            t.title,
            now,
          );
        }
      }
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }

  static String _describe(int minutes) => minutes < 60
      ? 'in $minutes min'
      : minutes < 1440
      ? 'in ${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''}'
      : minutes < 10080
      ? 'in ${minutes ~/ 1440} day${minutes >= 2880 ? 's' : ''}'
      : 'in a week';

  Future<void> _at(int id, DateTime when, String title, String body, DateTime now) async {
    if (!when.isAfter(now)) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      // A UTC time is the same moment wherever the phone is.
      scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'due',
          'Due tasks',
          channelDescription: 'Reminders when a task is due',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
