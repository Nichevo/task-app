import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'models.dart';

/// Shares the task list with the Android home screen widgets, and picks up tasks ticked
/// off on a widget. Does nothing on other platforms.
class HomeWidgets {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static const _providers = [
    'com.jeff.task_blocks.TaskListWidget',
    'com.jeff.task_blocks.CompactWidget',
  ];

  /// Writes what the widgets show and asks them to redraw.
  Future<void> push(AppData data) async {
    if (!supported) return;
    final now = DateTime.now();
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
            },
      ],
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

  /// Tasks ticked off on a widget since the app last looked: (task id, when).
  Future<List<(String, DateTime)>> takeCompleted() async {
    if (!supported) return const [];
    try {
      final raw = await HomeWidget.getWidgetData<String>('widget_done');
      if (raw == null || raw.isEmpty || raw == '[]') return const [];
      await HomeWidget.saveWidgetData<String>('widget_done', '[]');
      return [
        for (final e in jsonDecode(raw) as List)
          (e['id'] as String, DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt())),
      ];
    } catch (e) {
      debugPrint('Could not read widget ticks: $e');
      return const [];
    }
  }

  /// Links opened from a widget: taskblocks://add or taskblocks://open?id=…
  Stream<Uri?> get clicks => supported ? HomeWidget.widgetClicked : const Stream.empty();

  Future<Uri?> launchUri() async => supported ? HomeWidget.initiallyLaunchedFromHomeWidget() : null;
}
