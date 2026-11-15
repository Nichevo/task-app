import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/day_plan.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/screens/side_panel.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';

DateTime at(int h, [int m = 0, int day = 16]) => DateTime(2026, 11, day, h, m);

/// Item 101, part 3 (1.11.2): the bits the plan doc had that were missing.
void main() {
  test('Too early: a task starting before what it comes after is finished', () {
    final s = AppStore();
    final a = s.addTask('Buy paint');
    final b = s.addTask('Paint fence')..afterTaskId = a.id;
    s.planTime(a, at(10), 60);
    final early = tooEarlyFor(s.data, b, null, at(10, 30));
    expect(early.single.$1, 'Buy paint');
    expect(early.single.$2, at(11));
    expect(tooEarlyFor(s.data, b, null, at(11)), isEmpty);
  });

  test('Too early: a step before the step it comes after', () {
    final s = AppStore();
    final t = s.addTask('Fence');
    final sand = s.addStep(t, 'Sand'), coat = s.addStep(t, 'Coat');
    coat.afterIds.add(sand.id);
    s.planTime(t, at(9), 60, step: sand);
    expect(tooEarlyFor(s.data, t, coat, at(9, 30)).single.$1, 'Sand');
    s.toggleStep(t, sand);
    expect(tooEarlyFor(s.data, t, coat, at(9, 30)), isEmpty);
  });

  test('moving a band that leaves room takes the open things inside it', () {
    final s = AppStore();
    final bake = s.addTask('Bake bread'), mail = s.addTask('Email'), call = s.addTask('Call');
    s.planTime(bake, at(9), 120, shared: true);
    final m = s.planTime(mail, at(9, 30), 30);
    s.planTime(call, at(12), 30); // outside the band
    final band = blocksOn(s.data, at(9)).firstWhere((b) => b.shared);
    final moves = insideBand(s.data, band, const Duration(hours: 1));
    expect(moves.length, 1);
    expect(identical(moves.single.slot, m), isTrue);
    expect(moves.single.to, at(10, 30));
  });

  test('Show ticked: saved only when off, and hides ticked blocks', () {
    final s = AppStore();
    final t = s.addTask('Write');
    s.planTime(t, at(9), 30).doneAt = at(9, 30);
    s.planTime(t, at(11), 30);
    expect(s.data.dayPlan.toJson().containsKey('ticked'), isFalse);
    expect(layoutDay(s.data, at(0)).blocks.length, 2);
    s.data.dayPlan.showTicked = false;
    final json = s.data.dayPlan.toJson();
    expect(json['ticked'], false);
    expect(DayPlanSettings.fromJson(jsonDecode(jsonEncode(json))).showTicked, isFalse);
    expect(layoutDay(s.data, at(0)).blocks.length, 1);
  });

  test('a missed time shows in the tray with its slot and length', () {
    final s = AppStore();
    final t = s.addTask('Tidy shed');
    final sl = s.planTime(t, at(9, 0, 13), 45);
    final item = trayFor(s.data, at(0), at: at(8)).firstWhere((i) => i.task == t);
    expect(item.why, startsWith('Missed'));
    expect(identical(item.missed, sl), isTrue);
    expect(item.minutes(s.data), 45);
  });

  test('the widgets get free time in working hours', () {
    final s = AppStore();
    s.planTime(s.addTask('Write'), at(10), 60);
    final free = jsonDecode(HomeWidgets.widgetJson(s.data, at(7)))['planFree'] as List;
    expect(free, isNotEmpty);
    final today = free.where((f) => DateTime.fromMillisecondsSinceEpoch(f[0]).day == 16).toList();
    // No free stretch overlaps the planned hour.
    for (final f in today) {
      final a = DateTime.fromMillisecondsSinceEpoch(f[0]), b = DateTime.fromMillisecondsSinceEpoch(f[1]);
      expect(a.isBefore(at(11)) && b.isAfter(at(10)), isFalse);
    }
  });

  testWidgets('with the Day plan in the side panel, list rows can be dragged', (tester) async {
    tester.view.physicalSize = const Size(900 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = AppStore();
    s.addTask('Fix the leak');
    s.showPanel(PanelView.dayPlan);
    await tester.pumpWidget(TaskApp(store: s));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LongPressDraggable<TrayItem>), findsWidgets);
    s.showPanel(PanelView.agenda);
    await tester.pumpAndSettle();
    expect(find.byType(LongPressDraggable<TrayItem>), findsNothing);
  });
}
