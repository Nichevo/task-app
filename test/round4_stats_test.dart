import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/reminders.dart';
import 'package:task_blocks/screens/stats_page.dart';
import 'package:task_blocks/stats.dart';
import 'package:task_blocks/store.dart';

void main() {
  final now = DateTime(2026, 11, 2, 12);

  test('done records keep source, series, lateness and missed cycles, and survive JSON', () {
    final t = Task(id: 'b', title: 'Bins', createdAt: DateTime(2026, 10, 1), source: TaskSource.widget)
      ..dueAt = DateTime(2026, 10, 12, 8)
      ..repeat = const Repeat(unit: RepeatUnit.week);
    // Due 12 Oct, ticked 2 Nov at noon: the 19 Oct, 26 Oct and 2 Nov 8am repeats went by.
    final r = DoneRecord.of(t, now);
    expect(r.source, TaskSource.widget);
    expect(r.series, 'b');
    expect(r.missed, 3);
    expect(r.lateMinutes, now.difference(DateTime(2026, 10, 12, 8)).inMinutes);
    final back = DoneRecord.fromJson(jsonDecode(jsonEncode(r.toJson())));
    expect(back.missed, 3);
    expect(back.due, DateTime(2026, 10, 12, 8));
    expect(back.title, 'Bins');
  });

  test('30 by source counts added, done share and ticked off, including cleaned-up tasks', () {
    final d = AppData(
      active: [
        Task(id: 'a', title: 'a', createdAt: now.subtract(const Duration(days: 2)), source: TaskSource.typed),
        Task(id: 'c', title: 'c', createdAt: now.subtract(const Duration(days: 1)), source: TaskSource.calendar),
      ],
      archived: [
        Task(id: 'b', title: 'b', createdAt: now.subtract(const Duration(days: 3)), source: TaskSource.typed,
            closedAt: now.subtract(const Duration(days: 1))),
      ],
      done: {
        'b': DoneRecord(at: now.subtract(const Duration(days: 1)), tookMinutes: 2 * 1440, source: TaskSource.typed),
        // Archive clean-up already deleted this one.
        'gone': DoneRecord(at: now.subtract(const Duration(days: 4)), tookMinutes: 60, source: TaskSource.voice),
      },
    );
    final rows = {for (final r in Stats(d, now).bySource(now.subtract(const Duration(days: 7)))) r.source: r};
    expect(rows[TaskSource.typed]!.added, 2);
    expect(rows[TaskSource.typed]!.addedDone, 1);
    expect(rows[TaskSource.typed]!.share, 0.5);
    expect(rows[TaskSource.typed]!.done, 1);
    expect(rows[TaskSource.calendar]!.added, 1);
    expect(rows[TaskSource.voice]!.added, 1);
    expect(rows[TaskSource.voice]!.done, 1);
  });

  test('36 repeats count done, skipped and missed per series', () {
    final s = AppStore();
    final t = s.addTask('Bins')
      ..dueAt = DateTime(2026, 10, 19, 8)
      ..repeat = const Repeat(unit: RepeatUnit.week);
    // Skipped on 20 Oct (none missed); the 26 Oct one ticked off on 2 Nov 9am, after 2 Nov 8am went by.
    s.skip(t, at: DateTime(2026, 10, 20, 9));
    expect(t.dueAt, DateTime(2026, 10, 26, 8));
    final next = s.complete(t, at: DateTime(2026, 11, 2, 9))!;
    expect(next.series, t.id);
    final row = Stats(s.data, now).repeats(null).single;
    expect(row.name, 'Bins');
    expect(row.done, 1);
    expect(row.skipped, 1);
    expect(row.missed, 1);
    expect(row.share, closeTo(1 / 3, 0.001));
  });

  test('36 timing buckets by calendar day against the due date', () {
    DoneRecord rec(DateTime due, DateTime at) =>
        DoneRecord(at: at, tookMinutes: 0, lateMinutes: at.difference(due).inMinutes);
    final due = DateTime(2026, 10, 20, 17);
    final d = AppData(done: {
      'a': rec(due, DateTime(2026, 10, 10, 9)), // 10 days early
      'b': rec(due, DateTime(2026, 10, 18, 9)), // 2 days early
      'c': rec(due, DateTime(2026, 10, 20, 20)), // same day, 3 h late
      'd': rec(due, DateTime(2026, 10, 23, 9)), // 3 days late
      'e': DoneRecord(at: DateTime(2026, 10, 23), tookMinutes: 0, onTime: false), // old record, left out
    });
    final t = Stats(d, now).timing(null);
    expect(t.buckets, [1, 1, 1, 1, 0]);
    expect(t.total, 4);
    expect(t.early, 2);
  });

  test('38 added vs done per day with the open line, filtered by category', () {
    final today = DateTime(now.year, now.month, now.day);
    final d = AppData(
      categories: [TaskCategory(id: 'h', name: 'Home')],
      active: [
        Task(id: 'a', title: 'a', createdAt: today.subtract(const Duration(days: 2, hours: -9)), categoryId: 'h'),
        Task(id: 'b', title: 'b', createdAt: today.add(const Duration(hours: 9))),
      ],
      archived: [
        Task(id: 'c', title: 'c', createdAt: today.subtract(const Duration(days: 2, hours: -10)), categoryId: 'h',
            closedAt: today.subtract(const Duration(days: 1, hours: -10))),
      ],
    );
    final s = Stats(d, now);
    final all = s.addedVsDone(today.subtract(const Duration(days: 2)));
    expect(all.length, 3);
    expect(all.first.unit, BucketUnit.day);
    expect([for (final b in all) b.added], [2, 0, 1]);
    expect([for (final b in all) b.done], [0, 1, 0]);
    expect([for (final b in all) b.open], [2, 1, 2]);
    final home = s.addedVsDone(today.subtract(const Duration(days: 2)), categoryId: 'h');
    expect([for (final b in home) b.added], [2, 0, 0]);
    expect(s.addedVsDone(today.subtract(const Duration(days: 200))).first.unit, BucketUnit.week);
  });

  test('44 weekly review: next date and wording', () {
    final d = AppData(weeklyReview: true, weeklyDay: DateTime.sunday, weeklyAt: 18 * 60);
    // 2 Nov 2026 is a Monday.
    expect(Reminders.nextReview(d, now), DateTime(2026, 11, 8, 18));
    expect(Reminders.nextReview(d, DateTime(2026, 11, 8, 17)), DateTime(2026, 11, 8, 18));
    expect(Reminders.nextReview(d, DateTime(2026, 11, 8, 19)), DateTime(2026, 11, 15, 18));
    d.active.add(Task(id: 'x', title: 'x', createdAt: DateTime(2026, 11, 5), dueAt: DateTime(2026, 11, 10)));
    final (title, body) = Reminders.reviewText(d, DateTime(2026, 11, 8, 18));
    expect(title, 'Weekly review: 0 done, 1 added');
    expect(body, 'Last 7 days: 1 task added, 0 ticked off. 1 task due in the coming week.');
  });

  testWidgets('statistics page shows the new sections', (tester) async {
    final store = AppStore()..addTask('Bins');
    final t = store.data.active.single
      ..dueAt = DateTime.now().subtract(const Duration(days: 1))
      ..repeat = const Repeat(unit: RepeatUnit.week);
    store.complete(t);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Added vs done'), 300);
    await tester.scrollUntilVisible(find.text('By source'), 300);
    expect(find.text('Typed in the app'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Repeating tasks'), 300);
    expect(find.text('Bins'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Early or late'), 300);
    expect(find.textContaining('Typically 24 hours late'), findsOneWidget);
  });
}
