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
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  /// Replaces all scheduled reminders with one per open task due in the future.
  Future<void> schedule(List<Task> active) async {
    if (!_ready) return;
    final now = DateTime.now();
    try {
      await _plugin.cancelAllPendingNotifications();
      for (final t in active) {
        final due = t.dueAt;
        if (due == null || !due.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          id: t.id.hashCode & 0x7fffffff,
          title: 'Task due',
          body: t.title,
          // A UTC time is the same moment wherever the phone is.
          scheduledDate: tz.TZDateTime.from(due.toUtc(), tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('due', 'Due tasks',
                channelDescription: 'Reminders when a task is due',
                importance: Importance.high,
                priority: Priority.high),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }
}
