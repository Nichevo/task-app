import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/widgets/task_block.dart';

// Monday 16 November 2026, 06:00.
final now = DateTime(2026, 11, 16, 6);

/// 1.12.5: the opened card: time bar, chips, short step list, one row of buttons.
void main() {
  test('chips show only what is set, most useful first', () {
    final t = Task.create('Finn – flea treatment')..dueAt = DateTime(2026, 11, 23, 18);
    expect(cardChips(t, now), isEmpty);
    t
      ..where = const TaskWhere('the vet')
      ..estimate = 15
      ..repeat = const Repeat(unit: RepeatUnit.month, every: 3);
    t.focus['2026-11-15'] = 20;
    final texts = cardChips(t, now, category: 'General').map((c) => c.text).toList();
    expect(texts, [
      'At the vet',
      'Takes 15 min · 20 min worked',
      'Repeats every 3 months, next 23 Feb 2027',
      'General',
    ]);
  });

  test('the next dated step comes first, red when overdue', () {
    final t = Task.create('CGM: plan test week');
    final a = TaskStep.create('Test 1')..dueAt = DateTime(2026, 11, 15, 7, 30);
    final b = TaskStep.create('Test 2')..dueAt = DateTime(2026, 11, 16, 7, 30);
    t.steps.addAll([b, a]);
    final first = cardChips(t, now).first;
    expect(first.text, 'Next: Test 1 · Yesterday 07:30 · overdue');
    expect(first.warn, isTrue);
    a.done = true;
    expect(cardChips(t, now).first.text, 'Next: Test 2 · Today 07:30');
  });

  test('dates read short', () {
    expect(shortWhen(DateTime(2026, 11, 16, 9), now), 'Today 09:00');
    expect(shortWhen(DateTime(2026, 11, 19, 9), now), 'Thu 19 09:00');
    expect(shortWhen(DateTime(2026, 11, 24, 18), now), 'Tue 24 Nov, 18:00');
    expect(daysFrom(DateTime(2026, 11, 24), now), 'in 8 days');
    expect(daysFrom(DateTime(2026, 11, 5), now), '11 days ago');
  });

  Future<void> pump(WidgetTester tester, Task t, {bool showCategory = true, VoidCallback? onBoard}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TaskBlock(
              task: t,
              color: const Color(0xFFDFD05E),
              expanded: true,
              onTap: () {},
              onOpen: () {},
              onWorked: () {},
              onPlan: () {},
              onBoard: onBoard,
              categoryName: 'General',
              showCategory: showCategory,
            ),
          ),
        ),
      ));

  testWidgets('steps: ticked folded, three open then "more", which opens the rest', (tester) async {
    final t = Task.create('CGM: plan test week')..dueAt = DateTime.now().add(const Duration(days: 8));
    t.steps.addAll([
      TaskStep.create('Put CGM on')..done = true,
      TaskStep.create('Baseline week')..done = true,
      for (var i = 1; i <= 7; i++) TaskStep.create('Test $i'),
    ]);
    await pump(tester, t, showCategory: false);
    expect(find.text('▸ 2 ticked'), findsOneWidget);
    expect(find.text('Put CGM on'), findsNothing);
    expect(find.text('Test 3'), findsOneWidget);
    expect(find.text('Test 4'), findsNothing);
    expect(find.text('▸ 4 more steps'), findsOneWidget);
    expect(find.text('General'), findsNothing, reason: 'the list is grouped by category');
    await tester.tap(find.text('▸ 4 more steps'));
    await tester.pump();
    expect(find.text('Test 7'), findsOneWidget);
    await tester.tap(find.text('▸ 2 ticked'));
    await tester.pump();
    expect(find.text('Put CGM on'), findsOneWidget);
  });

  testWidgets('the Board button only shows for a task on the board', (tester) async {
    final t = Task.create('Fix the gate');
    await pump(tester, t, onBoard: () {});
    expect(find.text('Board'), findsNothing);
    expect(find.text('Worked today'), findsOneWidget);
    expect(find.text('Plan time'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('No due date'), findsOneWidget);
    t.kanban = true;
    await pump(tester, t, onBoard: () {});
    expect(find.text('Board'), findsOneWidget);
  });
}
