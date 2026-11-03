import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'models.dart';
import 'stats.dart';

typedef WidgetMove = ({String task, String? step, String stage, DateTime at});

/// Shares the task list with the Android home screen widgets, and picks up what was done
/// on them (ticks, step ticks, snoozes). Does nothing on other platforms.
class HomeWidgets {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static const _providers = [
    'app.taskblocks.TaskListWidget',
    'app.taskblocks.CompactWidget',
    'app.taskblocks.TodayWidget',
    'app.taskblocks.FocusWidget',
    'app.taskblocks.ChecklistWidget',
    'app.taskblocks.StatsWidget',
    'app.taskblocks.MonthWidget',
    'app.taskblocks.QuickAddWidget',
    // Item 68: board and matrix widgets.
    'app.taskblocks.BoardSummaryWidget',
    'app.taskblocks.StageListWidget',
    'app.taskblocks.NowDoingWidget',
    'app.taskblocks.BoardStepsWidget',
    'app.taskblocks.MatrixWidget',
  ];

  /// Writes what the widgets show and asks them to redraw.
  String? _lastJson;

  Future<void> push(AppData data) async {
    if (!supported) return;
    final json = widgetJson(data, DateTime.now());
    // Each update redraws every widget, so skip it when nothing they show has changed.
    if (json == _lastJson) return;
    try {
      await HomeWidget.saveWidgetData<String>('widget_data', json);
      _lastJson = json;
      for (final p in _providers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: p);
      }
    } catch (e) {
      debugPrint('Could not update widgets: $e');
    }
  }

  /// What the widgets are given (read by WidgetData.kt). Snoozed tasks are sent only when on
  /// the board, marked `snoozed`, so the board widgets count them like the board does.
  static String widgetJson(AppData data, DateTime now) {
    final stats = Stats(data, now);
    return jsonEncode({
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
          if (!t.isSnoozed(now) || t.kanban)
            {
              'id': t.id,
              'title': t.title,
              'cat': data.category(t.categoryId)?.id,
              'start': t.colourStart(now).millisecondsSinceEpoch,
              'due': t.dueAt?.millisecondsSinceEpoch,
              'locked': data.isLocked(t),
              'star': t.starred,
              if (t.isSnoozed(now)) 'snoozed': true,
              if (t.kanban) 'stage': (data.stage(t.stageId) ?? data.stages.firstOrNull)?.id,
              if (t.stageSince != null) 'since': t.stageSince!.millisecondsSinceEpoch,
              if (t.matrixBox != null) 'box': t.matrixBox,
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
      // Days (yyyy-MM-dd) with tasks due, for the mini month widget; repeats faded.
      'dueDays': stats.dueDays(now, const Duration(days: 62)),
      'stats': {'week': stats.doneThisWeek, 'streak': stats.streak},
    });
  }

  Future<List<dynamic>> _take(String key) async {
    if (!supported) return const [];
    try {
      final raw = await HomeWidget.getWidgetData<String>(key);
      if (raw == null || raw.isEmpty || raw == '[]') return const [];
      await HomeWidget.saveWidgetData<String>(key, '[]');
      return jsonDecode(raw) as List;
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

  /// Item 48B: tasks sent by other Android apps (Tasker and the like) while the app was closed,
  /// in the inbox file format (docs/PUSH_TASKS.md).
  Future<List<dynamic>> takePushed() => _take('pushed_tasks');

  /// Links opened from a widget: taskblocks://add, taskblocks://open?id=…, taskblocks://day?d=…
  Stream<Uri?> get clicks => supported ? HomeWidget.widgetClicked : const Stream.empty();

  Future<Uri?> launchUri() async => supported ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;
}
