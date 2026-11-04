import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/csv_import.dart';
import 'package:task_blocks/input_parse.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/matrix_page.dart';
import 'package:task_blocks/screens/search_page.dart';
import 'package:task_blocks/screens/settings_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/task_list.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

void main() {
  group('matrix (60)', () {
    test('box and waiting on survive JSON, and box names can be changed', () {
      final s = AppStore();
      final t = s.addTask('Book the venue', box: MatrixBox.delegate);
      s.setWaitingOn(t, '  Sam ');
      s.setBoxName(MatrixBox.doNow, 'Now');
      final d = roundTrip(s.data);
      expect(d.active.single.matrixBox, 'delegate');
      expect(d.active.single.waitingOn, 'Sam');
      expect(d.boxName(MatrixBox.doNow), 'Now');
      expect(d.boxName(MatrixBox.decide), 'Decide');
      s.setBoxName(MatrixBox.doNow, '');
      expect(s.data.matrixNames, isEmpty);
      expect(s.data.matrixTasks.single.id, t.id);
    });

    test('a repeat copies its box', () {
      final s = AppStore();
      final t = s.addTask('Pay rent', box: MatrixBox.decide, due: DateTime(2026, 11, 1, 9))
        ..repeat = Repeat(unit: RepeatUnit.month);
      expect(t.nextRepeat(DateTime(2026, 11, 1)).matrixBox, 'decide');
    });

    test('"Urgent?" shows only in a not-urgent box, when due within the days set', () {
      final s = AppStore();
      final now = DateTime(2026, 11, 3, 10);
      final t = s.addTask('Tax return', box: MatrixBox.decide, due: DateTime(2026, 11, 5, 9));
      expect(s.looksUrgent(t, now), isFalse, reason: 'off by default');
      s.setUrgentDays(3);
      expect(s.looksUrgent(t, now), isTrue);
      t.dueAt = DateTime(2026, 11, 20);
      expect(s.looksUrgent(t, now), isFalse);
      t
        ..dueAt = DateTime(2026, 11, 4)
        ..matrixBox = MatrixBox.doNow.id;
      expect(s.looksUrgent(t, now), isFalse, reason: 'Do is already urgent');
    });

    testWidgets('the page shows only tasks put on the matrix, in their boxes', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppStore();
      s.addTask('Fix the leak', box: MatrixBox.doNow);
      s.addTask('Plan the garden', box: MatrixBox.decide);
      s.addTask('Not on it');
      s.setBoxName(MatrixBox.delete, 'Drop');
      await tester.pumpWidget(MaterialApp(home: MatrixPage(store: s)));
      await tester.pumpAndSettle();
      expect(find.text('Fix the leak'), findsOneWidget);
      expect(find.text('Plan the garden'), findsOneWidget);
      expect(find.text('Not on it'), findsNothing);
      expect(find.textContaining('Drop'), findsWidgets);
    });

    testWidgets('Decide asks for a date when the task has none', (tester) async {
      final s = AppStore();
      final t = s.addTask('Learn Spanish');
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));
      final done = putInBox(ctx, s, t, MatrixBox.decide);
      await tester.pumpAndSettle();
      expect(find.text('When will you do it?'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(await done, isTrue);
      expect(t.matrixBox, 'decide');
      expect(t.dueAt, isNotNull);
    });
  });

  group('quick-add words (64)', () {
    test('!words put a task in a box, on the board, or star it, and come off the name', () {
      final d = AppData();
      final p = parseInput('Ring the plumber !do !star tomorrow', d, DateTime(2026, 11, 3, 10));
      expect(p.title, 'Ring the plumber');
      expect(p.box, MatrixBox.doNow);
      expect(p.star, isTrue);
      expect(p.due, isNotNull);
      expect(parseInput('Fence !board', d, DateTime(2026, 11, 3)).board, isTrue);
      expect(parseInput('Hire help !delegate', d, DateTime(2026, 11, 3)).box, MatrixBox.delegate);
      expect(parseInput('Say !hello', d, DateTime(2026, 11, 3)).title, 'Say !hello');
    });

    test('words follow a renamed box, can be changed by hand, or turned off', () {
      final s = AppStore();
      s.setBoxName(MatrixBox.doNow, 'Now');
      expect(quickWord(s.data, QuickWord.doBox), 'now');
      expect(parseInput('X !now', s.data, DateTime(2026, 11, 3)).box, MatrixBox.doNow);
      s.setQuickWord('star', '!fav');
      expect(parseInput('X !fav', s.data, DateTime(2026, 11, 3)).star, isTrue);
      expect(parseInput('X !star', s.data, DateTime(2026, 11, 3)).star, isFalse);
      s.setQuickWord('board', '');
      expect(quickWord(s.data, QuickWord.board), isNull);
      expect(parseInput('X !board', s.data, DateTime(2026, 11, 3)).title, 'X !board');
      s.setQuickWord('board', null);
      expect(quickWord(s.data, QuickWord.board), 'board');
      expect(roundTrip(s.data).quickWords, {'star': 'fav'});
    });

    test('a !word added task lands in the box, on the board and starred', () {
      final s = AppStore();
      final t = s.addTask('Fence', box: MatrixBox.decide, board: true, star: true);
      expect(t.matrixBox, 'decide');
      expect(t.kanban, isTrue);
      expect(t.starred, isTrue);
    });

    testWidgets('Settings lists every add-box word in its own section', (tester) async {
      final s = AppStore();
      await tester.pumpWidget(MaterialApp(home: SettingsPage(store: s)));
      await tester.scrollUntilVisible(find.text('Quick-add words'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Quick-add words'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('!delegate'), 100, scrollable: find.byType(Scrollable).first);
      expect(find.text('#category'), findsOneWidget);
      expect(find.text('!do'), findsOneWidget);
      expect(find.text('!decide'), findsOneWidget);
    });
  });

  group('categories that go on the board (67)', () {
    test('new tasks and tasks moved into the category go on the board, in its stage', () {
      final s = AppStore();
      s.addCategory('Work');
      final work = s.data.categories.single;
      final next = s.data.stages[1];
      s.setCategoryBoard(work, on: true, stageId: next.id, steps: true);
      final t = s.addTask('Write report', categoryId: work.id);
      expect(t.kanban, isTrue);
      expect(t.stageId, next.id);
      expect(t.stepsOnBoard, isTrue);
      final u = s.addTask('Other');
      expect(u.kanban, isFalse);
      s.setCategory(u, work.id);
      expect(u.kanban, isTrue);
      final d = roundTrip(s.data);
      expect(d.categories.single.boardByDefault, isTrue);
      expect(d.categories.single.boardStage, next.id);
    });

    test('"Put them on the board now" boards the open tasks already in it', () {
      final s = AppStore();
      s.addCategory('Work');
      final work = s.data.categories.single;
      s.addTask('A', categoryId: work.id);
      s.addTask('B', categoryId: work.id);
      s.addTask('C');
      s.setCategoryBoard(work, on: true);
      expect(s.offBoardIn(work), hasLength(2));
      s.boardAllIn(work);
      expect(s.offBoardIn(work), isEmpty);
      expect(s.data.active.where((t) => t.kanban), hasLength(2));
    });
  });

  group('deep search (65)', () {
    AppStore sample() {
      final s = AppStore();
      s.addCategory('Garden');
      final t = s.addTask('Call the Café owner', categoryId: s.data.categories.single.id)
        ..notes = 'About the outdoor tables'
        ..waitingOn = 'Priya';
      t.steps.add(TaskStep.create('Measure the patio'));
      t.emails.add(TaskEmail(id: 'm1', subject: 'Quote for tables', from: 'Bob <bob@example.com>', snippet: 'Here is the price'));
      final old = Task.create('Repaint the shed')..closedAt = DateTime(2026, 10, 1);
      s.data.archived.add(old);
      return s;
    }

    test('looks in notes, steps, category, waiting on and emails, ignoring accents and order', () {
      final s = sample();
      final t = s.data.active.single;
      for (final q in ['cafe', 'CAFÉ', 'patio', 'garden', 'priya', 'bob@example', 'price', 'tables owner']) {
        expect(matchesSearch(t, q, s.data), isTrue, reason: q);
      }
      expect(matchesSearch(t, 'garden', null), isFalse, reason: 'category needs the data');
      expect(matchesSearch(t, '"outdoor tables"', s.data), isTrue);
      expect(matchesSearch(t, '"tables outdoor"', s.data), isFalse);
    });

    test('results are grouped, the archive included, and filters narrow them', () {
      final s = sample();
      var r = searchAll(s.data, 'patio');
      expect(r.tasks, hasLength(1));
      expect(r.steps.single.$2.title, 'Measure the patio');
      expect(r.emails, isEmpty);
      r = searchAll(s.data, 'quote');
      expect(r.emails.single.$2.id, 'm1');
      r = searchAll(s.data, 'shed');
      expect(r.archive.single.title, 'Repaint the shed');
      expect(searchAll(s.data, 'shed', filters: {SearchFilter.open}).count, 0);
      expect(searchAll(s.data, 'cafe', filters: {SearchFilter.starred}).count, 0);
      expect(searchAll(s.data, 'cafe', categoryId: s.data.categories.single.id).tasks, hasLength(1));
      expect(searchAll(s.data, '').count, 0);
    });

    test('match ranges point at the original text, accents and all', () {
      expect(matchRanges('Call the Café owner', ['cafe']), [(9, 13)]);
      expect(matchRanges('aaa', ['a']), [(0, 3)]);
      expect(matchRanges('Tables and tables', ['tables']), [(0, 6), (11, 17)]);
      expect(searchTerms('"outdoor  tables" cafe'), ['outdoor  tables', 'cafe']);
    });

    testWidgets('the search page shows groups with counts', (tester) async {
      final s = sample();
      await tester.pumpWidget(MaterialApp(home: SearchPage(store: s, initialQuery: 'the')));
      await tester.pumpAndSettle();
      expect(find.text('Tasks (1)'), findsOneWidget);
      expect(find.text('Steps (1)'), findsOneWidget);
      expect(find.text('Archive (1)'), findsOneWidget);
    });
  });

  test('CSV export and import carry the matrix box and waiting on (63)', () {
    final s = AppStore();
    s.setBoxName(MatrixBox.delegate, 'Hand off');
    s.addTask('Book the venue', box: MatrixBox.delegate).waitingOn = 'Sam';
    final csv = buildCsv(s.data);
    expect(csv.split('\r\n')[1], contains(',Hand off,Sam,'));
    final d = AppData(matrixNames: {'delegate': 'Hand off'});
    importCsvText(d, csv);
    expect(d.active.single.matrixBox, 'delegate');
    expect(d.active.single.waitingOn, 'Sam');
    // The standard names are understood too.
    final e = AppData();
    importCsvText(e, csv.replaceAll('Hand off', 'Delegate'));
    expect(e.active.single.matrixBox, 'delegate');
  });
}
