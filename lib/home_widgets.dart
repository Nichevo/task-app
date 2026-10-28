import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'models.dart';
import 'stats.dart';

/// Shares the task list with the Android home screen widgets, and picks up what was done
/// on them (ticks, step ticks, snoozes). Does nothing on other platforms.
class HomeWidgets {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static const _providers = [
    'com.jeff.task_blocks.TaskListWidget',
    'com.jeff.task_blocks.CompactWidget',
    'com.jeff.task_blocks.TodayWidget',
    'com.jeff.task_blocks.FocusWidget',
    'com.jeff.task_blocks.ChecklistWidget',
    'com.jeff.task_blocks.StatsWidget',
    'com.jeff.task_blocks.MonthWidget',
    'com.jeff.task_blocks.QuickAddWidget',
  ];

  /// Writes what the widgets show and asks them to redraw.
  Future<void> push(AppData data) async {
    if (!supported) return;
    final now = DateTime.now();
    final stats = Stats(data, now);
    final json = jsonEncode({
      'hoursToRed': data.hoursToRed,
      'colourByDue': data.colourByDue,
      'categories': [for (final c in data.categories) {'id': c.id, 'name': c.name}],
      'tasks': [
        for (final t in [...data.active.where((t) => t.starred), ...data.active.where((t) => !t.starred)])
          if (!t.isSnoozed(now))
            {
              'id': t.id,
              'title': t.title,
              'cat': data.category(t.categoryId)?.id,
              'start': t.colourStart(now).millisecondsSinceEpoch,
              'due': t.dueAt?.millisecondsSinceEpoch,
              'locked': data.isLocked(t),
              'star': t.starred,
              if (t.steps.isNotEmpty)
                'steps': [
                  for (final s in t.steps) {'id': s.id, 'title': s.title, 'done': s.done},
                ],
            },
      ],
      // Days (yyyy-MM-dd) with tasks due, for the mini month widget; repeats faded.
      'dueDays': stats.dueDays(now, const Duration(days: 62)),
      'stats': {'week': stats.doneThisWeek, 'streak': stats.streak},
    });
    try {
      await HomeWidget.saveWidgetData<String>('widget_data', json);
      for (final p in _providers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: p);
      }
    } catch (e) {
      debugPrint('Could not update widgets: $e');
    }
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

  /// Links opened from a widget: taskblocks://add, taskblocks://open?id=…, taskblocks://day?d=…
  Stream<Uri?> get clicks => supported ? HomeWidget.widgetClicked : const Stream.empty();

  Future<Uri?> launchUri() async => supported ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;
}
