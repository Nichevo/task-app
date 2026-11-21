import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/daily_helpers.dart';
import 'package:task_blocks/estimates.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/modes.dart';
import 'package:task_blocks/reminders.dart';
import 'package:task_blocks/screens/settings_page.dart';
import 'package:task_blocks/screens/stats_page.dart';
import 'package:task_blocks/screens/wrap_up_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/actual_sheet.dart';
import 'package:task_blocks/work_meetings.dart';

/// Item 114 B: estimates against actual time, the morning brief and wrap up.
void main() {
  group('estimate vs actual', () {
    test('ticking off keeps the estimate and the recorded time, and asks', () async {
      final s = AppStore();
      final asked = <Task>[];
      final sub = s.actualAsks.listen(asked.add);
      final t = s.addTask('Review the draft')..estimate = 60;
      t.focus[dayKey(DateTime.now())] = 85;
      s.complete(t);
      await Future<void>.delayed(Duration.zero);
      expect(asked, [t]);
      expect(t.actual, 85);
      expect(s.data.done[t.id]!.estMinutes, 60);
      expect(s.data.done[t.id]!.actMinutes, 85);
      s.setActual(t, 90);
      expect(s.data.done[t.id]!.actMinutes, 90);
      final back = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())) as Map<String, dynamic>);
      expect(back.done[t.id]!.actMinutes, 90);
      expect(back.archived.single.actual, 90);
      await sub.cancel();
    });

    test('no question for a task without an estimate, nor when switched off or set to never', () async {
      final s = AppStore();
      final asked = <Task>[];
      final sub = s.actualAsks.listen(asked.add);
      s.complete(s.addTask('No estimate'));
      s.data.askActual = 'unrecorded';
      final timed = s.addTask('Timed')..estimate = 30;
      timed.focus[dayKey(DateTime.now())] = 20;
      s.complete(timed);
      s.data.askActual = 'never';
      s.complete(s.addTask('Never')..estimate = 30);
      s.data.askActual = 'always';
      s.setHelper(Helper.learnEstimates, false);
      s.complete(s.addTask('Off')..estimate = 30);
      await Future<void>.delayed(Duration.zero);
      expect(asked, isEmpty);
      await sub.cancel();
    });

    test('statistics and the planning factor', () {
      final d = AppData(categories: [TaskCategory(id: 'w', name: 'Work')]);
      final now = DateTime(2026, 11, 21, 12);
      for (var i = 0; i < 12; i++) {
        d.done['t$i'] = DoneRecord(
          at: now.subtract(Duration(days: i)),
          tookMinutes: 100,
          categoryId: i < 6 ? 'w' : null,
          title: 'Task $i',
          estMinutes: 60,
          actMinutes: i < 6 ? 96 : 60,
        );
      }
      d.done['old'] = DoneRecord(at: now.subtract(const Duration(days: 90)), tookMinutes: 1, estMinutes: 10, actMinutes: 500);
      final st = estimateStats(d, now);
      expect(st.count, 12);
      expect(st.ratio, closeTo(1.3, 0.001));
      expect(st.byCategory.firstWhere((c) => c.$1 == 'w').$2, closeTo(1.6, 0.001));
      expect(st.misses.first.act, 96);
      expect(estimateFactor(d, 'w', now), closeTo(1.6, 0.001));
      expect(estimateFactor(d, 'other', now), closeTo(1.3, 0.001));
      d.allowForEstimates = false;
      expect(estimateFactor(d, 'w', now), 1);
    });

    testWidgets('the question sheet saves the picked time', (tester) async {
      final s = AppStore();
      final t = s.addTask('Write it')..estimate = 60;
      t.focus[dayKey(DateTime.now())] = 85;
      s.complete(t);
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) => TextButton(onPressed: () => askActualTime(c, s, t), child: const Text('go'))),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The timer and Day plan say about 1 h 25 m'), findsOneWidget);
      await tester.tap(find.text('2 h'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(t.actual, 120);
    });

    testWidgets('the Statistics page shows the estimates card', (tester) async {
      final s = AppStore();
      for (var i = 0; i < 3; i++) {
        final t = s.addTask('T$i')..estimate = 30;
        t.focus[dayKey(DateTime.now())] = 45;
        s.complete(t);
      }
      await tester.pumpWidget(MaterialApp(home: StatsPage(store: s)));
      await tester.dragUntilVisible(find.text('How good are your estimates?'), find.byType(ListView).first, const Offset(0, -300));
      await tester.dragUntilVisible(find.text('1.5×'), find.byType(ListView).first, const Offset(0, -100));
      expect(find.text('1.5×'), findsOneWidget);
    });
  });

  group('morning brief and wrap up', () {
    final thu = DateTime(2026, 11, 19);
    test('times: weekdays by default, or the mode schedule', () {
      final d = AppData();
      expect(dailyTime(d, d.briefAt, thu), DateTime(2026, 11, 19, 7, 30));
      expect(dailyTime(d, d.briefAt, DateTime(2026, 11, 21)), isNull, reason: 'Saturday');
      d.modeSchedule.add(ModeSlot(day: 4, start: 9 * 60, end: 18 * 60, mode: 'work'));
      expect(dailyTime(d, d.wrapAt, thu, end: true), DateTime(2026, 11, 19, 18), reason: 'when Work ends');
      expect(dailyTime(d, d.briefAt, DateTime(2026, 11, 20)), isNull, reason: 'Friday has no mode');
      d.briefAt = DailyAt(at: 8 * 60, days: {5}, follow: false);
      expect(dailyTime(d, d.briefAt, DateTime(2026, 11, 20)), DateTime(2026, 11, 20, 8));
    });

    test('the brief lists meetings, the first thing, what is due and overdue', () {
      final s = AppStore();
      s.data.workMeetings.add(WorkMeeting(title: 'Stand-up', start: thu.add(const Duration(hours: 9)), end: thu.add(const Duration(hours: 9, minutes: 30))));
      final report = s.addTask('Write report');
      s.planTime(report, thu.add(const Duration(hours: 10)), 60);
      s.addTask('Send numbers').dueAt = thu.add(const Duration(hours: 17));
      s.addTask('Old one').dueAt = DateTime(2026, 11, 17);
      final (title, body) = briefText(s.data, thu.add(const Duration(hours: 7, minutes: 30)));
      expect(title, 'Thursday: 1 meeting, 1 planned');
      expect(body, 'First up: Stand-up at 09:00. Due today: Send numbers. 1 task overdue.');
    });

    test('notifications are planned for the week and open their screens', () {
      final now = DateTime(2026, 11, 19, 6);
      final s = AppStore();
      s.addTask('Due today').dueAt = DateTime(2026, 11, 19, 15);
      final all = Reminders.dailyHelpers(s.data, now);
      final briefs = all.where((r) => r.kind == ReminderKind.brief).toList();
      final wraps = all.where((r) => r.kind == ReminderKind.wrapUp).toList();
      expect(briefs.map((r) => r.when.weekday).toSet(), {1, 2, 3, 4, 5});
      expect(wraps.first.when, DateTime(2026, 11, 19, 17, 30));
      expect(wraps.first.title, '1 still open');
      expect(jsonDecode(wraps.first.payload!)['wrap'], isTrue);
      s.setHelper(Helper.morningBrief, false);
      expect(Reminders.dailyHelpers(s.data, now).where((r) => r.kind == ReminderKind.brief), isEmpty);
    });

    test('roll a task on to tomorrow, and undo', () {
      final s = AppStore();
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final t = s.addTask('Leftover')..dueAt = day.add(const Duration(hours: 15));
      final slot = s.planTime(t, day.add(const Duration(hours: 10)), 30);
      expect(leftOpen(s.data, day), [t]);
      final undo = s.rollTask(t, day, day.add(const Duration(days: 1)));
      expect(t.dueAt, DateTime(day.year, day.month, day.day + 1, 15));
      expect(slot.start, DateTime(day.year, day.month, day.day + 1, 10));
      expect(leftOpen(s.data, day), isEmpty);
      undo();
      expect(t.dueAt, day.add(const Duration(hours: 15)));
      expect(slot.start, day.add(const Duration(hours: 10)));
    });

    testWidgets('the Wrap up screen moves things on', (tester) async {
      final s = AppStore();
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      final a = s.addTask('Carry me')..dueAt = day.add(const Duration(hours: 9));
      final b = s.addTask('Finish me')..dueAt = day.add(const Duration(hours: 9));
      s.addTask('Not today').dueAt = day.add(const Duration(days: 3));
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: WrapUpPage(store: s)));
      expect(find.text('Carry me'), findsOneWidget);
      expect(find.text('Not today'), findsNothing);
      await tester.tap(find.text('Tomorrow').first);
      await tester.pump();
      expect(a.dueAt!.day, day.add(const Duration(days: 1)).day);
      expect(find.text('moved to tomorrow'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(s.data.archived, contains(b));
    });

    testWidgets('Settings has the switches and times', (tester) async {
      final s = AppStore();
      await tester.pumpWidget(MaterialApp(home: SettingsPage(store: s)));
      expect(find.text('Learn from my estimates'), findsOneWidget);
      expect(find.text('Morning brief'), findsOneWidget);
      expect(find.text('At 07:30, weekdays'), findsOneWidget);
      expect(find.text('Wrap up the day'), findsOneWidget);
      await tester.tap(find.text('Morning brief'));
      await tester.pump();
      expect(s.data.helperOn(Helper.morningBrief), isFalse);
    });
  });
}
