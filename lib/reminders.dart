import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'habits.dart';
import 'models.dart';
import 'stats.dart';

/// A Done or Snooze press on a notification, waiting for the app to apply it.
class PendingAction {
  const PendingAction({required this.taskId, required this.action, required this.at, this.snoozeUntil});

  final String taskId;

  /// 'done', 'skip' or 'snooze'.
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
    'skip' => PendingAction(taskId: taskId, action: 'skip', at: now),
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

/// Phone and iPad notifications when a task falls due, and for overdue tasks. Not on
/// desktops: the app may not be running at the time, and a synced phone reminds you anyway.
class Reminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called when a button on a notification is pressed while the app is open.
  VoidCallback? onAction;

  /// Called when the weekly review notification is tapped while the app is running.
  VoidCallback? onOpenReview;

  /// The app was started by tapping the weekly review notification.
  bool startedFromReview = false;

  static bool _isReview(String? payload) {
    if (payload == null || payload.isEmpty) return false;
    try {
      return (jsonDecode(payload) as Map)['review'] == true;
    } catch (_) {
      return false;
    }
  }

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// The Done / snooze buttons on an iPhone or iPad notification (long-press to see them).
  static final _darwin = DarwinInitializationSettings(notificationCategories: [
    DarwinNotificationCategory('due', actions: [
      DarwinNotificationAction.plain('done', 'Done'),
      DarwinNotificationAction.plain('snooze1', '1 hour'),
      DarwinNotificationAction.plain('snoozeEve', 'This evening'),
      DarwinNotificationAction.plain('snoozeTmrw', 'Tomorrow'),
    ]),
    // Repeating tasks: Skip moves it to the next date without ticking it off.
    DarwinNotificationCategory('dueRepeat', actions: [
      DarwinNotificationAction.plain('done', 'Done'),
      DarwinNotificationAction.plain('skip', 'Skip'),
      DarwinNotificationAction.plain('snooze1', '1 hour'),
      DarwinNotificationAction.plain('snoozeTmrw', 'Tomorrow'),
    ]),
  ]);

  Future<void> init() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: InitializationSettings(android: const AndroidInitializationSettings('@drawable/ic_notification'), iOS: _darwin),
      onDidReceiveNotificationResponse: (r) async {
        if (r.actionId == null && _isReview(r.payload)) {
          onOpenReview?.call();
          return;
        }
        await _recordAction(r);
        onAction?.call();
      },
      onDidReceiveBackgroundNotificationResponse: notificationActionInBackground,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    startedFromReview =
        (launch?.didNotificationLaunchApp ?? false) && _isReview(launch?.notificationResponse?.payload);
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

  String? _lastKey;

  /// Everything the scheduled reminders depend on: the settings, each open task's name, dates
  /// and reminder, how much is done (for the weekly review) and today's date.
  static String scheduleKey(AppData data, DateTime now) {
    final j = data.toJson()
      ..removeWhere((k, _) => const {
            'active', 'archived', 'done', 'deleted', 'skips', 'updatedAt', 'orderUpdatedAt', 'hiddenEmails',
          }.contains(k));
    return jsonEncode([
      '${now.year}-${now.month}-${now.day}',
      j,
      data.done.length,
      data.archived.length,
      for (final t in data.active)
        if (t.dueAt != null)
          [t.id, t.title, t.dueAt!.toIso8601String(), t.remindBefore, t.snoozedUntil?.toIso8601String()],
      for (final t in data.active)
        for (final st in t.steps)
          if (st.dueAt != null) [st.id, st.title, st.done, st.dueAt!.toIso8601String(), st.remindBefore, t.title],
      // Item 78: a habit's reminder moves on once today is ticked.
      for (final t in data.habits)
        if (nextHabitReminder(t, now) case final at?) [t.id, t.title, at.toIso8601String()],
    ]);
  }

