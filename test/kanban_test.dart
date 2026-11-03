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

void main() {
  KanbanStage st(AppStore s, String id) => s.data.stage(id)!;

  test('old data files load with the default stages and no board tasks', () {
    final old = AppData(active: [Task.create('a')]).toJson()
      ..remove('stages')
      ..remove('kanbanDone');
    final d = AppData.fromJson(old);
    expect(d.stages.map((s) => s.name), ['Backlog', 'Up next', 'In progress', 'Blocked', 'Done']);
    expect(d.kanbanDone, KanbanDone.ask);
    expect(d.active.single.kanban, isFalse);
    expect(d.active.single.moves, isEmpty);
  });

  test('moves record from, to, how, device and note, and survive JSON', () {
    final s = AppStore();
    final t = s.addTask('Fix gate');
    s.setOnBoard(t, true);
    expect(t.kanban, isTrue);
    expect(t.stageId, 'backlog');
    expect(s.moveToStage(t, st(s, 'doing'), how: MoveHow.menu, note: ' waiting on parts '), isFalse);
    expect(s.moveToStage(t, st(s, 'doing'), how: MoveHow.menu), isFalse); // already there: no move
    expect(t.moves.length, 2);
    final m = t.moves.last;
    expect((m.fromName, m.toName, m.how, m.note, m.device), ('Backlog', 'In progress', MoveHow.menu, 'waiting on parts', AppStore.deviceName));

    // Renaming a stage later doesn't rewrite history.
    s.updateStage(st(s, 'doing'), name: 'Doing');
    final back = roundTrip(s.data).active.single;
    expect(back.kanban, isTrue);
    expect(back.stageId, 'doing');
    expect(back.moves.last.toName, 'In progress');
    expect(back.moves.last.note, 'waiting on parts');
    expect(back.moves.first.fromId, isNull);

    expect(s.moveToStage(t, st(s, 'done'), how: MoveHow.dragged), isTrue); // last stage
  });

  test('taking a task off the board keeps its history and it goes back to the same stage', () {
    final s = AppStore();
    final t = s.addTask('Paint shed');
    s.setOnBoard(t, true);
    s.moveToStage(t, st(s, 'blocked'), how: MoveHow.swiped);
    s.setOnBoard(t, false);
    expect(t.kanban, isFalse);
    expect(t.moves.last.toId, isNull);
    expect(t.moves.last.fromName, 'Blocked');
    expect(s.data.boardTasks, isEmpty);
    s.setOnBoard(t, true);
    expect(t.stageId, 'blocked');
    expect(t.moves.length, 4);
  });

  test('ticking off ends in the last stage, keeps minutes per stage; restore moves it back', () {
    final s = AppStore();
    final t = s.addTask('Order parts');
    s.setOnBoard(t, true);
    // Make the stage times known.
    t.moves.first = StageMove(id: 'a', toId: 'backlog', toName: 'Backlog', at: DateTime(2026, 11, 1, 9), how: MoveHow.added);
    t.moves.add(StageMove(
        id: 'b', fromId: 'backlog', toId: 'doing', toName: 'In progress', at: DateTime(2026, 11, 1, 10), how: MoveHow.dragged));
    t.stageId = 'doing';
    s.complete(t, at: DateTime(2026, 11, 1, 13));
    expect(t.stageId, 'done');
    expect(t.moves.last.how, MoveHow.done);
    expect(s.data.done[t.id]!.stageMinutes, {'backlog': 60, 'doing': 180, 'done': 0});
    expect(DoneRecord.fromJson(jsonDecode(jsonEncode(s.data.done[t.id]!.toJson()))).stageMinutes!['doing'], 180);

    s.restore(t);
    expect(t.stageId, 'doing');
    expect(t.moves.last.how, MoveHow.reopened);
  });

  test('the next copy of a repeating board task starts in the first stage', () {
    final s = AppStore();
    final t = s.addTask('Bins')
      ..dueAt = DateTime(2026, 11, 2, 8)
      ..repeat = const Repeat(unit: RepeatUnit.week);
    s.setOnBoard(t, true);
    s.moveToStage(t, st(s, 'doing'), how: MoveHow.menu);
    final next = s.complete(t)!;
    expect(next.kanban, isTrue);
    expect(next.stageId, 'backlog');
    expect(next.moves.single.how, MoveHow.repeat);
  });

  test('sync keeps moves made on both devices and takes the stage from the latest', () {
    final base = Task(id: 't', title: 'Car service', createdAt: DateTime(2026, 11, 1), kanban: true, stageId: 'backlog', moves: [
      StageMove(id: 'm0', toId: 'backlog', toName: 'Backlog', at: DateTime(2026, 11, 1, 9), how: MoveHow.added),
    ]);
    final phone = Task.fromJson(base.toJson())
      ..stageId = 'next'
      ..updatedAt = DateTime.utc(2026, 11, 1, 10);
    phone.moves.add(StageMove(id: 'p', fromId: 'backlog', toId: 'next', at: DateTime(2026, 11, 1, 10), how: MoveHow.swiped));
    final desk = Task.fromJson(base.toJson())
      ..stageId = 'doing'
      ..title = 'Car service (booked)'
      ..updatedAt = DateTime.utc(2026, 11, 1, 9, 30);
    desk.moves.add(StageMove(id: 'd', fromId: 'next', toId: 'doing', at: DateTime(2026, 11, 1, 11), how: MoveHow.dragged));

    final a = AppData(active: [phone]);
    final m = mergeData(a, AppData(active: [desk]));
    final t = m.active.single;
    expect(t.moves.map((x) => x.id), ['m0', 'p', 'd']);
    expect(t.stageId, 'doing'); // the latest move, made on the desktop
    expect(t.title, 'Car service'); // the rest from the newer copy, as before
    expect(a.active.single.moves.length, 2, reason: 'this device\'s copy is not changed by the merge');
  });

  test('removing a stage moves its tasks, as a recorded move', () {
    final s = AppStore();
    final t = s.addTask('Quote');
    s.setOnBoard(t, true, stage: st(s, 'blocked'));
    s.deleteStage(st(s, 'blocked'), st(s, 'next'));
    expect(s.data.stages.length, 4);
    expect(t.stageId, 'next');
    expect(t.moves.last.how, MoveHow.stageRemoved);
    expect(t.moves.last.fromName, 'Blocked');
  });

  test('statistics: time per stage, moves a week, backwards and longest waiting', () {
    final now = DateTime(2026, 11, 8);
    Task task(String id, List<(String?, String?, DateTime)> path, {bool board = true}) => Task(
          id: id,
          title: id,
          createdAt: DateTime(2026, 11, 1),
          kanban: board,
          stageId: path.last.$2 ?? path.last.$1,
          moves: [
            for (final (i, (from, to, at)) in path.indexed) StageMove(id: '$id$i', fromId: from, toId: to, at: at, how: MoveHow.menu),
          ],
        );
    final d = AppData(active: [
      task('a', [(null, 'backlog', DateTime(2026, 11, 2)), ('backlog', 'doing', DateTime(2026, 11, 3)), ('doing', 'next', DateTime(2026, 11, 4))]),
      task('b', [(null, 'backlog', DateTime(2026, 11, 5)), ('backlog', 'doing', DateTime(2026, 11, 7))]),
    ], done: {
      // Cleaned out of the archive: only its record is left.
      'gone': DoneRecord(at: DateTime(2026, 11, 6), tookMinutes: 0, stageMinutes: {'backlog': 3 * 1440}),
    });
    final k = Stats(d, now).kanban(DateTime(2026, 11, 1))!;
    final backlog = k.stages.firstWhere((r) => r.stage.id == 'backlog');
    expect(backlog.minutes, [1440, 2 * 1440, 3 * 1440]);
    expect(backlog.median, 2 * 1440);
    expect(k.stages.firstWhere((r) => r.stage.id == 'doing').minutes, [1440]);
    expect(k.backwards, 1); // a went from In progress back to Up next
    expect(k.movesPerWeek, 3); // three stage-to-stage moves in a week
    expect(k.longest.first.$1.id, 'a'); // in Up next since 4 Nov
    expect(Stats(AppData(), now).kanban(null), isNull);
  });

  test('CSV: Stage column and one row per move in kanban_moves.csv', () {
    final s = AppStore();
    final t = s.addTask('Fence');
    s.setOnBoard(t, true);
    s.moveToStage(t, st(s, 'doing'), how: MoveHow.dragged, note: 'started, see notes');
    expect(buildCsv(s.data).split('\r\n')[1], endsWith(',In progress,,,'));
    final lines = buildMovesCsv(s.data)!.trim().split('\r\n');
    expect(lines.first, 'Task,Step,Moved from,Moved to,When,Minutes in previous stage,How,Where,Device,Note');
    expect(lines.length, 3);
    expect(lines[2], contains('Fence,,Backlog,In progress,'));
    expect(lines[2], endsWith(',Dragged,,${AppStore.deviceName},"started, see notes"'));
    expect(buildMovesCsv(AppData()), isNull);
  });

  group('board screen', () {
    AppStore board() {
      final s = AppStore();
      final a = s.addTask('Sand the door');
      final b = s.addTask('Buy paint');
      s.addTask('Not on the board');
      s.setOnBoard(a, true);
      s.setOnBoard(b, true, stage: s.data.stage('doing'));
      return s;
    }

    testWidgets('narrow: one column at a time, arrow moves a card on', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final s = board();
      await tester.pumpWidget(MaterialApp(home: KanbanPage(store: s)));
      expect(find.text('Backlog 1'), findsOneWidget);
      expect(find.text('In progress 1'), findsOneWidget);
      expect(find.text('Sand the door'), findsOneWidget);
      expect(find.text('Not on the board'), findsNothing);

      await tester.tap(find.byTooltip('Move to Up next'));
      await tester.pumpAndSettle();
      final t = s.data.active.firstWhere((t) => t.title == 'Sand the door');
      expect(t.stageId, 'next');
      expect(t.moves.last.how, MoveHow.menu);
      expect(find.text('Backlog 0'), findsOneWidget);
    });

    testWidgets('wide: all columns side by side; moving into Done asks to tick off', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = board();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: KanbanPage(store: s))));
      for (final name in ['Backlog', 'Up next', 'In progress', 'Blocked', 'Done']) {
        expect(find.text(name), findsOneWidget);
      }
      final t = s.data.active.firstWhere((t) => t.title == 'Buy paint');
      // Cards in board order: Sand the door (Backlog), then Buy paint (In progress).
      await tester.tap(find.byTooltip('Move to…, take off the board').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('Tick it off too?'), findsOneWidget);
      await tester.tap(find.text('Tick off'));
      await tester.pumpAndSettle();
      expect(t.closedAt, isNotNull);
      expect(s.data.done[t.id]!.stageMinutes!.keys, containsAll(['doing', 'done']));
    });

    testWidgets('task page switch puts a task on the board and shows its history', (tester) async {
      final s = AppStore();
      final t = s.addTask('Tidy garage');
      await tester.pumpWidget(MaterialApp(home: TaskPage(store: s, task: t)));
      await tester.scrollUntilVisible(find.text('On the Kanban board'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('On the Kanban board'));
      await tester.pumpAndSettle();
      expect(t.kanban, isTrue);
      expect(find.textContaining('In Backlog'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Board history'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Board history'));
      await tester.pumpAndSettle();
      expect(find.text('Onto the board: Backlog'), findsOneWidget);
    });
  });
}
