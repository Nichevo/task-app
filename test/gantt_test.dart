import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/csv_import.dart';
import 'package:task_blocks/gantt.dart';
import 'package:task_blocks/input_parse.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/gantt_page.dart';
import 'package:task_blocks/store.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

// Monday 9 November 2026.
final mon = DateTime(2026, 11, 9);

/// Item 72: the Gantt chart.
void main() {
  group('days of work', () {
    test('weekends skipped unless they count', () {
      expect(workEnd(mon, 5, weekends: false), DateTime(2026, 11, 13));
      expect(workEnd(mon, 6, weekends: false), DateTime(2026, 11, 16), reason: 'jumps the weekend');
      expect(workEnd(mon, 6, weekends: true), DateTime(2026, 11, 14));
      expect(workEnd(DateTime(2026, 11, 7), 2, weekends: false), DateTime(2026, 11, 10),
          reason: 'a Saturday start begins on Monday');
      expect(workStart(DateTime(2026, 11, 16), 2, weekends: false), DateTime(2026, 11, 13));
      expect(workDays(mon, DateTime(2026, 11, 16), weekends: false), 6);
    });
  });

  group('bars', () {
    test('start plus length gives the expected end, apart from the due date', () {
      final s = AppStore();
      final t = s.addTask('Fit shelves')
        ..startAt = mon
        ..takesDays = 4
        ..dueAt = DateTime(2026, 11, 11, 17);
      final b = barFor(t, s.data)!;
      expect(b.start, mon);
      expect(b.end, DateTime(2026, 11, 12));
      expect(b.late, isTrue);
      expect(b.lateDays, 1);
    });

    test('no length: the bar ends on the due date; no start: it counts back from it', () {
      final s = AppStore();
      final a = s.addTask('A')
        ..startAt = mon
        ..dueAt = DateTime(2026, 11, 11, 17);
      expect(barFor(a, s.data)!.end, DateTime(2026, 11, 11));
      final b = s.addTask('B')
        ..dueAt = DateTime(2026, 11, 16, 9)
        ..takesDays = 2;
      final bar = barFor(b, s.data)!;
      expect(bar.start, DateTime(2026, 11, 13));
      expect(bar.guessedStart, isTrue);
      expect(barFor(s.addTask('C'), s.data), isNull, reason: 'needs dates');
    });

    test('the Settings default for weekends applies unless the task says', () {
      final s = AppStore();
      final t = s.addTask('Paint')
        ..startAt = DateTime(2026, 11, 13)
        ..takesDays = 3;
      expect(barFor(t, s.data)!.end, DateTime(2026, 11, 17));
      s.data.ganttWeekends = true;
      expect(barFor(t, s.data)!.end, DateTime(2026, 11, 15));
      t.countWeekends = false;
      expect(barFor(t, s.data)!.end, DateTime(2026, 11, 17));
    });

    test('a milestone is one day', () {
      final s = AppStore();
      final t = s.addTask('Review')
        ..milestone = true
        ..dueAt = DateTime(2026, 11, 10, 10);
      final b = barFor(t, s.data)!;
      expect(b.start, b.end);
    });
  });

  group('steps on the chart', () {
    test('a step can have a start and days of work, or just a date (a diamond)', () {
      final s = AppStore();
      final t = s.addTask('Paint spare room')
        ..gantt = true
        ..startAt = mon
        ..takesDays = 8;
      final prep = s.addStep(t, 'Prep walls');
      final dry = s.addStep(t, 'Let it dry');
      s.setStepDue(t, dry, DateTime(2026, 11, 13, 17));
      expect(stepBar(t, prep, s.data), isNull, reason: 'no dates yet');
      expect(stepIsPoint(dry), isTrue);
      expect(stepBar(t, dry, s.data)!.start, DateTime(2026, 11, 13));
      s.setStepPlan(t, prep, start: DateTime(2026, 11, 12), takes: 3);
      final b = stepBar(t, prep, s.data)!;
      expect(b.start, DateTime(2026, 11, 12));
      expect(b.end, DateTime(2026, 11, 16), reason: 'the weekend is skipped as its task counts it');
      s.setStepDue(t, prep, DateTime(2026, 11, 13, 17));
      expect(stepBar(t, prep, s.data)!.lateDays, 3);
      // Days of work and a due date, no start: counts back from the due date.
      s.setStepPlan(t, dry, takes: 2);
      expect(stepIsPoint(dry), isFalse);
      expect(stepBar(t, dry, s.data)!.start, DateTime(2026, 11, 12));
      final back = roundTrip(s.data).task(t.id)!.steps.first;
      expect(back.startAt, DateTime(2026, 11, 12));
      expect(back.takesDays, 3);
      // Progress on a step fills its bar and counts toward its task's progress.
      s.setStepPlan(t, prep, start: DateTime(2026, 11, 12), takes: 3, progress: 50);
      expect(prep.share, 0.5);
      expect(t.progressShare, 0.25, reason: 'half of one of two steps');
      dry.done = true;
      expect(t.progressShare, 0.75);
      expect(roundTrip(s.data).task(t.id)!.steps.first.progress, 50);
      final (n, _) = s.splitOut(t, prep);
      expect(n.startAt, DateTime(2026, 11, 12));
      expect(n.takesDays, 3);
    });

    testWidgets('tapping a step row asks for its start and days of work', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppStore();
      final t = s.addTask('Paint spare room')
        ..gantt = true
        ..startAt = DateTime.now()
        ..takesDays = 5;
      final st = s.addStep(t, 'Prep walls');
      await tester.pumpWidget(MaterialApp(home: GanttPage(store: s)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show steps').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prep walls'));
      await tester.pumpAndSettle();
      expect(find.text('Takes: not set'), findsOneWidget);
      await tester.tap(find.byTooltip('More days'));
      await tester.tap(find.byTooltip('More days'));
      await tester.pumpAndSettle();
      expect(find.text('Takes 2 days of work'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(st.takesDays, 2);
      expect(st.progress, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('comes after', () {
    test('several tasks, a wait, and a clash when it starts too early', () {
      final s = AppStore();
      final paint = s.addTask('Order paint')
        ..startAt = mon
        ..takesDays = 2;
      final furniture = s.addTask('Move furniture')
        ..startAt = mon
        ..takesDays = 3;
      final room = s.addTask('Paint room')..startAt = DateTime(2026, 11, 12);
      expect(s.addAfter(room, paint), isTrue);
      expect(s.addAfter(room, furniture), isTrue);
      expect(room.afterTaskId, paint.id, reason: 'older versions still see one');
      expect(room.afterIds, [paint.id, furniture.id]);
      expect(earliestStart(room, s.data), DateTime(2026, 11, 12));
      expect(clashes(room, s.data), isFalse);
      room.lagDays = 1;
      expect(clashes(room, s.data), isTrue);
      expect(linksAmong([paint, furniture, room], s.data).where((l) => l.clash).single.from, furniture);
      expect(s.addAfter(paint, room), isFalse, reason: 'no loops');
      s.removeAfter(room, paint.id);
      expect(room.afterTaskId, furniture.id);
      expect(roundTrip(s.data).task(room.id)!.lagDays, 1);
    });

    test('it stays locked until everything it waits for is ticked off', () {
      final s = AppStore();
      final a = s.addTask('A'), b = s.addTask('B'), c = s.addTask('C');
      s.addAfter(c, a);
      s.addAfter(c, b);
      expect(s.data.isLocked(c), isTrue);
      s.complete(a);
      expect(s.data.isLocked(c), isTrue);
      expect(c.readyAt, isNull);
      s.complete(b);
      expect(s.data.isLocked(c), isFalse);
      expect(c.readyAt, isNotNull);
    });
  });

  group('moving on the chart', () {
    test('moving later works out how far the tasks after it must move, only as needed', () {
      final s = AppStore();
      final a = s.addTask('A')
        ..startAt = mon
        ..takesDays = 2
        ..gantt = true;
      final b = s.addTask('B')
        ..startAt = DateTime(2026, 11, 11)
        ..takesDays = 1
        ..gantt = true;
      final c = s.addTask('C')
        ..startAt = DateTime(2026, 11, 16)
        ..gantt = true;
      s.addAfter(b, a);
      s.addAfter(c, b);
      final plan = s.moveOnGantt(a, 2);
      expect(a.startAt, DateTime(2026, 11, 11));
      expect(plan, {b: 2}, reason: 'C has room to spare');
      s.pushLater(plan);
      expect(b.startAt, DateTime(2026, 11, 13));
      expect(clashes(c, s.data), isFalse);
    });

    test('dragging the end changes the length, or the due date when there is none', () {
      final s = AppStore();
      final t = s.addTask('T')
        ..startAt = mon
        ..takesDays = 2;
      s.resizeOnGantt(t, DateTime(2026, 11, 16));
      expect(t.takesDays, 6, reason: 'work days, the weekend skipped');
      final u = s.addTask('U')
        ..startAt = mon
        ..dueAt = DateTime(2026, 11, 10, 9);
      s.resizeOnGantt(u, DateTime(2026, 11, 12));
      expect(u.dueAt, DateTime(2026, 11, 12, 9));
    });

    test('putting it on the chart remembers the first plan', () {
      final s = AppStore();
      final t = s.addTask('T')
        ..startAt = mon
        ..takesDays = 3;
      s.setOnGantt(t, true);
      expect(t.planStart, mon);
      expect(t.planDue, DateTime(2026, 11, 11));
      s.moveOnGantt(t, 3);
      expect(t.planStart, mon, reason: 'the first plan stays');
    });
  });

  test('moving a card into In progress fills an empty start', () {
    final s = AppStore();
    final t = s.addTask('T', board: true);
    s.moveToStage(t, s.data.stages.firstWhere((x) => x.id == 'doing'), how: MoveHow.menu);
    expect(t.startAt, dayOf(DateTime.now()));
    final u = s.addTask('U', board: true)..startAt = mon;
    s.moveToStage(u, s.data.stages.firstWhere((x) => x.id == 'doing'), how: MoveHow.menu);
    expect(u.startAt, mon);
  });

  test('!gantt puts it on the chart', () {
    final s = AppStore();
    final p = parseInput('Plan the trip !gantt', s.data, DateTime.now());
    expect(p.title, 'Plan the trip');
    expect(p.gantt, isTrue);
    final t = s.addTask(p.title, gantt: p.gantt);
    expect(t.gantt, isTrue);
    expect(s.data.ganttTasks, [t]);
  });

  test('CSV carries the Gantt fields and comes-after links', () {
    final s = AppStore();
    final a = s.addTask('Order paint')..gantt = true;
    final b = s.addTask('Paint room')
      ..gantt = true
      ..startAt = DateTime(2026, 11, 12, 0)
      ..takesDays = 3
      ..countWeekends = true
      ..progress = 40;
    s.addAfter(b, a);
    final d = AppData();
    importCsvText(d, buildCsv(s.data));
    final back = d.active.firstWhere((t) => t.title == 'Paint room');
    expect(back.gantt, isTrue);
    expect(back.startAt, DateTime(2026, 11, 12));
    expect(back.takesDays, 3);
    expect(back.countWeekends, isTrue);
    expect(back.progress, 40);
    expect(back.afterTaskId, d.active.firstWhere((t) => t.title == 'Order paint').id);
  });

  test('a repeating task\'s next copy stays on the chart', () {
    final s = AppStore();
    final t = s.addTask('Monthly report')
      ..gantt = true
      ..dueAt = DateTime(2026, 11, 13, 17)
      ..startAt = DateTime(2026, 11, 9)
      ..takesDays = 5
      ..repeat = const Repeat(unit: RepeatUnit.month);
    final next = s.complete(t)!;
    expect(next.gantt, isTrue);
    expect(next.takesDays, 5);
    expect(next.startAt, DateTime(2026, 12, 9));
  });

  testWidgets('the page shows tasks on the chart and the ones that need dates', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppStore();
    final now = DateTime.now();
    s.addTask('Draft report')
      ..gantt = true
      ..startAt = now
      ..takesDays = 3;
    s.addTask('Clear garage').gantt = true;
    s.addTask('Not on it');
    await tester.pumpWidget(MaterialApp(home: GanttPage(store: s)));
    await tester.pumpAndSettle();
    expect(find.text('Draft report'), findsWidgets);
    expect(find.text('Needs dates (1)'), findsOneWidget);
    expect(find.text('Clear garage'), findsOneWidget);
    expect(find.text('Not on it'), findsNothing);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.text('Draft report'), findsWidgets);
  });

  testWidgets('narrow screens work too', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppStore();
    s.addTask('Draft report')
      ..gantt = true
      ..dueAt = DateTime.now().add(const Duration(days: 3));
    await tester.pumpWidget(MaterialApp(home: GanttPage(store: s)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Draft report'), findsWidgets);
  });
}
