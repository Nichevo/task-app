import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/kanban_page.dart';
import 'package:task_blocks/screens/task_page.dart';
import 'package:task_blocks/stats.dart';
import 'package:task_blocks/store.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

/// Item 56: checklist steps on the Kanban board.
void main() {
  KanbanStage st(AppStore s, String id) => s.data.stage(id)!;

  (AppStore, Task) withSteps() {
    final s = AppStore();
    final t = s.addTask('Renew insurance');
    for (final name in ['Get quotes', 'Compare cover', 'Pay']) {
      s.addStep(t, name);
    }
    s.setOnBoard(t, true, stage: s.data.stage('next'));
    return (s, t);
  }

  test('off by default; switching on puts each step in the first stage, ticked ones in the last', () {
    final (s, t) = withSteps();
    expect(t.stepsOnBoard, isFalse);
    expect(t.boardSteps, isEmpty);
    s.toggleStep(t, t.steps.first);
    s.setStepsOnBoard(t, true);
    expect(t.boardSteps.length, 3);
    expect(t.steps.map((x) => x.stageId), ['done', 'backlog', 'backlog']);
    expect(t.steps.every((x) => x.placed), isTrue);
    // A new step joins the board in the first stage.
    final added = s.addStep(t, 'Print certificate');
    expect(added.stageId, 'backlog');
    expect(added.moves.single.how, MoveHow.added);
  });

  test('steps move on their own; the last stage ticks them and leaving it unticks', () {
    final (s, t) = withSteps();
    s.setStepsOnBoard(t, true);
    final quotes = t.steps[0];
    expect(s.moveStepToStage(t, quotes, st(s, 'doing'), how: MoveHow.dragged, note: 'rang two'), isFalse);
    expect(t.stageId, 'next'); // the task stays where it was
    expect(
      (quotes.moves.last.fromName, quotes.moves.last.toName, quotes.moves.last.note),
      ('Backlog', 'In progress', 'rang two'),
    );
    s.moveStepToStage(t, quotes, st(s, 'done'), how: MoveHow.dragged);
    expect(quotes.done, isTrue);
    s.moveStepToStage(t, quotes, st(s, 'blocked'), how: MoveHow.menu);
    expect(quotes.done, isFalse);
    // Ticking the others in the checklist sends them to the last stage; the last one finishes it.
    s.toggleStep(t, t.steps[1]);
    expect(t.steps[1].stageId, 'done');
    expect(s.moveStepToStage(t, quotes, st(s, 'done'), how: MoveHow.menu), isFalse);
    expect(s.moveStepToStage(t, t.steps[2], st(s, 'done'), how: MoveHow.menu), isTrue);
    // Unticking in the checklist goes back to where it came from.
    s.toggleStep(t, quotes);
    expect(quotes.stageId, 'blocked');
    expect(quotes.moves.last.how, MoveHow.reopened);
  });

  test('taking the task off the board takes its steps off, and back on returns them', () {
    final (s, t) = withSteps();
    s.setStepsOnBoard(t, true);
    s.moveStepToStage(t, t.steps[1], st(s, 'doing'), how: MoveHow.menu);
    s.setOnBoard(t, false);
    expect(t.boardSteps, isEmpty);
    expect(t.steps.any((x) => x.placed), isFalse);
    s.setOnBoard(t, true);
    expect(t.steps[1].stageId, 'doing');
    expect(t.steps.every((x) => x.placed), isTrue);
    // Switching steps off keeps the task on the board.
    s.setStepsOnBoard(t, false);
    expect(t.kanban, isTrue);
    expect(t.steps.any((x) => x.placed), isFalse);
  });

  test('skip and repeat start the steps again in the first stage; undo puts them back', () {
    final (s, t) = withSteps();
    t.repeat = const Repeat(unit: RepeatUnit.week, every: 1);
    t.dueAt = DateTime(2026, 11, 6, 9);
    s.setStepsOnBoard(t, true);
    s.moveStepToStage(t, t.steps[0], st(s, 'done'), how: MoveHow.menu);
    final undo = s.skip(t);
    expect(t.steps.map((x) => (x.stageId, x.done)), everyElement(('backlog', false)));
    undo();
    expect((t.steps[0].stageId, t.steps[0].done), ('done', true));

    final next = s.complete(t)!;
    expect(next.stepsOnBoard, isTrue);
    expect(next.boardSteps.map((x) => x.stageId), everyElement('backlog'));
  });

  test('removing a stage moves its steps; ticking a linked task ticks its board step', () {
    final (s, t) = withSteps();
    s.setStepsOnBoard(t, true);
    s.moveStepToStage(t, t.steps[0], st(s, 'blocked'), how: MoveHow.menu);
    s.deleteStage(st(s, 'blocked'), st(s, 'next'));
    expect(t.steps[0].stageId, 'next');
    expect(t.steps[0].moves.last.how, MoveHow.stageRemoved);

    final linked = s.stepToTask(t, t.steps[1]);
    s.complete(linked);
    expect(t.steps[1].done, isTrue);
    expect(t.steps[1].stageId, 'done');
  });

  test('JSON and sync keep every step move from both devices', () {
    final (s, t) = withSteps();
    s.setStepsOnBoard(t, true);
    final phone = roundTrip(s.data);
    final desk = roundTrip(s.data);
    final p = phone.active.single, d = desk.active.single;
    expect(p.stepsOnBoard, isTrue);
    p.steps[0].moves.add(
      StageMove.create(from: phone.stage('backlog'), to: phone.stage('doing'), at: DateTime.now(), how: MoveHow.swiped),
    );
    p.steps[0].stageId = 'doing';
    p.updatedAt = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    d.steps[2].moves.add(
      StageMove.create(
        from: desk.stage('backlog'),
        to: desk.stage('blocked'),
        at: DateTime.now(),
        how: MoveHow.dragged,
      ),
    );
    d.steps[2].stageId = 'blocked';
    d.touch(); // the desk copy is newer and wins the task, but the phone's step move is kept
    final merged = mergeData(phone, desk).active.single;
    expect(merged.steps[0].stageId, 'doing');
    expect(merged.steps[0].moves.length, 2);
    expect(merged.steps[2].stageId, 'blocked');
  });

  test('statistics count steps apart, and kanban_moves.csv has a row per step move', () {
    final (s, t) = withSteps();
    s.setStepsOnBoard(t, true);
    final quotes = t.steps[0];
    final start = DateTime(2026, 11, 1, 9);
    quotes.moves
      ..clear()
      ..add(StageMove(id: 'a', toId: 'backlog', toName: 'Backlog', at: start, how: MoveHow.added))
      ..add(
        StageMove(
          id: 'b',
          fromId: 'backlog',
          fromName: 'Backlog',
          toId: 'doing',
          toName: 'In progress',
          at: start.add(const Duration(hours: 2)),
          how: MoveHow.dragged,
        ),
      );
    final k = Stats(s.data, DateTime(2026, 11, 8)).kanban(null)!;
    expect(k.steps, isNotNull);
    expect(k.steps!.firstWhere((r) => r.stage.id == 'backlog').count, 1);
    expect(k.stepMovesPerWeek, greaterThan(0));
    // Task time per stage isn't mixed with steps.
    expect(k.stages.firstWhere((r) => r.stage.id == 'backlog').count, 0);

    final lines = buildMovesCsv(s.data)!.trim().split('\r\n');
    expect(lines.where((l) => l.startsWith('Renew insurance,Get quotes,Backlog,In progress,')), hasLength(1));
  });

  group('board screen', () {
    testWidgets('wide: steps folded into a chip, unfolded under their task and grouped elsewhere', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (s, t) = withSteps();
      s.setStepsOnBoard(t, true);
      s.moveStepToStage(t, t.steps[1], st(s, 'next'), how: MoveHow.menu);
      await tester.pumpWidget(MaterialApp(home: KanbanPage(store: s)));
      expect(find.text('3 steps: 1 under way, 0 done'), findsOneWidget);
      expect(find.text('Get quotes'), findsNothing);

      await tester.tap(find.text('3 steps: 1 under way, 0 done'));
      await tester.pumpAndSettle();
      expect(find.text('Hide 3 steps'), findsOneWidget);
      expect(find.text('Compare cover'), findsOneWidget); // under its task in Up next
      expect(find.text('Renew insurance · 2 steps here'), findsOneWidget); // grouped in Backlog
      expect(find.text('Get quotes'), findsOneWidget);

      // Lanes: a row for the task with all its steps.
      await tester.tap(find.byTooltip('Lanes: a row for each task with steps'));
      await tester.pumpAndSettle();
      expect(s.boardLanes, isTrue);
      expect(find.text('3 steps · 0 done'), findsOneWidget);
      expect(find.text('Pay'), findsOneWidget);
    });

    testWidgets('moving the task to Done with open steps asks first', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (s, t) = withSteps();
      s.data.kanbanDone = KanbanDone.never;
      s.setStepsOnBoard(t, true);
      await tester.pumpWidget(MaterialApp(home: KanbanPage(store: s)));
      await tester.tap(find.byTooltip('Move to…, take off the board'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('3 steps are still open'), findsOneWidget);
      await tester.tap(find.text('Tick them all'));
      await tester.pumpAndSettle();
      expect(t.stageId, 'done');
      expect(t.steps.every((x) => x.done && x.stageId == 'done'), isTrue);
    });

    testWidgets('narrow: an unfolded task shows all its steps with their stage', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final (s, t) = withSteps();
      s.setStepsOnBoard(t, true);
      s.setBoardView(showSteps: true);
      await tester.pumpWidget(MaterialApp(home: KanbanPage(store: s)));
      expect(find.text('Backlog 0·3'), findsOneWidget);
      await tester.tap(find.text('Up next 1'));
      await tester.pumpAndSettle();
      expect(find.text('Pay'), findsOneWidget);
      expect(find.textContaining('step 3 of 3 · Backlog'), findsOneWidget);
    });

    testWidgets('task page switch puts the steps on the board', (tester) async {
      final s = AppStore();
      final t = s.addTask('Tidy garage');
      s.addStep(t, 'Sort tools');
      s.setOnBoard(t, true);
      await tester.pumpWidget(
        MaterialApp(
          home: TaskPage(store: s, task: t),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Steps on the board too'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Steps on the board too'));
      await tester.pumpAndSettle();
      expect(t.stepsOnBoard, isTrue);
      expect(t.steps.single.stageId, 'backlog');
    });
  });
}
