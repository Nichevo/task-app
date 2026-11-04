import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/achievements.dart';
import 'package:task_blocks/gantt.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/achievements_page.dart';
import 'package:task_blocks/screens/gantt_page.dart';
import 'package:task_blocks/screens/task_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/worked_week.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

// Wednesday 11 November 2026; last week ran Monday 2 to Sunday 8 November.
final wed = DateTime(2026, 11, 11, 12);

/// Items 75 (days worked), 76 (Achievements) and 77 (burn-down and chart widgets).
void main() {
  group('days worked (75)', () {
    test('ticking a day keeps the task open, counts the week and survives a sync', () {
      final s = AppStore();
      final t = s.addTask('Write report', board: true);
      final stage = t.stageId;
      expect(s.toggleWorked(t, wed), isTrue);
      s.setWorked(t, DateTime(2026, 11, 9), true);
      s.setWorked(t, DateTime(2026, 11, 6), true);
      expect(t.closedAt, isNull);
      expect(t.stageId, stage, reason: 'ticking a day does not move the card');
      expect(t.workedInWeek(wed), 2);
      expect(roundTrip(s.data).task(t.id)!.worked, {'2026-11-06', '2026-11-09', '2026-11-11'});
      expect(s.toggleWorked(t, wed), isFalse);
      expect(t.workedOn(wed), isFalse);
    });

    test('the widgets get the last fortnight of days', () {
      final s = AppStore();
      final t = s.addTask('Write report')
        ..worked.addAll({'2026-10-01', '2026-11-10'});
      final j = jsonDecode(HomeWidgets.widgetJson(s.data, wed)) as Map<String, dynamic>;
      expect(j['today'], '2026-11-11');
      final row = (j['tasks'] as List).firstWhere((x) => x['id'] == t.id);
      expect(row['worked'], ['2026-11-10']);
    });
  });

  group('achievements (76)', () {
    AppStore setUp() {
      final s = AppStore();
      s.addCategory('Work');
      s.addCategory('Home');
      final work = s.data.categories.first.id, home = s.data.categories.last.id;
      final report = s.addTask('Report', categoryId: work)
        ..dueAt = DateTime(2026, 11, 5, 17)
        ..startAt = DateTime(2026, 11, 2)
        ..worked.addAll({'2026-11-02', '2026-11-03'});
      final st = s.addStep(report, 'Draft');
      st.done = true;
      st.doneAt = DateTime(2026, 11, 3, 10);
      s.complete(report, at: DateTime(2026, 11, 6, 9));
      s.addTask('Slides', categoryId: work).worked.addAll({'2026-11-04', '2026-11-10'});
      final shed = s.addTask('Shed', categoryId: home)..worked.add('2026-11-07');
      s.complete(shed, at: DateTime(2026, 11, 7, 15));
      return s;
    }

    test('last week, one category: done, steps, days, plan against actual, unfinished', () {
      final s = setUp();
      final a = Achievements(s.data, AchievePeriod.lastWeek, wed, categoryId: s.data.categories.first.id);
      expect(a.from, DateTime(2026, 11, 2));
      expect(a.to, DateTime(2026, 11, 9));
      expect(a.tasksDone, 1);
      expect(a.stepsTicked, 1);
      expect(a.daysWorked, 3, reason: '2, 3 and 4 November');
      final f = a.finished.single;
      expect(f.task.title, 'Report');
      expect(f.daysLate, 1);
      expect(planLine(f), 'due Thu 5 Nov, 1 day late');
      expect(f.actualStart, DateTime(2026, 11, 2));
      expect(a.unfinished.single.task.title, 'Slides');
      expect(a.unfinished.single.daysWorked, 1, reason: 'only the day inside last week');
      expect(a.asText(), contains('1 task done, 1 step ticked, 3 days worked'));
      expect(a.asText(), contains('- Slides: 1 day'));
    });

    test('all categories and this week', () {
      final s = setUp();
      expect(Achievements(s.data, AchievePeriod.lastWeek, wed).tasksDone, 2);
      final now = Achievements(s.data, AchievePeriod.thisWeek, wed);
      expect(now.tasksDone, 0);
      expect(now.daysWorked, 1);
    });

    testWidgets('the page shows the numbers and the lists', (tester) async {
      final s = AppStore();
      final t = s.addTask('Slides');
      s.toggleWorked(t, DateTime.now());
      await tester.pumpWidget(MaterialApp(home: AchievementsPage(store: s)));
      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();
      expect(find.text('days worked'), findsOneWidget);
      expect(find.text('Worked on, not finished (1)'), findsOneWidget);
      expect(find.text('Slides'), findsOneWidget);
    });
  });

  group('burn-down (77)', () {
    test('ideal, actual and the pace of the last two weeks', () {
      final s = AppStore();
      final a = s.addTask('A')
        ..gantt = true
        ..startAt = DateTime(2026, 11, 2)
        ..takesDays = 3;
      final b = s.addTask('B')
        ..gantt = true
        ..startAt = DateTime(2026, 11, 5)
        ..takesDays = 6;
      s.addStep(b, 'one');
      final two = s.addStep(b, 'two');
      two.done = true;
      two.doneAt = DateTime(2026, 11, 6, 9);
      s.complete(a, at: DateTime(2026, 11, 4, 16));
      final burn = burnDown(burnTasks(s.data, null), s.data, wed)!;
      expect(burn.start, DateTime(2026, 11, 2));
      expect(burn.end, DateTime(2026, 11, 12));
      expect(burn.total, 3, reason: 'task A, and the two steps of B');
      expect(burn.left.first, 3);
      expect(burn.left[2], 2, reason: 'A ticked on the 4th');
      expect(burn.now, 1);
      expect(burn.idealOn(DateTime(2026, 11, 12)), 0);
      // 2 done in the 10 days so far: 1 left takes 5 more days.
      expect(burn.projected, DateTime(2026, 11, 16));
      expect(burn.daysLate, 4);
      expect(burnSummary(burn), contains('4 days after the plan'));
      final days = burnDown(burnTasks(s.data, null), s.data, wed, unit: BurnUnit.days)!;
      expect(days.total, 9, reason: '3 days for A and 6 for B');
    });

    test('the widgets get the burn-down and Added vs done for each category', () {
      final s = AppStore();
      s.addCategory('Work');
      final id = s.data.categories.single.id;
      s.addTask('A', categoryId: id)
        ..gantt = true
        ..startAt = DateTime(2026, 11, 9)
        ..takesDays = 2;
      final j = jsonDecode(HomeWidgets.widgetJson(s.data, wed)) as Map<String, dynamic>;
      expect((j['burn'] as Map).keys, containsAll(['', id]));
      expect(j['burn'][id]['summary'], contains('1 task or step left'));
      expect((j['addedDone'][id]['added'] as List).length, 28);
    });

    testWidgets('the Gantt page has the burn-down strip', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppStore();
      s.addTask('Draft')
        ..gantt = true
        ..startAt = DateTime.now()
        ..takesDays = 3;
      await tester.pumpWidget(MaterialApp(home: GanttPage(store: s)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.trending_down));
      await tester.pumpAndSettle();
      expect(find.text('Burn-down'), findsOneWidget);
      await tester.tap(find.text('Days of work'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the task page shows the week to tick', (tester) async {
    final s = AppStore();
    final t = s.addTask('Slides');
    await tester.pumpWidget(MaterialApp(home: TaskPage(store: s, task: t)));
    await tester.scrollUntilVisible(find.text('Days worked on it'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byType(WorkedWeek));
    await tester.pumpAndSettle();
    final todayLetter = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][DateTime.now().weekday - 1];
    // T and S come twice in the week: pick the right one.
    final before = WorkedWeek.letters.sublist(0, DateTime.now().weekday - 1).where((l) => l == todayLetter).length;
    await tester.tap(find.descendant(of: find.byType(WorkedWeek), matching: find.text(todayLetter)).at(before));
    await tester.pumpAndSettle();
    expect(t.workedOn(DateTime.now()), isTrue);
    expect(find.textContaining('1 day this week'), findsOneWidget);
  });
}
