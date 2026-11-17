import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/focus_timer.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/modes.dart';
import 'package:task_blocks/screens/focus_page.dart';
import 'package:task_blocks/store.dart';

// Item 108: the Focus timer widget's buttons without the app, a focus mode of a widget's own,
// mode buttons on the Focus mode widget, and round lengths for each mode.
void main() {
  setUp(() {
    modeNow
      ..mode = null
      ..peek = false
      ..reach = null
      ..reason = null
      ..data = null
      ..noonModes = {};
  });
  tearDown(() => focusNow = null);

  test('presses on the widget are done again in the app at the times they were made', () {
    final s = AppStore();
    final t = s.addTask('Order worktops');
    final t0 = DateTime.now().subtract(const Duration(hours: 2));
    s.applyFocusOp('start', t0, taskId: t.id);
    final f = focusNow!;
    expect(f.taskId, t.id);
    expect(f.end, t0.add(const Duration(minutes: 25)));
    // Paused 10 minutes in: 10 minutes on the task, 15 left.
    s.applyFocusOp('pause', t0.add(const Duration(minutes: 10)));
    expect(f.running, isFalse);
    expect(f.left, const Duration(minutes: 15));
    expect(focusOn(t, t0), 10);
    // +5 while paused, then on again an hour later: the round ends 20 minutes after that.
    s.applyFocusOp('add', t0.add(const Duration(minutes: 11)));
    expect(f.left, const Duration(minutes: 20));
    final back = t0.add(const Duration(minutes: 70));
    s.applyFocusOp('resume', back);
    expect(f.end, back.add(const Duration(minutes: 20)));
    // The round ended on its own before the break was skipped: the break comes first.
    final skip = back.add(const Duration(minutes: 22));
    s.applyFocusOp('skip', skip);
    expect(f.round, 2);
    expect(f.phase, FocusPhase.focus);
    expect(f.end, skip.add(const Duration(minutes: 25)));
    expect(focusOn(t, t0), 30);
    s.applyFocusOp('stop', skip.add(const Duration(minutes: 5)));
    expect(focusNow, isNull);
    expect(focusOn(t, t0), 35);
  });

  test('a press for a task that is gone does nothing', () {
    final s = AppStore();
    s.applyFocusOp('start', DateTime.now(), taskId: 'nope');
    expect(focusNow, isNull);
    s.applyFocusOp('pause', DateTime.now());
    expect(focusNow, isNull);
  });

  test('a mode can have its own round lengths; the timer uses the mode in force', () {
    final s = AppStore();
    final m = FocusMode.create('Work')..timer = FocusSettings(focus: 50, shortBreak: 10, longBreak: 20, every: 3);
    s.addMode(m);
    final t = s.addTask('Quote');
    s.chooseMode(m.id);
    expect(modeNow.mode?.id, m.id);
    s.data.focusSettings.dnd = true;
    expect(focusLengthsNow(s.data).focus, 50);
    expect(focusLengthsNow(s.data).dnd, isTrue);
    s.startFocus(t);
    expect(focusNow!.length, const Duration(minutes: 50));
    s.tickFocus(focusNow!.end!.add(const Duration(seconds: 1)));
    expect(focusNow!.length, const Duration(minutes: 10));
    s.stopFocus();
    // Everything: the lengths for every mode.
    s.chooseMode(everythingId);
    expect(focusLengthsNow(s.data).focus, 25);
    // Saved with the mode, without its own Do not disturb.
    final j = m.toJson();
    expect(j['timer'], {'focus': 50, 'short': 10, 'long': 20, 'every': 3});
    expect(FocusMode.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>).timer?.focus, 50);
    expect(FocusMode.fromJson({'id': 'x', 'name': 'Home'}).timer, isNull);
  });

  test('the widgets get each mode\'s lengths and the modes even when not following them', () {
    final s = AppStore();
    final m = FocusMode.create('Work')..timer = FocusSettings(focus: 50, shortBreak: 10);
    s.addMode(m);
    s.data.modeWidgets = false;
    s.data.focusSettings.dnd = true;
    final j = jsonDecode(HomeWidgets.widgetJson(s.data, DateTime.now())) as Map<String, dynamic>;
    expect(j['modeWidgets'], isFalse);
    final work = (j['modes'] as List).firstWhere((x) => x['id'] == m.id) as Map;
    expect(work['timer'], [50, 10, 15, 4]);
    expect(((j['modes'] as List).first as Map).containsKey('timer'), isFalse);
    expect(j['focusDnd'], isTrue);
  });

  test('a mode picked on the widget lasts until the schedule changes; the scheduled one goes back to it', () {
    final s = AppStore();
    final m = FocusMode.create('Work');
    final h = FocusMode.create('Home');
    s.addMode(m);
    s.addMode(h);
    final now = DateTime.now();
    // Work all week, every hour of the day: the schedule says Work now.
    s.setModeSchedule([for (var d = 1; d <= 7; d++) ModeSlot(day: d, start: 0, end: 24 * 60, mode: m.id)]);
    expect(modeNow.mode?.id, m.id);
    s.applyModePick(h.id, now);
    expect(modeNow.mode?.id, h.id);
    expect(s.deviceModeChoice?.mode, h.id);
    s.applyModePick(m.id, now);
    expect(modeNow.mode?.id, m.id);
    expect(s.deviceModeChoice?.mode ?? '', '');
    // A mode deleted since is left alone.
    s.applyModePick('gone', now);
    expect(modeNow.mode?.id, m.id);
  });

  testWidgets('focus settings: lengths for every mode or for one mode', (tester) async {
    final s = AppStore();
    final m = FocusMode.create('Work');
    s.addMode(m);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FocusSettingsSheet(store: s))));
    expect(find.text('Round lengths for'), findsOneWidget);
    expect(find.text('Every mode'), findsOneWidget);
    await tester.tap(find.text('Every mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    expect(find.text('Own lengths in Work'), findsOneWidget);
    await tester.tap(find.text('Own lengths in Work'));
    await tester.pumpAndSettle();
    expect(m.timer, isNotNull);
    expect(m.timer!.focus, 25);
  });
}
