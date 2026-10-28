import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// A Done or Snooze press on a notification, waiting for the app to apply it.
class PendingAction {
  const PendingAction({required this.taskId, required this.action, required this.at, this.snoozeUntil});

  final String taskId;

  /// 'done' or 'snooze'.
  final String action;
  final DateTime at;
  final DateTime? snoozeUntil;

  Map<String, dynamic> toJson() => {
        'task': taskId,
        'action': action,
        'at': at.toIso8601String(),
        if (snoozeUntil != null) 'until': snoozeUntil!.toIso8601String(),
      };

  factory PendingAction.fromJson(Map<String, dynamic> j) => PendingAction(
        taskId: j['task'] as String,
        action: j['action'] as String,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        snoozeUntil: DateTime.tryParse(j['until'] as String? ?? ''),
      );
}

const _pendingFile = 'pending_actions.json';

/// Works out what a button press means and leaves a note for the app. Runs in the app, or
/// in a separate background isolate when the app isn't open, so it only touches a file.
Future<void> _recordAction(NotificationResponse r) async {
  final payload = r.payload;
  if (payload == null || payload.isEmpty) return;
  final j = jsonDecode(payload) as Map<String, dynamic>;
  final taskId = j['task'] as String?;
  final dir = j['dir'] as String?;
  if (taskId == null || dir == null) return;
  final now = DateTime.now();
  final action = switch (r.actionId) {
    'done' => PendingAction(taskId: taskId, action: 'done', at: now),
    'snooze1' => PendingAction(taskId: taskId, action: 'snooze', at: now, snoozeUntil: now.add(const Duration(hours: 1))),
    'snoozeEve' => PendingAction(
        taskId: taskId,
        action: 'snooze',
        at: now,
        snoozeUntil: now.hour < 18
            ? DateTime(now.year, now.month, now.day, 18)
            : DateTime(now.year, now.month, now.day + 1, 18)),
    'snoozeTmrw' =>
      PendingAction(taskId: taskId, action: 'snooze', at: now, snoozeUntil: DateTime(now.year, now.month, now.day + 1, 8)),
    _ => null,
  };
  if (action == null) return;
  final f = File('$dir/$_pendingFile');
  final list = await f.exists() ? jsonDecode(await f.readAsString()) as List : [];
  list.add(action.toJson());
  await f.writeAsString(jsonEncode(list), flush: true);
}

@pragma('vm:entry-point')
void notificationActionInBackground(NotificationResponse r) {
  _recordAction(r);
}

/// Phone notifications when a task falls due, and for overdue tasks. Android only: the
/// Windows app may not be running at the time, and a synced phone reminds you anyway.
class Reminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called when a button on a notification is pressed while the app is open.
  VoidCallback? onAction;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> init() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) async {
        await _recordAction(r);
        onAction?.call();
      },
      onDidReceiveBackgroundNotificationResponse: notificationActionInBackground,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  /// Button presses made since the app last looked; clears them.
  Future<List<PendingAction>> takeActions(String? dir) async {
    if (dir == null) return const [];
    final f = File('$dir/$_pendingFile');
    if (!await f.exists()) return const [];
    try {
      final list = jsonDecode(await f.readAsString()) as List;
      await f.delete();
      return [for (final j in list) PendingAction.fromJson(j as Map<String, dynamic>)];
    } catch (e) {
      debugPrint('Could not read notification actions: $e');
      return const [];
    }
  }

  /// Where the app keeps its files, passed along in each notification so a button press
  /// can be noted down even when the app isn't running.
  String? dir;

  /// Replaces all scheduled reminders: one at each open task's due time, an earlier one if
  /// asked for, and the overdue summary or nudges chosen in Settings.
  Future<void> schedule(AppData data) async {
    if (!_ready) return;
    final now = DateTime.now();
    try {
      await _plugin.cancelAllPendingNotifications();
      var budget = 200; // Android allows ~500 alarms per app; stay well inside it.
      for (final t in data.active) {
        final due = t.dueAt;
        if (due == null) continue;
        final before = t.remindBefore ?? data.defaultRemindBefore;
        final base = (t.id.hashCode & 0x0fffffff) * 8;
        if (await _at(base, due, 'Task due', t.title, now, t)) budget--;
        if (before > 0 &&
            await _at(base + 1, due.subtract(Duration(minutes: before)), 'Due ${_describe(before)}', t.title, now, t)) {
          budget--;
        }
        if (data.overdueMode == OverdueMode.nudge) {
          var when = due;
          for (var k = 2; k < 8 && budget > 0; k++) {
            when = _afterQuiet(when.add(Duration(hours: data.nudgeHours)), data);
            if (t.snoozedUntil != null && when.isBefore(t.snoozedUntil!)) continue;
            if (await _at(base + k, when, 'Still to do', t.title, now, t)) budget--;
          }
        }
        if (budget <= 0) break;
      }
      if (data.overdueMode == OverdueMode.daily) await _dailySummary(data, now);
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }

  /// One notification a day listing what is overdue at that moment.
  Future<void> _dailySummary(AppData data, DateTime now) async {
    var at = DateTime(now.year, now.month, now.day, data.overdueAt ~/ 60, data.overdueAt % 60);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    final overdue = data.active.where((t) => t.dueAt != null && t.dueAt!.isBefore(at) && !t.isSnoozed(at)).toList();
    if (overdue.isEmpty) return;
    final names = overdue.take(4).map((t) => t.title).join(', ');
    await _plugin.zonedSchedule(
      id: 1,
      title: '${overdue.length} task${overdue.length == 1 ? '' : 's'} overdue',
      body: overdue.length > 4 ? '$names…' : names,
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'overdue',
          'Overdue tasks',
          channelDescription: 'A daily summary of overdue tasks',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// Pushes a time inside the quiet hours to when they end.
  static DateTime _afterQuiet(DateTime t, AppData data) {
    final m = t.hour * 60 + t.minute;
    final s = data.quietStart, e = data.quietEnd;
    if (s == e) return t;
    final overnight = s > e;
    final quiet = overnight ? (m >= s || m < e) : (m >= s && m < e);
    if (!quiet) return t;
    final day = overnight && m >= s ? t.day + 1 : t.day;
    return DateTime(t.year, t.month, day, e ~/ 60, e % 60);
  }

  static String _describe(int minutes) => minutes < 60
      ? 'in $minutes min'
      : minutes < 1440
      ? 'in ${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''}'
      : minutes < 10080
      ? 'in ${minutes ~/ 1440} day${minutes >= 2880 ? 's' : ''}'
      : 'in a week';

  Future<bool> _at(int id, DateTime when, String title, String body, DateTime now, Task t) async {
    if (!when.isAfter(now)) return false;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      payload: jsonEncode({'task': t.id, 'dir': dir}),
      // A UTC time is the same moment wherever the phone is.
      scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'due',
          'Due tasks',
          channelDescription: 'Reminders when a task is due',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction('done', 'Done'),
            AndroidNotificationAction('snooze1', '1 hour'),
            AndroidNotificationAction('snoozeEve', 'This evening'),
            AndroidNotificationAction('snoozeTmrw', 'Tomorrow'),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return true;
  }
}
