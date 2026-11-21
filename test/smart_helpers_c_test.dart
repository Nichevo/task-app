import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/auto_plan.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/day_plan_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/what_now_sheet.dart';
import 'package:task_blocks/work_meetings.dart';

/// Item 114 C: Plan my day and What should I do now.
void main() {
  // A Monday a week or more ahead, so no time on it has passed.
  final mon = () {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day + 7);
    return DateTime(d.year, d.month, d.day + (DateTime.monday - d.weekday + 7) % 7);
  }();
  DateTime at(int h, [int m = 0]) => DateTime(mon.year, mon.month, mon.day, h, m);
  final morning = at(7);

  group('ranking', () {
    test('overdue, then due soonest, Do box and starred before the rest', () {
      final s = AppStore();
      final plain = s.addTask('Plain');
      final star = s.addTask('Starred')..starred = true;
      final soon = s.addTask('Due tomorrow')..dueAt = at(17).add(const Duration(days: 1));
      final late = s.addTask('Overdue')..dueAt = at(9).subtract(const Duration(days: 2));
      final box = s.addTask('Do box')..matrixBox = MatrixBox.doNow.id;
      final order = rankPicks(s.data, morning).map((p) => p.task).toList();
      expect(order.first, late);
      expect(order.indexOf(soon), lessThan(order.indexOf(plain)));
      expect(order.indexOf(box), lessThan(order.indexOf(plain)));
      expect(order.indexOf(star), lessThan(order.indexOf(plain)));
    });

    test('a task with steps is suggested as its next open step, after any it waits for', () {
      final s = AppStore();
      final t = s.addTask('Tender');
      final a = s.addStep(t, 'Read brief')..done = true;
      final b = s.addStep(t, 'Pricing');
      final c = s.addStep(t, 'Proof');
      c.afterIds.add(b.id);
      expect(a.done, isTrue);
      final p = rankPicks(s.data, morning).single;
      expect(p.step, b);
      expect(p.stepLabel, 'Step 2 of 3');
    });

    test('estimates are stretched by how far off they usually are', () {
      final s = AppStore();
      for (var i = 0; i < 10; i++) {
        s.data.done['d$i'] = DoneRecord(at: morning.subtract(Duration(days: i + 1)), tookMinutes: 1, estMinutes: 60, actMinutes: 90);
      }
      final t = s.addTask('Report')..estimate = 60;
      expect(pickMinutes(s.data, t, null, morning), 90);
      s.data.allowForEstimates = false;
      expect(pickMinutes(s.data, t, null, morning), 60);
    });
  });

  group('plan my day', () {
    test('fills free time around meetings and lunch, leaving some free', () {
      final s = AppStore();
      s.data.workMeetings.add(WorkMeeting(title: 'Stand-up', start: at(9), end: at(9, 30)));
      for (var i = 0; i < 12; i++) {
        s.addTask('Task $i').estimate = 60;
      }
      final plan = planDay(s.data, mon, now: morning);
      expect(plan, isNotEmpty);
      for (final p in plan) {
        expect(p.start.isBefore(at(9, 30)) && p.end.isAfter(at(9)), isFalse, reason: 'not over the meeting');
        expect(p.start.isBefore(at(13)) && p.end.isAfter(at(12)), isFalse, reason: 'not over lunch');
        expect(p.start.hour, greaterThanOrEqualTo(s.data.dayPlan.workStart ~/ 60));
      }
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].start.isBefore(plan[i - 1].end), isFalse, reason: 'no overlaps');
      }
      final planned = plan.fold(0, (a, p) => a + p.pick.minutes);
      final free = layoutFree(s, mon) - 60; // less lunch
      expect(planned, lessThanOrEqualTo((free * 0.85).round() + 1));
    });

    test('nothing planned twice, and Try again gives a different mix', () {
      final s = AppStore();
      for (var i = 0; i < 20; i++) {
        s.addTask('Task $i').estimate = 30 + (i % 3) * 15;
      }
      final one = planDay(s.data, mon, now: morning);
      expect(one.map((p) => p.pick.task.id).toSet().length, one.length);
      final two = planDay(s.data, mon, now: morning, attempt: 1);
      expect(two.map((p) => p.pick.task.id).toList(), isNot(one.map((p) => p.pick.task.id).toList()));
      final added = s.planPicks(one);
      expect(planDay(s.data, mon, now: morning).map((p) => p.pick.task.id).toSet().intersection(one.map((p) => p.pick.task.id).toSet()),
          isEmpty);
      for (final (t, sl) in added) {
        s.removeSlot(t, sl);
      }
    });

    testWidgets('the ✨ button plans, and Cancel takes it back', (tester) async {
      final s = AppStore();
      s.addTask('Write report').estimate = 60;
      s.addTask('Book flights').estimate = 30;
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s, initialDay: mon)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plan my day'));
      await tester.pumpAndSettle();
      expect(find.text('2 planned, 1 h 30'), findsOneWidget);
      expect(s.data.active.every((t) => t.slots.length == 1), isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(s.data.active.every((t) => t.slots.isEmpty), isTrue);
      await tester.tap(find.byTooltip('Plan my day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(s.data.active.every((t) => t.slots.length == 1), isTrue);
    });
  });

  group('what now', () {
    test('fits the time before the next meeting, and the place', () {
      final s = AppStore();
      s.data.workMeetings.add(WorkMeeting(title: 'Team lunch', start: at(12), end: at(13)));
      final long = s.addTask('Long one')..estimate = 180;
      final short = s.addTask('Short one')..estimate = 45;
      final now = at(11, 5);
      var a = whatNow(s.data, now);
      expect(a.freeMinutes, 55);
      expect(a.until, 'Team lunch');
      expect(a.picks.first.task, short);
      expect(a.picks.first.why.first, 'Fits before Team lunch');
      long.place = 'Office';
      short.place = 'Home';
      a = whatNow(s.data, now, place: 'Office');
      expect(a.picks.first.task, long, reason: 'at the office');
    });

    test('something planned now comes first', () {
      final s = AppStore();
      s.addTask('Urgent').dueAt = at(8);
      final planned = s.addTask('Planned');
      s.planTime(planned, at(10), 60);
      final a = whatNow(s.data, at(10, 15));
      expect(a.planned, isTrue);
      expect(a.picks.first.task, planned);
      expect(a.picks.first.minutes, 45);
    });

    test('the widget gets the picks', () {
      final s = AppStore();
      s.addTask('Call plumber').estimate = 5;
      final j = jsonDecode(HomeWidgets.widgetJson(s.data, at(10))) as Map;
      expect((j['doNow']['picks'] as List).single['title'], 'Call plumber');
      s.setHelper(Helper.whatNow, false);
      expect((jsonDecode(HomeWidgets.widgetJson(s.data, at(10))) as Map).containsKey('doNow'), isFalse);
    });

    testWidgets('the sheet shows a pick and Something else moves on', (tester) async {
      final s = AppStore();
      s.addTask('First').dueAt = DateTime.now().subtract(const Duration(days: 1));
      s.addTask('Second');
      Task? focused;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showWhatNow(c, s, onFocus: (t, _) => focused = t, onOpen: (_) {}),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      await tester.tap(find.text('Something else'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start focus'));
      await tester.pumpAndSettle();
      expect(focused?.title, 'Second');
    });
  });
}

int layoutFree(AppStore s, DateTime day) {
  final d = s.data.dayPlan;
  return d.workEnd - d.workStart - 30; // less the stand-up
}
