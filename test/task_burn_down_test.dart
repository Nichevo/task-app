import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/gantt.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/task_burn_down.dart';

/// Item 86: a burn-down for one task's steps.
void main() {
  test('a task with steps and a due date burns down by steps, off the Gantt chart too', () {
    final s = AppStore();
    final t = s.addTask('Paint the hall')
      ..startAt = DateTime(2026, 11, 2)
      ..dueAt = DateTime(2026, 11, 11, 17);
    expect(t.gantt, isFalse);
    final a = s.addStep(t, 'Fill cracks');
    final b = s.addStep(t, 'Sand');
    s.addStep(t, 'Undercoat');
    s.addStep(t, 'Top coat');
    a
      ..done = true
      ..doneAt = DateTime(2026, 11, 3, 10);
    b
      ..done = true
      ..doneAt = DateTime(2026, 11, 5, 18);

    final burn = taskBurnDown(t, s.data, DateTime(2026, 11, 6, 9))!;
    expect(burn.start, DateTime(2026, 11, 2));
    expect(burn.end, DateTime(2026, 11, 11));
    expect(burn.total, 4);
    expect(burn.left, [4, 3, 3, 2, 2]); // 2nd to 6th
    expect(burn.now, 2);
    expect(burn.projected, isNotNull);
  });

  test('days of work: steps with their own days count them, the rest share what is left', () {
    final s = AppStore();
    final t = s.addTask('Fence')
      ..countWeekends = true
      ..startAt = DateTime(2026, 11, 2)
      ..takesDays = 10;
    s.addStep(t, 'Posts')
      ..startAt = DateTime(2026, 11, 2)
      ..takesDays = 4;
    s.addStep(t, 'Panels');
    s.addStep(t, 'Stain');
    final burn = taskBurnDown(t, s.data, DateTime(2026, 11, 3), unit: BurnUnit.days)!;
    expect(burn.total, 10); // 4 + (10 - 4) shared by 2
  });

  test('no burn-down with fewer than two steps or nothing to finish by', () {
    final s = AppStore();
    final one = s.addTask('One step')..dueAt = DateTime(2026, 12, 1);
    s.addStep(one, 'Only');
    expect(taskBurnDown(one, s.data, DateTime(2026, 11, 20)), isNull);

    final undated = s.addTask('No dates');
    s.addStep(undated, 'A');
    s.addStep(undated, 'B');
    expect(taskBurnDown(undated, s.data, DateTime(2026, 11, 20)), isNull);
  });

  testWidgets('the task page tile opens to the chart and switches to days of work', (tester) async {
    final s = AppStore();
    final now = DateTime.now();
    final t = s.addTask('Garage')
      ..startAt = now.subtract(const Duration(days: 3))
      ..dueAt = now.add(const Duration(days: 5));
    s.addStep(t, 'Clear').done = true;
    s.addStep(t, 'Shelves');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [TaskBurnDownTile(task: t, data: s.data)]))));
    expect(find.text('Burn-down'), findsOneWidget);
    await tester.tap(find.text('Burn-down'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Days of work'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
