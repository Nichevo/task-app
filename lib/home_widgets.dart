import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'day_plan.dart' show layoutDay;
import 'focus_timer.dart';
import 'gantt.dart';
import 'habits.dart';
import 'auto_plan.dart' show whatNow;
import 'day_plan.dart' show describeLength;
import 'models.dart';
import 'widgets/task_colors.dart' show ageColor;
import 'modes.dart';
import 'stats.dart';
import 'week_widgets.dart' show weekWidgetData;

typedef WidgetMove = ({String task, String? step, String stage, DateTime at});

/// Shares the task list with the home screen widgets (Android, and iPad/iPhone from item 79),
/// and picks up what was done on them (ticks, step ticks, snoozes). Does nothing on other platforms.
class HomeWidgets {
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Item 79: the iPad widget kinds (WidgetKit `kind` strings in ios/TaskBlocksWidget).
  static const _iosKinds = [
    'TaskList', 'Summary', 'Focus', 'Checklist', 'Month', 'Board', 'Matrix', 'Worked', 'Chart', 'QuickAdd',
    'Calendar', 'Glance', // Item 90.
    'DayPlan', // Item 101.
    'Mode', // Item 102.
    'FocusTimer', // Item 102, part 4.
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
    'app.taskblocks.DayPlanWidget', // Item 101.
    'app.taskblocks.ModeWidget', // Item 102.
    'app.taskblocks.FocusTimerWidget', // Item 102, part 4.
    'app.taskblocks.DoNowWidget', // Item 114 C.
    'app.taskblocks.WeekMonthWidget', // Item 115.
    'app.taskblocks.BusyMonthWidget', // Item 115.
    'app.taskblocks.WeekBoardWidget', // Item 115.
    'app.taskblocks.BusyBoardWidget', // Item 115.
    'app.taskblocks.WeekLoadWidget', // Item 115.
    'app.taskblocks.WeekDayWidget', // Item 115.
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
  /// Item 114 C: what the Do now widget shows.
  static Map<String, dynamic> doNowData(AppData data, DateTime now) {
    final a = whatNow(data, now);
    return {
      'head': a.freeMinutes == null ? 'Do now' : 'Do now · ${describeLength(a.freeMinutes!)} free',
      'picks': [
        for (final p in a.picks)
          {
            'id': p.task.id,
            if (p.step != null) 'step': p.step!.id,
            'title': p.task.title,
            'meta': [
              if (p.step != null) p.step!.title,
              describeLength(p.minutes),
              ...p.why.take(2),
            ].join(' · '),
            'color': ageColor(p.task, data.hoursToRed, byDue: data.colourByDue, now: now).toARGB32(),
          },
      ],
    };
  }

  static String widgetJson(AppData data, DateTime now) {
    final stats = Stats(data, now);
    final fortnight = dayKey(now.subtract(const Duration(days: 14)));
    final modes = modeWidgetData(data, now);
    return jsonEncode({
      ...?modes,
      // Item 102, part 4: the focus timer, for the Focus timer widget.
      'focusTimer': ?focusTimerData(data, now),
      'focusLengths': [
        data.focusSettings.focus,
        data.focusSettings.shortBreak,
        data.focusSettings.longBreak,
        data.focusSettings.every,
      ],
      // Item 108: the Focus timer widget's buttons work without the app, Do not disturb too.
      if (data.focusSettings.dnd) 'focusDnd': true,
      // Item 114 C: the Do now widget's picks, worked out when anything changes.
      if (data.helperOn(Helper.whatNow)) 'doNow': doNowData(data, now),
      // Item 115: the week and month widgets with two clocks.
      'week': weekWidgetData(data, now),
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
              if (focusOn(t, now) case final m when m > 0) 'focusToday': m,
              if (modes != null)
                if (modesHiding(data, t, now) case final h when h.isNotEmpty) 'hide': h,
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
      // Item 101: the Today's plan widget: planned times for the coming week (it shows today's,
      // so it keeps up when the day changes before the app is opened).
      'plan': dayPlanRows(data, now),
      // Free time in working hours on those days (the widgets take out calendar events).
      'planFree': dayPlanFree(data, now),
      // Item 111: work meetings from a photo of Outlook, for Today's plan (not those a task stands for).
      'work': [
        for (final e in data.workEvents(DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day + 7)))
          if (!e.allDay && data.linkedToMeeting(e.id) == null)
            {'id': e.id, 'title': e.title, 'at': e.start.millisecondsSinceEpoch, 'end': e.end.millisecondsSinceEpoch},
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
        // Item 86: each open task's own burn-down, as "task:<id>", for widgets set to one task.
        for (final t in data.active)
          if (taskBurnDown(t, data, now) case final b?) 'task:${t.id}': _burn(b),
      },
    });
  }

