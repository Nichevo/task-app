import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/day_plan.dart';
import 'package:task_blocks/screens/day_plan_page.dart';
import 'package:task_blocks/store.dart';

DateTime at(int h, [int m = 0, int day = 16]) => DateTime(2026, 11, day, h, m);

/// 1.12.4: the "To plan" tray lists other open tasks and opens tasks to their steps; the week
/// arrows go to the start of the week.
void main() {
  test('other open tasks: due later and no date, soonest first; planned ones left out', () {
    final s = AppStore();
    final noDate = s.addTask('Clean gutters');
    final later = s.addTask('Renew rego')..dueAt = at(9, 0, 25);
    final sooner = s.addTask('Book flights')..dueAt = at(9, 0, 19);
    final dueToday = s.addTask('Call bank')..dueAt = at(15);
    final planned = s.addTask('Mow lawn');
    s.planTime(planned, at(9, 0, 18), 60);
    final tray = trayFor(s.data, at(0), at: at(8));
    final others = tray.where((i) => i.other).map((i) => i.task).toList();
    expect(others, [sooner, later, noDate]);
    expect(tray.firstWhere((i) => i.task == dueToday).other, isFalse);
    expect(tray.map((i) => i.task), isNot(contains(planned)));
    expect(tray.firstWhere((i) => i.task == noDate).why, 'No date');

    s.data.dayPlan.trayAll = false;
    expect(trayFor(s.data, at(0), at: at(8)).where((i) => i.other), isEmpty);
  });

  test('a task opens to its open steps that have no time that day', () {
    final s = AppStore();
    final t = s.addTask('Kitchen');
    final a = s.addStep(t, 'Measure'), b = s.addStep(t, 'Order worktops'), c = s.addStep(t, 'Fit');
    s.toggleStep(t, c);
    s.planTime(t, at(10), 30, step: a);
    final item = trayFor(s.data, at(0), at: at(8)).firstWhere((i) => i.task == t && i.step == null);
    expect(trayStepsOf(s.data, item, at(0)).map((i) => i.step), [b]);
    expect(trayStepsOf(s.data, item, at(0, 0, 17)).map((i) => i.step), [a, b]);
  });

  test('the week arrows open the next week on Monday, or today if it is that week', () {
    final sunday = at(0, 0, 15);
    expect(weekStartFrom(sunday, 1, today: sunday), at(0, 0, 16));
    expect(weekStartFrom(at(0, 0, 18), -1, today: sunday), sunday, reason: 'today is in the week before');
    expect(weekStartFrom(at(0, 0, 18), -1, today: at(0, 0, 30)), at(0, 0, 9));
    expect(weekStartFrom(at(0, 0, 18), 1, today: at(0, 0, 25)), at(0, 0, 25));
  });

  testWidgets('steps can be opened in the tray and dragged from there', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppStore();
    final t = s.addTask('Fence');
    s.addStep(t, 'Sand');
    s.addStep(t, 'Paint');
    await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s)));
    await tester.pump();
    expect(find.textContaining('more open'), findsOneWidget);
    expect(find.textContaining('Sand'), findsNothing);
    await tester.tap(find.textContaining('more open'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_right).last);
    await tester.pump();
    expect(find.textContaining('Sand'), findsOneWidget);
    expect(find.textContaining('Paint'), findsOneWidget);
  });
}
