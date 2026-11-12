import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'gantt.dart';
import 'habits.dart';
import 'models.dart';
import 'stats.dart';

typedef WidgetMove = ({String task, String? step, String stage, DateTime at});

/// Shares the task list with the home screen widgets (Android, and iPad/iPhone from item 79),
/// and picks up what was done on them (ticks, step ticks, snoozes). Does nothing on other platforms.
class HomeWidgets {
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Item 79: the iPad widget kinds (WidgetKit `kind` strings in ios/TaskBlocksWidget).
  static const _iosKinds = [
    'TaskList', 'Summary', 'Focus', 'Checklist', 'Month', 'Board', 'Matrix', 'Worked', 'Chart', 'QuickAdd',
    'Calendar', 'Glance', // Item 90.
  ];

  static const _channel = MethodChannel('app.taskblocks/widgets');

  /// On iOS the widgets read from a shared app group whose name can change when the app is
  /// sideloaded (AltStore adds the team id), so the native side looks it up. False when the
  /// build has no shared group, in which case nothing is sent.
  Future<bool>? _ready;

  Future<bool> _setUp() async {
    if (!Platform.isIOS) return true;
    try {
      final group = await _channel.invokeMethod<String>('appGroup');
      if (group == null) return false;
      await HomeWidget.setAppGroupId(group);
      return true;
    } catch (e) {
      debugPrint('No widget app group: $e');
      return false;
    }
  }

  Future<bool> get _ok => _ready ??= _setUp();

  static const _providers = [
    'app.taskblocks.TaskListWidget',
    'app.taskblocks.CompactWidget',
    'app.taskblocks.TodayWidget',
    'app.taskblocks.FocusWidget',
    'app.taskblocks.ChecklistWidget',
    'app.taskblocks.StatsWidget',
    'app.taskblocks.MonthWidget',
    'app.taskblocks.CalendarWidget', // Item 83.
    'app.taskblocks.QuickAddWidget',
    // Item 68: board and matrix widgets.
    'app.taskblocks.BoardSummaryWidget',
    'app.taskblocks.StageListWidget',
    'app.taskblocks.NowDoingWidget',
    'app.taskblocks.BoardStepsWidget',
    'app.taskblocks.MatrixWidget',
    // Items 75 and 77.
    'app.taskblocks.WorkedTodayWidget',
    'app.taskblocks.AddedDoneWidget',
    'app.taskblocks.BurnDownWidget',
  ];

  /// Writes what the widgets show and asks them to redraw.
  String? _lastJson;

  Future<void> push(AppData data) async {
    if (!supported || !await _ok) return;
    final json = widgetJson(data, DateTime.now());
    // Each update redraws every widget, so skip it when nothing they show has changed.
    if (json == _lastJson) return;
    try {
      await HomeWidget.saveWidgetData<String>('widget_data', json);
      _lastJson = json;
      if (Platform.isIOS) {
        for (final k in _iosKinds) {
          await HomeWidget.updateWidget(iOSName: k);
        }
      } else {
        for (final p in _providers) {
          await HomeWidget.updateWidget(qualifiedAndroidName: p);
        }
      }
    } catch (e) {
      debugPrint('Could not update widgets: $e');
    }
  }

  /// What the widgets are given (read by WidgetData.kt). Snoozed tasks are marked `snoozed` with
  /// `snoozedUntil`: list widgets hide them until then, board widgets count them like the board does.
  static String widgetJson(AppData data, DateTime now) {
    final stats = Stats(data, now);
    final fortnight = dayKey(now.subtract(const Duration(days: 14)));
    return jsonEncode({
      'today': dayKey(now),
      'hoursToRed': data.hoursToRed,
      'colourByDue': data.colourByDue,
      'categories': [for (final c in data.categories) {'id': c.id, 'name': c.name}],
      'stages': [
        for (final s in data.stages)
          {'id': s.id, 'name': s.name, if (s.colour != null) 'colour': s.colour, if (s.limit != null) 'limit': s.limit},
      ],
      'boxes': {for (final b in MatrixBox.values) b.id: data.boxName(b)},
      'tasks': [
        for (final t in [...data.active.where((t) => t.starred), ...data.active.where((t) => !t.starred)])
          // M4: snoozed tasks are sent too, with when the snooze ends, so the widgets show them
          // again then without waiting for the app to be opened.
          if (!t.habit)
            {
              'id': t.id,
              'title': t.title,
              'cat': data.category(t.categoryId)?.id,
              'start': t.colourStart(now).millisecondsSinceEpoch,
              'due': t.dueAt?.millisecondsSinceEpoch,
              'locked': data.isLocked(t),
              'star': t.starred,
              if (t.isSnoozed(now)) 'snoozed': true,
              if (t.isSnoozed(now)) 'snoozedUntil': t.snoozedUntil!.millisecondsSinceEpoch,
              if (t.kanban) 'stage': (data.stage(t.stageId) ?? data.stages.firstOrNull)?.id,
              if (t.stageSince != null) 'since': t.stageSince!.millisecondsSinceEpoch,
              if (t.matrixBox != null) 'box': t.matrixBox,
              // Item 75: days worked in the last fortnight, for the Worked today widget.
              if (t.worked.isNotEmpty) 'worked': [for (final k in t.worked) if (k.compareTo(fortnight) >= 0) k],
              if (t.steps.isNotEmpty)
                'steps': [
                  for (final s in t.steps)
                    {
                      'id': s.id,
                      'title': s.title,
                      'done': s.done,
                      if (t.boardSteps.contains(s) && s.placed)
                        'stage': (data.stage(s.stageId) ?? data.stages.firstOrNull)?.id,
                      if (t.boardSteps.contains(s) && s.stageSince != null)
                        'since': s.stageSince!.millisecondsSinceEpoch,
                    },
                ],
            },
      ],
      // Item 78: habits, for the Worked today widget's Habits choice.
      'habits': [
        for (final t in data.habits)
          if (!t.habitPaused)
            {
              'id': t.id,
              'title': t.title,
              'due': dueToday(t, now),
              'worked': [for (final k in t.worked) if (k.compareTo(fortnight) >= 0) k],
              'streak': streak(t, now),
              'unit': t.habitGoal == HabitGoal.perWeek ? 'week' : 'day',
            },
      ],
      // Days (yyyy-MM-dd) with tasks due, for the mini month widget; repeats faded.
      'dueDays': stats.dueDays(now, const Duration(days: 62)),
      'stats': {'week': stats.doneThisWeek, 'streak': stats.streak},
      // Item 77: the Added vs done chart (last 4 weeks, by day) for everything and each category.
      'addedDone': {
        for (final id in [null, ...data.categories.map((c) => c.id)])
          id ?? '': _addedDone(stats.addedVsDone(Stats.dayOf(now).subtract(const Duration(days: 27)), categoryId: id)),
      },
      // Item 77: burn-downs of the Gantt chart, for everything and each category with chart tasks.
      'burn': {
        for (final id in [null, ...data.categories.map((c) => c.id)])
          if (burnDown(burnTasks(data, id), data, now) case final b?) id ?? '': _burn(b),
      },
    });
  }