  /// Item 102, part 4: the running focus timer: its task and steps, the phase and when it ends
  /// (or the time left while paused). The widgets move it on through the break themselves.
  static Map<String, Object?>? focusTimerData(AppData data, DateTime now) {
    final f = focusNow;
    final t = f == null ? null : data.task(f.taskId);
    if (f == null || t == null) return null;
    return {
      'task': t.id,
      'title': t.title,
      if (f.stepId != null) 'step': f.stepId,
      'steps': [
        for (final s in t.steps) {'id': s.id, 'title': s.title, if (s.done) 'done': true},
      ],
      'phase': f.phase.name,
      'round': f.round,
      'length': f.length.inSeconds,
      if (f.end != null) 'end': f.end!.millisecondsSinceEpoch,
      if (f.end == null) 'left': f.remaining(now).inSeconds,
      if (f.heldBreak) 'ready': true,
      'today': focusOn(t, now),
    };
  }

  /// Item 102: what the widgets need to follow the focus modes: each mode's name, colour and
  /// what breaks through, and a timeline of the mode in force for the next 8 days (the current
  /// mode until it ends, then the weekly schedule). Null when there are no modes. Everything is
  /// listed as a mode ('all') that hides nothing. Item 108: sent even when the widgets are set
  /// not to follow the mode ('modeWidgets' false), for the Focus mode widget and for widgets set
  /// to one mode of their own; each mode carries its own focus timer lengths, if it has them.
  static Map<String, Object?>? modeWidgetData(AppData data, DateTime now) {
    if (data.modes.isEmpty) return null;
    // From the start of today, so the data (and the widgets) only change when the mode does.
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final end = DateTime(now.year, now.month, now.day + 8);
    final line = <List<Object>>[];
    final reach = modeNow.reach;
    final current = modeNow.mode?.id ?? everythingId;
    if (reach == null || !reach.isBefore(end)) {
      line.add([start, end.millisecondsSinceEpoch, current]);
    } else {
      line.add([start, reach.millisecondsSinceEpoch, current]);
      for (final (m, a, b) in scheduleSegments(data.modeSchedule, reach, end)) {
        line.add([a.millisecondsSinceEpoch, b.millisecondsSinceEpoch, data.mode(m) == null ? everythingId : m]);
      }
    }
    return {
      'modeWidgets': data.modeWidgets,
      'modes': [
        {'id': everythingId, 'name': 'Everything', 'colour': 0xFF006A6A},
        for (final m in data.modes)
          {
            'id': m.id,
            'name': m.name,
            'colour': m.colour,
            if (!m.overdue) 'overdue': false,
            'due': m.due.name,
            if (!m.starred) 'starred': false,
            if (m.timer case final t?) 'timer': [t.focus, t.shortBreak, t.longBreak, t.every],
          },
      ],
      'modeLine': line,
    };
  }

  /// Item 102: the modes that hide [t] (the widgets still let it through when it is overdue,
  /// due soon or starred, as each mode says; "always show", "planned today" and "gone red" are
  /// worked out here).
  static List<String> modesHiding(AppData data, Task t, DateTime now) {
    if (t.alwaysShow) return const [];
    return [
      for (final m in data.modes)
        if (m.showFor(data, t.categoryId) == CatShow.hide && _quietBreak(data, m, t, now) == null) m.id,
    ];
  }

