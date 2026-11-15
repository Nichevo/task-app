import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/focus_timer.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/reminders.dart';
import 'package:task_blocks/screens/focus_page.dart';
import 'package:task_blocks/store.dart';

void main() {
  tearDown(() => focusNow = null);

  test('a round becomes a break, the break waits for the next round, and minutes are saved', () {
    final s = AppStore();
    final t = s.addTask('Order worktops');
    s.startFocus(t);
    final f = focusNow!;
    final start = f.end!.subtract(const Duration(minutes: 25));
    expect(f.round, 1);
    expect(f.phase, FocusPhase.focus);
    // The round ends: 25 minutes on the task today, worked on today, a short break.
    s.tickFocus(start.add(const Duration(minutes: 25, seconds: 1)));
    expect(focusOn(t, start), 25);
    expect(t.worked, contains(dayKey(start)));
    expect(f.phase, FocusPhase.shortBreak);
    expect(f.length, const Duration(minutes: 5));
    // The break ends: round 2 waits to be started.
    s.tickFocus(start.add(const Duration(minutes: 31)));
    expect(f.phase, FocusPhase.focus);
    expect(f.round, 2);
    expect(f.heldBreak, isTrue);
    expect(f.running, isFalse);
    s.resumeFocus();
    expect(f.running, isTrue);
    s.stopFocus();
    expect(focusNow, isNull);
  });

  test('the long break comes after every fourth round; pause, +5 and skip', () {
    final s = AppStore();
    final t = s.addTask('Quotes');
    s.data.focusSettings.every = 2;
    s.startFocus(t);
    final f = focusNow!
      ..round = 2;
    s.tickFocus(f.end!.add(const Duration(seconds: 1)));
    expect(f.phase, FocusPhase.longBreak);
    expect(f.length, const Duration(minutes: 15));
    s.skipBreak();
    expect(f.phase, FocusPhase.focus);
    expect(f.round, 3);
    expect(f.running, isTrue);
    s.pauseFocus();
    expect(f.paused, isTrue);
    final left = f.left!;
    s.addFocusTime();
    expect(f.left, left + const Duration(minutes: 5));
    expect(f.length, const Duration(minutes: 30));
    s.resumeFocus();
    expect(f.end!.difference(DateTime.now()).inMinutes, closeTo(left.inMinutes + 5, 1));
    s.stopFocus();
  });

  test('a ticked-off task stops its timer; the timer and settings survive saving', () {
    final s = AppStore();
    final t = s.addTask('Tap');
    s.startFocus(t);
    final copy = FocusTimer.tryParse(jsonDecode(jsonEncode(focusNow!.toJson())))!;
    expect([copy.taskId, copy.phase, copy.round, copy.length, copy.end!.millisecondsSinceEpoch ~/ 1000],
        [t.id, FocusPhase.focus, 1, const Duration(minutes: 25), focusNow!.end!.millisecondsSinceEpoch ~/ 1000]);
    s.complete(t);
    s.tickFocus();
    expect(focusNow, isNull);
    s.data.focusSettings
      ..focus = 50
      ..dnd = true;
    final back = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())));
    expect([back.focusSettings.focus, back.focusSettings.dnd, back.focusSettings.every], [50, true, 4]);
    final task = Task.create('x')..focus['2026-11-15'] = 40;
    expect(Task.fromJson(jsonDecode(jsonEncode(task.toJson()))).focus, {'2026-11-15': 40});
  });

  test('other reminders wait for the break; the round end reminds', () {
    final s = AppStore();
    final t = s.addTask('Focus on me');
    final other = s.addTask('Ring the bank', due: DateTime.now().add(const Duration(minutes: 10)));
    s.startFocus(t);
    final end = focusNow!.end!;
    final plan = Reminders.plan(s.data, DateTime.now());
    final bank = plan.where((r) => r.task == other && r.title == 'Task due').single;
    expect(bank.when.isBefore(end), isFalse);
    expect(Reminders.heldForFocus, greaterThan(0));
    final ring = plan.where((r) => r.id == Reminders.focusEndId).single;
    expect(ring.when, end);
    expect(ring.title, 'Time for a break');
    s.stopFocus();
  });

  test('the widgets get the timer and the minutes', () {
    final s = AppStore();
    final t = s.addTask('Order worktops');
    t.steps.add(TaskStep.create('Get two quotes'));
    t.focus[dayKey(DateTime.now())] = 70;
    s.startFocus(t, stepId: t.steps.first.id);
    final j = jsonDecode(HomeWidgets.widgetJson(s.data, DateTime.now())) as Map<String, dynamic>;
    final f = j['focusTimer'] as Map<String, dynamic>;
    expect(f['title'], 'Order worktops');
    expect(f['step'], t.steps.first.id);
    expect((f['steps'] as List).single['title'], 'Get two quotes');
    expect(f['today'], 70);
    expect(f['end'], isA<int>());
    expect(j['focusLengths'], [25, 5, 15, 4]);
    expect(((j['tasks'] as List).single as Map)['focusToday'], 70);
    s.stopFocus();
  });

  testWidgets('the Focus screen shows the countdown, the task and its steps', (tester) async {
    final s = AppStore();
    final t = s.addTask('Order worktops');
    t.steps.add(TaskStep.create('Get two quotes'));
    s.startFocus(t, stepId: t.steps.first.id);
    await tester.pumpWidget(MaterialApp(home: FocusPage(store: s)));
    await tester.pump();
    expect(find.text('Order worktops'), findsOneWidget);
    expect(find.textContaining('← this session'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    s.stopFocus();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('No focus session running.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