  /// Replaces all scheduled reminders: one at each open task's due time, an earlier one if
  /// asked for, and the overdue summary or nudges chosen in Settings.
  Future<void> schedule(AppData data) async {
    if (!_ready) return;
    final now = DateTime.now();
    // Rescheduling means up to a few hundred calls into the system, so skip it when nothing a
    // reminder depends on has changed (at least once a day, for the daily and weekly ones).
    final key = scheduleKey(data, now);
    if (key == _lastKey) return;
    _lastKey = key;
    try {
      await _plugin.cancelAllPendingNotifications();
      // Android allows ~500 alarms per app; stay well inside it. iOS keeps the soonest 64.
      var budget = 200;
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
      // Item 61: steps with their own date, reminded with the task's name.
      for (final t in data.active) {
        for (final st in t.steps) {
          final due = st.dueAt;
          if (due == null || st.done || budget <= 0) continue;
          final before = st.remindBefore ?? data.defaultRemindBefore;
          // Negative ids, so they never meet a task's (0 and up).
          final base = -2 - (st.id.hashCode & 0x0fffffff) * 2;
          final body = '${st.title}\nPart of: ${t.title}';
          if (await _at(base, due, 'Step due', body, now, t, step: true)) budget--;
          if (before > 0 &&
              await _at(base + 1, due.subtract(Duration(minutes: before)), 'Step due ${_describe(before)}', body, now, t,
                  step: true)) {
            budget--;
          }
        }
      }
      // Item 78: each habit's next reminder, only on a day it isn't ticked yet.
      for (final t in data.habits) {
        final at = nextHabitReminder(t, now);
        if (at == null || budget <= 0) continue;
        if (await _at((t.id.hashCode & 0x0fffffff) * 8 + 7, at, 'Habit', t.title, now, t, step: true)) budget--;
      }
      if (data.overdueMode == OverdueMode.daily) await _dailySummary(data, now);
      if (data.weeklyReview) await _weeklyReview(data, now);
    } catch (e) {
      _lastKey = null; // Try again on the next change.
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
        iOS: DarwinNotificationDetails(),
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

  /// Next time the weekly review is due: the chosen weekday and time, after [now].
  static DateTime nextReview(AppData data, DateTime now) {
    var at = DateTime(now.year, now.month, now.day, data.weeklyAt ~/ 60, data.weeklyAt % 60);
    at = DateTime(at.year, at.month, at.day + (data.weeklyDay - at.weekday) % 7, at.hour, at.minute);
    if (!at.isAfter(now)) at = DateTime(at.year, at.month, at.day + 7, at.hour, at.minute);
    return at;
  }

  /// The words of the weekly review, worked out from the tasks as they are when scheduling
  /// (it is re-scheduled whenever anything changes, so it is up to date as of the last use).
  static (String, String) reviewText(AppData data, DateTime at) {
    final r = Stats(data, at).weekReview(at);
    String n(int c, String one) => '$c $one${c == 1 ? '' : 's'}';
    return (
      'Weekly review: ${r.done} done, ${r.added} added',
      [
        'Last 7 days: ${n(r.added, 'task')} added, ${r.done} ticked off.',
        if (r.overdue > 0) '${n(r.overdue, 'task')} overdue.',
        r.dueNext == 0 ? 'Nothing due in the coming week.' : '${n(r.dueNext, 'task')} due in the coming week.',
      ].join(' '),
    );
  }

  /// One notification a week (day and time from Settings) with last week's numbers.
  Future<void> _weeklyReview(AppData data, DateTime now) async {
    final at = nextReview(data, now);
    final (title, body) = reviewText(data, at);
    await _plugin.zonedSchedule(
      id: 2,
      title: title,
      body: body,
      payload: jsonEncode({'review': true}),
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: NotificationDetails(
        iOS: const DarwinNotificationDetails(),
        android: AndroidNotificationDetails(
          'review',
          'Weekly review',
          channelDescription: 'Last week\'s numbers and what is coming up',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
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

  static const _due = NotificationDetails(
    iOS: DarwinNotificationDetails(categoryIdentifier: 'due'),
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
  );

  /// Android shows at most three buttons, so a repeating task trades "This evening" and
  /// "Tomorrow" for Skip.
  static const _dueRepeat = NotificationDetails(
    iOS: DarwinNotificationDetails(categoryIdentifier: 'dueRepeat'),
    android: AndroidNotificationDetails(
      'due',
      'Due tasks',
      channelDescription: 'Reminders when a task is due',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('done', 'Done'),
        AndroidNotificationAction('skip', 'Skip'),
        AndroidNotificationAction('snooze1', '1 hour'),
      ],
    ),
  );

  /// A step's reminder: opens its task, with no Done or Snooze buttons (those act on a task).
  static const _stepDue = NotificationDetails(
    iOS: DarwinNotificationDetails(),
    android: AndroidNotificationDetails(
      'due',
      'Due tasks',
      channelDescription: 'Reminders when a task is due',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  Future<bool> _at(int id, DateTime when, String title, String body, DateTime now, Task t, {bool step = false}) async {
    if (!when.isAfter(now)) return false;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      payload: jsonEncode({'task': t.id, 'dir': dir}),
      // A UTC time is the same moment wherever the phone is.
      scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
      notificationDetails: step ? _stepDue : t.repeat == null ? _due : _dueRepeat,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return true;
  }
}