  static Map<String, Object?> _addedDone(List<Bucket> b) => {
        'from': b.isEmpty ? null : dayKey(b.first.start),
        'added': [for (final x in b) x.added],
        'done': [for (final x in b) x.done],
        'open': [for (final x in b) x.open],
      };

  static Map<String, Object?> _burn(BurnDown b) => {
        'from': dayKey(b.start),
        'end': dayKey(b.end),
        'total': b.total,
        'left': [for (final v in b.left) double.parse(v.toStringAsFixed(2))],
        if (b.projected != null) 'projected': dayKey(b.projected!),
        'summary': burnSummary(b),
      };

  Future<List<dynamic>> _take(String key) async {
    if (!supported || !await _ok) return const [];
    try {
      final raw = await HomeWidget.getWidgetData<String>(key);
      if (raw == null || raw.isEmpty || raw == '[]') return const [];
      final taken = jsonDecode(raw) as List;
      // L4: a widget may have added more since; clear only what was read.
      final now = await HomeWidget.getWidgetData<String>(key);
      final all = now == null || now.isEmpty ? const [] : jsonDecode(now) as List;
      await HomeWidget.saveWidgetData<String>(key, jsonEncode(all.length > taken.length ? all.sublist(taken.length) : const []));
      return taken;
    } catch (e) {
      debugPrint('Could not read $key: $e');
      return const [];
    }
  }

  static DateTime _ms(Object? v) => DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

  /// Tasks ticked off on a widget since the app last looked: (task id, when).
  Future<List<(String, DateTime)>> takeCompleted() async =>
      [for (final e in await _take('widget_done')) (e['id'] as String, _ms(e['at']))];

  /// Checklist steps ticked on a widget: (task id, step id).
  Future<List<(String, String)>> takeStepTicks() async =>
      [for (final e in await _take('widget_steps')) (e['task'] as String, e['step'] as String)];

  /// Tasks snoozed on a widget: (task id, until).
  Future<List<(String, DateTime)>> takeSnoozes() async =>
      [for (final e in await _take('widget_snoozed')) (e['id'] as String, _ms(e['until']))];

  /// Board moves made on a widget: (task id, step id or null, stage id, when).
  Future<List<WidgetMove>> takeMoves() async => [
        for (final e in await _take('widget_moves'))
          (task: e['task'] as String, step: e['step'] as String?, stage: e['stage'] as String, at: _ms(e['at'])),
      ];

  /// Item 75: days ticked or unticked as worked on the Worked today widget: (task id, day, on).
  Future<List<(String, DateTime, bool)>> takeWorked() async => [
        for (final e in await _take('widget_worked'))
          if (DateTime.tryParse(e['day'] as String? ?? '') case final d?) (e['id'] as String, d, e['on'] as bool? ?? true),
      ];

  /// Item 48B: tasks sent by other Android apps (Tasker and the like) while the app was closed,
  /// in the inbox file format (docs/PUSH_TASKS.md).
  Future<List<dynamic>> takePushed() => _take('pushed_tasks');

  /// Links opened from a widget: taskblocks://add, taskblocks://open?id=…, taskblocks://day?d=…
  Stream<Uri?> get clicks => supported ? HomeWidget.widgetClicked : const Stream.empty();

  Future<Uri?> launchUri() async => supported ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;
}
