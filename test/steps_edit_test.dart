import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/steps_edit_page.dart';
import 'package:task_blocks/screens/task_page.dart';
import 'package:task_blocks/step_bulk.dart';
import 'package:task_blocks/store.dart';

void main() {
  group('edit all steps (80)', () {
    test('line up puts open steps one after another, skipping weekends', () {
      // Tue 24 Nov 2026.
      final a = TaskStep.create('Fit cabinets')..takesDays = 3;
      final b = TaskStep.create('Worktop')..dueAt = DateTime(2026, 12, 4, 17);
      final done = TaskStep.create('Measure')..done = true;
      final c = TaskStep.create('Tiling');
      final plan = planLineUp([a, done, b, c], from: DateTime(2026, 11, 24), weekends: false);
      expect(plan.map((p) => p.step), [a, b, c]);
      expect(plan[0].start, DateTime(2026, 11, 24));
      expect(plan[0].end, DateTime(2026, 11, 26));
      expect(plan[1].start, DateTime(2026, 11, 27)); // Friday
      expect(plan[2].start, DateTime(2026, 11, 30)); // Monday, not Saturday
      applyLineUp(plan);
      expect(a.startAt, DateTime(2026, 11, 24));
      expect(a.dueAt, DateTime(2026, 11, 26, 17)); // filled in
      expect(b.dueAt, DateTime(2026, 12, 4, 17)); // kept
      expect(b.takesDays, 1);
      expect(done.startAt, isNull);
    });

    test('a gap counts working days, and "set all" overwrites due dates', () {
      final a = TaskStep.create('A');
      final b = TaskStep.create('B')..dueAt = DateTime(2026, 12, 20, 9);
      // Thu 26 Nov; A ends Thu, one free working day (Fri), B starts Mon 30.
      final plan = planLineUp([a, b], from: DateTime(2026, 11, 26), weekends: false, gap: 1);
      expect(plan[1].start, DateTime(2026, 11, 30));
      applyLineUp(plan, due: LineUpDue.setAll);
      expect(b.dueAt, DateTime(2026, 11, 30, 17));
      // With weekends counted the free day is Friday and B starts Saturday.
      final withWeekends = planLineUp([a, b], from: DateTime(2026, 11, 26), weekends: true, gap: 1);
      expect(withWeekends[1].start, DateTime(2026, 11, 28));
    });

    test('move dates shifts start and due, and undo restores the steps', () {
      final t = Task.create('Kitchen');
      final s = TaskStep.create('Plumbing')
        ..startAt = DateTime(2026, 11, 19)
        ..dueAt = DateTime(2026, 11, 20, 9);
      final bare = TaskStep.create('Tiling');
      t.steps.addAll([s, bare]);
      final snap = snapshotSteps(t);
      moveStepDates(t.steps, 3);
      expect(s.startAt, DateTime(2026, 11, 22));
      expect(s.dueAt, DateTime(2026, 11, 23, 9));
      expect(bare.startAt, isNull);
      t.steps.removeAt(1);
      restoreSteps(t, snap);
      expect(t.steps.map((x) => x.title), ['Plumbing', 'Tiling']);
      expect(t.steps.first.startAt, DateTime(2026, 11, 19));
    });

    testWidgets('the screen lists every step and shows the bar once some are ticked', (tester) async {
      final store = AppStore();
      final t = store.addTask('Kitchen');
      store.addStep(t, 'Measure up');
      store.addStep(t, 'Order cabinets');
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: StepsEditPage(store: store, task: t)));
      // Once in the table and once beside the timeline under it.
      expect(find.text('Measure up'), findsNWidgets(2));
      expect(find.text('Order cabinets'), findsNWidgets(2));
      expect(find.text('Line up in order'), findsNothing);
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Line up in order'), findsOneWidget);
      await tester.tap(find.text('Line up in order'));
      await tester.pumpAndSettle();
      expect(find.text('Line up 1 step'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Line up'));
      await tester.pumpAndSettle();
      expect(t.steps.first.startAt, isNotNull);
      expect(t.steps.first.dueAt, isNotNull);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(t.steps.first.startAt, isNull);
    });

    testWidgets('folded: cards and a bottom bar', (tester) async {
      final store = AppStore();
      final t = store.addTask('Kitchen');
      store.addStep(t, 'Measure up');
      store.addStep(t, 'Order cabinets');
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: StepsEditPage(store: store, task: t)));
      expect(find.text('Select all'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Line up'), findsOneWidget);
    });

    testWidgets('start dates can be set on a task that is not on the Gantt chart', (tester) async {
      final store = AppStore();
      final t = store.addTask('Kitchen');
      store.addStep(t, 'Measure up');
      store.addStep(t, 'Order cabinets');
      expect(t.gantt, isFalse);
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: StepsEditPage(store: store, task: t)));
      expect(find.widgetWithText(ActionChip, 'Start'), findsNWidgets(2));
      expect(find.widgetWithText(ActionChip, 'Days'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(ActionChip, 'Start').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(t.steps.first.startAt, isNotNull);
      expect(t.steps.last.startAt, isNull);
    });

    testWidgets('unfolded: Starts column shows for a task that is not on the Gantt chart', (tester) async {
      final store = AppStore();
      final t = store.addTask('Kitchen');
      store.addStep(t, 'Measure up');
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: StepsEditPage(store: store, task: t)));
      expect(find.text('STARTS'), findsOneWidget);
      expect(find.text('Set start'), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
    });

    testWidgets('a narrow task pane keeps the checklist title on one line', (tester) async {
      final store = AppStore();
      final t = store.addTask('CGM: plan test week');
      store.addStep(t, 'Test 1');
      store.addStep(t, 'Test 2');
      tester.view.physicalSize = const Size(300, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: TaskPage(store: store, task: t)));
      await tester.pump();
      expect(find.byTooltip('Edit all steps'), findsOneWidget);
      final title = tester.getSize(find.text('Checklist  0/2'));
      expect(title.height, lessThan(30));
    });

    testWidgets('folded: the timeline preview shows for a Gantt task', (tester) async {
      final store = AppStore();
      final t = store.addTask('Kitchen')..gantt = true;
      store.addStep(t, 'Measure up').startAt = DateTime.now();
      store.addStep(t, 'Order cabinets').takesDays = 2;
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: StepsEditPage(store: store, task: t)));
      expect(find.text('How it looks on the Gantt chart'), findsOneWidget);
    });
  });
}
