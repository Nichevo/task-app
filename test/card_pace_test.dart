import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/pace.dart';
import 'package:task_blocks/screens/kanban_page.dart';
import 'package:task_blocks/screens/search_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/task_list.dart';

/// Item 96: card shading and the pace verdict (behind, on pace, ahead).
void main() {
  final start = DateTime(2026, 11, 1, 9);
  final due = DateTime(2026, 11, 11, 9); // ten days later

  Task task({int steps = 0, int ticked = 0, int? progress, DateTime? dueAt}) {
    final t = Task(id: 't', title: 'Renew insurance', createdAt: start, dueAt: dueAt ?? due)..progress = progress;
    for (var i = 0; i < steps; i++) {
      t.steps.add(TaskStep(id: 's$i', title: 'step $i', done: i < ticked));
    }
    return t;
  }

  test('time used runs from the start to the due date and past 1 when overdue', () {
    expect(timeUsed(start, due, start), 0);
    expect(timeUsed(start, due, DateTime(2026, 11, 6, 9)), closeTo(0.5, 1e-9));
    expect(timeUsed(start, due, DateTime(2026, 11, 13, 9)), closeTo(1.2, 1e-9));
    expect(timeUsed(start, null, start), isNull);
  });

  test('steps: half a step either way is on pace', () {
    final day6 = DateTime(2026, 11, 7, 9); // 60% of the time gone, 3 of 5 steps expected
    expect(taskPace(task(steps: 5, ticked: 3), day6).verdict, Pace.onPace);
    final behind = taskPace(task(steps: 5, ticked: 1), day6);
    expect(behind.verdict, Pace.behind);
    expect(behind.label, 'Behind by 2 steps');
    expect(taskPace(task(steps: 5, ticked: 5), day6).verdict, Pace.ahead);
  });

  test('half-done steps count for their progress', () {
    final t = task(steps: 2, ticked: 1);
    t.steps[1].progress = 50;
    final p = taskPace(t, DateTime(2026, 11, 8, 9));
    expect(p.done, closeTo(0.75, 1e-9));
    expect(p.verdict, Pace.onPace);
  });

  test('progress set by hand: ten percent either way is on pace', () {
    final day5 = DateTime(2026, 11, 6, 9);
    expect(taskPace(task(progress: 45), day5).verdict, Pace.onPace);
    expect(taskPace(task(progress: 30), day5).verdict, Pace.behind);
    expect(taskPace(task(progress: 70), day5).verdict, Pace.ahead);
    expect(taskPace(task(progress: 30), day5).label, 'Behind');
  });

  test('overdue is behind; nothing to measure and not overdue has no verdict', () {
    final late = DateTime(2026, 11, 12, 9);
    expect(taskPace(task(), late).label, 'Overdue');
    expect(taskPace(task(), DateTime(2026, 11, 6, 9)).verdict, isNull);
    final noDue = Task(id: 'n', title: 'x', createdAt: start)..steps.add(TaskStep(id: 'a', title: 'a'));
    expect(taskPace(noDue, late).verdict, isNull);
    expect(taskPace(noDue, late).done, 0);
  });

  test('a Gantt start day counts from that day; off the chart it is ignored', () {
    final t = task(steps: 4, ticked: 0)
      ..gantt = true
      ..startAt = DateTime(2026, 11, 9);
    expect(taskPace(t, DateTime(2026, 11, 8, 12)).used, lessThan(0));
    expect(taskPace(t, DateTime(2026, 11, 8, 12)).verdict, Pace.ahead);
    t.gantt = false; // moving into In progress fills in startAt; that alone doesn't restart the clock
    expect(taskPace(t, DateTime(2026, 11, 8, 12)).verdict, Pace.behind);
  });

  test('a step uses its own due date and progress', () {
    final t = task(steps: 2);
    final st = t.steps[0]
      ..dueAt = DateTime(2026, 11, 6, 9)
      ..progress = 20;
    final p = stepPace(t, st, DateTime(2026, 11, 4, 9)); // 60% of its time gone
    expect(p.verdict, Pace.behind);
    expect(stepPace(t, t.steps[1], DateTime(2026, 11, 4, 9)).verdict, isNull);
    st.done = true;
    expect(stepPace(t, st, DateTime(2026, 11, 4, 9)).verdict, isNull);
  });

  test('the Behind filter in the list, board and matrix chips and in search', () {
    final now = DateTime.now();
    final behind = Task.create('late one')..dueAt = now.subtract(const Duration(hours: 1));
    final fine = Task.create('fine one')..dueAt = now.add(const Duration(days: 5));
    expect(passesFilter(behind, QuickFilter.behind, now), isTrue);
    expect(passesFilter(fine, QuickFilter.behind, now), isFalse);

    final data = AppData()..active.addAll([behind, fine]);
    final r = searchAll(data, 'one', filters: {SearchFilter.behind});
    expect(r.tasks.map((t) => t.title), ['late one']);
  });

  test('the shading setting is kept and defaults to On pace', () {
    expect(AppData().cardShading, CardShading.pace);
    expect(AppData().toJson().containsKey('cardShading'), isFalse);
    final d = AppData()..cardShading = CardShading.bars;
    expect(AppData.fromJson(d.toJson()).cardShading, CardShading.bars);
  });

  for (final shading in CardShading.values) {
    testWidgets('the board draws with ${shading.name} shading, steps unfolded', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppStore();
      s.data.cardShading = shading;
      final now = DateTime.now();
      final t = s.addTask('Renew insurance')..dueAt = now.add(const Duration(days: 3));
      for (final (i, name) in ['Get quotes', 'Compare cover', 'Pay'].indexed) {
        t.steps.add(TaskStep(id: 's$i', title: name, done: i == 0));
      }
      t.steps[1]
        ..progress = 40
        ..dueAt = now.add(const Duration(days: 1));
      s.setOnBoard(t, true, stage: s.data.stage('doing'));
      s.setStepsOnBoard(t, true);
      s.addTask('Late one').dueAt = now.subtract(const Duration(hours: 2));
      s.setOnBoard(s.data.active.firstWhere((x) => x.title == 'Late one'), true, stage: s.data.stage('doing'));
      await tester.pumpWidget(MaterialApp(home: KanbanPage(store: s)));
      await tester.tap(find.textContaining('3 steps:'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Compare cover'), findsOneWidget);
      switch (shading) {
        case CardShading.bars:
          expect(find.text('Steps'), findsOneWidget);
          expect(find.text('overdue'), findsOneWidget);
          expect(find.text('Overdue'), findsNWidgets(2)); // the filter chip and the card's verdict
        case CardShading.pace:
          expect(find.text('1 of 3 steps'), findsOneWidget);
          expect(find.text('Overdue'), findsNWidgets(2)); // the filter chip and the card's verdict
        case CardShading.fill:
          expect(find.text('Overdue'), findsNWidgets(2)); // the filter chip and the card's verdict
        case CardShading.off:
          expect(find.text('Overdue'), findsOneWidget); // only the filter chip
      }
    });
  }
}