  /// Why [t] breaks through [m] for reasons the widgets can't work out themselves.
  static String? _quietBreak(AppData data, FocusMode m, Task t, DateTime now) {
    final probe = ModeNow()..mode = FocusMode.fromJson({
      ...m.toJson(),
      'overdue': false,
      'due': DueWithin.off.name,
      'starred': false,
    });
    return probe.breakThrough(data, t, now);
  }

  /// Item 101: open planned times from the start of today for a week, in time order. "later"
  /// says more of the task's own time is planned after it, so ticking it counts as worked on
  /// that day rather than ticking the task off (as on the Day plan).
  static List<Map<String, Object?>> dayPlanRows(AppData data, DateTime now) {
    final from = DateTime(now.year, now.month, now.day), to = from.add(const Duration(days: 7));
    final rows = <(DateTime, Map<String, Object?>)>[];
    for (final t in data.active) {
      if (t.habit) continue;
      for (final sl in t.slots) {
        if (sl.doneAt != null || sl.start.isBefore(from) || !sl.start.isBefore(to)) continue;
        final step = sl.stepId == null ? null : t.steps.where((x) => x.id == sl.stepId).firstOrNull;
        if (sl.stepId != null && (step == null || step.done)) continue;
        rows.add((
          sl.start,
          {
            'id': t.id,
            'slot': sl.id,
            if (step != null) 'step': step.id,
            'title': step?.title ?? t.title,
            if (step != null) 'task': t.title,
            'at': sl.start.millisecondsSinceEpoch,
            'end': sl.end.millisecondsSinceEpoch,
            if (sl.shared) 'shared': true,
            if (step == null && t.ownSlots.any((x) => !identical(x, sl) && x.doneAt == null && x.start.isAfter(sl.start)))
              'later': true,
          }
        ));
      }
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final r in rows) r.$2];
  }

  /// Item 101: free stretches in working hours from today for a week, as [start, end] in ms.
  static List<List<int>> dayPlanFree(AppData data, DateTime now) {
    final from = DateTime(now.year, now.month, now.day);
    return [
      for (var i = 0; i < 7; i++)
        for (final f in layoutDay(data, from.add(Duration(days: i))).free)
          [f.start.millisecondsSinceEpoch, f.end.millisecondsSinceEpoch],
    ];
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

  /// Item 108: buttons pressed on the Focus timer widget, in order: (op, when, task, step). The
  /// widget moved its own copy of the timer on ('focus_local'); the app now does the same.
  Future<List<({String op, DateTime at, String? task, String? step})>> takeFocusOps() async => [
        for (final e in await _take('widget_focus'))
          (op: e['op'] as String, at: _ms(e['at']), task: e['task'] as String?, step: e['step'] as String?),
      ];

  /// Item 108: modes picked on the Focus mode widget, in order: (mode id, when).
  Future<List<(String, DateTime)>> takeModePicks() async =>
      [for (final e in await _take('widget_mode')) (e['mode'] as String, _ms(e['at']))];

  /// Item 108: forgets the widgets' own copies of the timer and the mode once the app has
  /// caught up with them, and redraws the widgets from what the app shares.
  Future<void> clearWidgetCopies({bool focus = false, bool mode = false}) async {
    if (!supported || !await _ok) return;
    try {
      if (focus) await HomeWidget.saveWidgetData<String>('focus_local', null);
      if (mode) await HomeWidget.saveWidgetData<String>('widget_mode_local', null);
      _lastJson = null;
    } catch (e) {
      debugPrint('Could not clear widget copies: $e');
    }
  }

  /// Item 48B: tasks sent by other Android apps (Tasker and the like) while the app was closed,
  /// in the inbox file format (docs/PUSH_TASKS.md).
  Future<List<dynamic>> takePushed() => _take('pushed_tasks');

  /// Links opened from a widget: taskblocks://add, taskblocks://open?id=…, taskblocks://day?d=…
  Stream<Uri?> get clicks => supported ? HomeWidget.widgetClicked : const Stream.empty();

  Future<Uri?> launchUri() async => supported ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;
}
