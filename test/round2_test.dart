import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/csv_import.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';

void main() {
  group('repeats', () {
    test('fixed schedule steps on from the due date, past any missed ones', () {
      const r = Repeat(unit: RepeatUnit.week);
      final next = r.nextDue(due: DateTime(2026, 10, 1, 9), completedAt: DateTime(2026, 10, 20, 12));
      expect(next, DateTime(2026, 10, 22, 9));
    });

    test('after completion counts from when it was ticked, keeping the time of day', () {
      const r = Repeat(unit: RepeatUnit.day, every: 7, fromCompletion: true);
      final next = r.nextDue(due: DateTime(2026, 10, 1, 9), completedAt: DateTime(2026, 10, 20, 12));
      expect(next, DateTime(2026, 10, 27, 9));
    });

    test('weekly on chosen days and month ends', () {
      const r = Repeat(unit: RepeatUnit.week, weekdays: {DateTime.monday, DateTime.thursday});
      // Due Mon 26 Oct, done on time -> Thu 29 Oct.
      expect(r.nextDue(due: DateTime(2026, 10, 26, 8), completedAt: DateTime(2026, 10, 26, 9)),
          DateTime(2026, 10, 29, 8));
      const m = Repeat(unit: RepeatUnit.month);
      expect(m.nextDue(due: DateTime(2026, 1, 31), completedAt: DateTime(2026, 1, 31, 1)), DateTime(2026, 2, 28));
    });

    test('ticking a repeating task archives it and adds the next one in its place', () {
      final s = AppStore()
        ..addTask('a')
        ..addTask('Bins')
        ..addTask('c');
      final bins = s.data.active[1]
        ..dueAt = DateTime(2030, 1, 7, 9)
        ..repeat = const Repeat(unit: RepeatUnit.week);
      final next = s.complete(bins)!;
      expect(s.data.active.map((t) => t.title), ['a', 'Bins', 'c']);
      expect(s.data.active[1], same(next));
      expect(next.dueAt, bins.dueAt!.add(const Duration(days: 7)));
      expect(s.data.archived.single, same(bins));
      s.uncomplete(bins, 1, next);
      expect(s.data.active, [s.data.active[0], bins, s.data.active[2]]);
      expect(s.data.active.length, 3);
    });
  });

  test('linked task is locked until the earlier one is ticked, then starts green', () {
    final s = AppStore()
      ..addTask('Buy paint')
      ..addTask('Paint fence');
    final paint = s.data.active[1]..afterTaskId = s.data.active[0].id;
    expect(s.data.isLocked(paint), isTrue);
    s.complete(s.data.active[0]);
    expect(s.data.isLocked(paint), isFalse);
    expect(paint.readyAt, isNotNull);
    expect(paint.colourStart(DateTime.now().add(const Duration(seconds: 1))), paint.readyAt);
  });

  test('dragging in grouped view keeps hidden tasks in place and changes category', () {
    final s = AppStore();
    final work = s.addCategory('Work');
    for (final n in ['a', 'b', 'c', 'd']) {
      s.addTask(n);
    }
    final [a, b, c, d] = s.data.active;
    // b is hidden (e.g. collapsed); show d, a, c and move d into Work.
    s.reorderVisible([d, a, c], moved: d, categoryId: work.id);
    expect(s.data.active, [d, b, a, c]);
    expect(d.categoryId, work.id);
  });

  test('CSV import reads the export back, skipping ones already there', () {
    final s = AppStore();
    final home = s.addCategory('Home');
    s.addTask('Fix gate, latch');
    s.data.active.single
      ..categoryId = home.id
      ..starred = true
      ..notes = 'line 1\nline 2'
      ..dueAt = DateTime(2026, 11, 3, 17);
    final csv = buildCsv(s.data);

    final fresh = AppData();
    expect(importCsvText(fresh, csv), 1);
    final t = fresh.active.single;
    expect(t.title, 'Fix gate, latch');
    expect(t.notes, 'line 1\nline 2');
    expect(t.starred, isTrue);
    expect(t.dueAt, DateTime(2026, 11, 3, 17));
    expect(fresh.category(t.categoryId)!.name, 'Home');
    expect(importCsvText(fresh, csv), 0);
  });

  test('CSV import accepts Excel-style dates and a minimal file', () {
    final d = AppData();
    expect(importCsvText(d, 'Task,Due\r\nCall Sam,28/10/2026 17:30\r\nNo date,\r\n'), 2);
    expect(d.active.first.dueAt, DateTime(2026, 10, 28, 17, 30));
  });

  testWidgets('grouped view shows bold headings and collapses them', (tester) async {
    final s = AppStore();
    final work = s.addCategory('Work');
    s.addTask('Email boss');
    s.addTask('Mow lawn');
    s.data.active.first.categoryId = work.id;
    s.data.groupByCategory = true;
    await tester.pumpWidget(TaskApp(store: s));
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('No category'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pump();
    expect(find.text('Email boss'), findsNothing);
    expect(find.text('Mow lawn'), findsOneWidget);
  });

  testWidgets('30-day focus hides later tasks behind a link; snoozed tasks hide too', (tester) async {
    final s = AppStore()
      ..addTask('Soon')
      ..addTask('Far off')
      ..addTask('Sleeping');
    s.data.active[1].dueAt = DateTime.now().add(const Duration(days: 60));
    s.data.active[2].snoozedUntil = DateTime.now().add(const Duration(days: 2));
    s.data.focusNext30 = true;
    await tester.pumpWidget(TaskApp(store: s));
    expect(find.text('Soon'), findsOneWidget);
    expect(find.text('Far off'), findsNothing);
    expect(find.text('Sleeping'), findsNothing);
    await tester.tap(find.text('Due later (1)'));
    await tester.pump();
    expect(find.text('Far off'), findsOneWidget);
  });

  testWidgets('typing a date shows it and sets the due date', (tester) async {
    final s = AppStore();
    await tester.pumpWidget(TaskApp(store: s));
    await tester.enterText(find.byType(TextField), 'Call bank tomorrow 5pm');
    await tester.pump();
    expect(find.textContaining('Due '), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final t = s.data.active.single;
    expect(t.title, 'Call bank');
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(t.dueAt, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17));
  });

  testWidgets('starred tasks show first and notes show a preview', (tester) async {
    final s = AppStore()
      ..addTask('Plain')
      ..addTask('Important');
    s.data.active[1]
      ..starred = true
      ..notes = 'Ring before 10\nsecond line';
    await tester.pumpWidget(TaskApp(store: s));
    final y1 = tester.getTopLeft(find.text('Important')).dy;
    final y2 = tester.getTopLeft(find.text('Plain')).dy;
    expect(y1, lessThan(y2));
    expect(find.text('Ring before 10'), findsOneWidget);
  });
}
