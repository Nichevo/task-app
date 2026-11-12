import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/changelog.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/task_list.dart';
import 'package:task_blocks/widgets/link_text.dart';

void main() {
  final now = DateTime(2026, 11, 2, 10);
  Task task(String title, {DateTime? due, bool starred = false, int ageHours = 0}) =>
      Task(id: title, title: title, createdAt: now.subtract(Duration(hours: ageHours)), dueAt: due, starred: starred);

  group('35 skip', () {
    test('moves a fixed-schedule repeat to its next date, unticks steps and records the skip', () {
      final s = AppStore();
      final t = s.addTask('Bins')
        ..dueAt = DateTime(2026, 11, 2, 8)
        ..repeat = const Repeat(unit: RepeatUnit.week)
        ..snoozedUntil = DateTime(2026, 11, 2, 12);
      s.addStep(t, 'Recycling').done = true;
      final undo = s.skip(t, at: DateTime(2026, 11, 2, 9));
      expect(t.dueAt, DateTime(2026, 11, 9, 8));
      expect(t.snoozedUntil, isNull);
      expect(t.steps.single.done, isFalse);
      expect(s.data.active.single, same(t)); // same task, not ticked off
      expect(s.data.archived, isEmpty);
      final rec = s.data.skips.values.single;
      expect(rec.series, t.id);
      expect(rec.due, DateTime(2026, 11, 2, 8));

      undo();
      expect(t.dueAt, DateTime(2026, 11, 2, 8));
      expect(t.steps.single.done, isTrue);
      expect(s.data.skips, isEmpty);
    });

    test('"after done" repeats count from the day of the skip', () {
      final s = AppStore();
      final t = s.addTask('Water plants')
        ..dueAt = DateTime(2026, 10, 20, 18)
        ..repeat = const Repeat(unit: RepeatUnit.day, every: 7, fromCompletion: true);
      s.skip(t, at: DateTime(2026, 11, 2, 9));
      expect(t.dueAt, DateTime(2026, 11, 9, 18));
    });

    test('repeats keep their series id and estimate; skips merge from both devices', () {
      final t = Task.create('Bins')
        ..repeat = const Repeat(unit: RepeatUnit.week)
        ..estimate = 10;
      final next = t.nextRepeat(now);
      expect(next.series, t.id);
      expect(next.nextRepeat(now).series, t.id);
      expect(next.estimate, 10);

      final a = SkipRecord(taskId: 'x', series: 'x', at: now, due: now);
      final b = SkipRecord(taskId: 'y', series: 'y', at: now, due: now);
      final m = mergeData(AppData(skips: {a.key: a}), AppData(skips: {b.key: b}));
      expect(m.skips.length, 2);
      final back = AppData.fromJson(jsonDecode(jsonEncode(m.toJson())));
      expect(back.skips[a.key]!.series, 'x');
    });
  });

  group('41 search', () {
    test('every word must be in the name, notes or checklist', () {
      final t = Task.create('Call plumber')
        ..notes = 'About the kitchen tap'
        ..steps.add(TaskStep.create('Find invoice'));
      expect(matchesSearch(t, 'plumber'), isTrue);
      expect(matchesSearch(t, 'KITCHEN call'), isTrue);
      expect(matchesSearch(t, 'invoice'), isTrue);
      expect(matchesSearch(t, 'plumber bathroom'), isFalse);
      expect(matchesSearch(t, '  '), isTrue);
    });
  });

  group('42 sorting and quick filters', () {
    test('date chips show tasks due up to the end of that day, overdue included, no-date left out', () {
      final overdue = task('overdue', due: now.subtract(const Duration(days: 3)));
      final tonight = task('tonight', due: DateTime(2026, 11, 2, 23));
      final in5 = task('in5', due: now.add(const Duration(days: 5)));
      final in10 = task('in10', due: now.add(const Duration(days: 10)));
      final none = task('none');
      List<String> pass(QuickFilter f) =>
          [for (final t in [overdue, tonight, in5, in10, none]) if (passesFilter(t, f, now)) t.title];
      expect(pass(QuickFilter.all), ['overdue', 'tonight', 'in5', 'in10', 'none']);
      expect(pass(QuickFilter.today), ['overdue', 'tonight']);
      expect(pass(QuickFilter.week), ['overdue', 'tonight', 'in5']);
      expect(pass(QuickFilter.twoWeeks), ['overdue', 'tonight', 'in5', 'in10']);
      expect(pass(QuickFilter.overdue), ['overdue']);
      expect(pass(QuickFilter.noDate), ['none']);
    });

    test('sorts by due date with starred at the top, keeping hand-made order between equals', () {
      final d = AppData(active: [
        task('b-none'),
        task('a-late', due: now.add(const Duration(days: 9))),
        task('c-soon', due: now.add(const Duration(days: 1))),
        task('d-star', due: now.add(const Duration(days: 20)), starred: true),
        task('e-none'),
      ]);
      expect(d.sort, ListSort.due); // fresh install default
      expect(sortTasks(d.active, d, now).map((t) => t.title), ['d-star', 'c-soon', 'a-late', 'b-none', 'e-none']);
      d.starredTop = false;
      expect(sortTasks(d.active, d, now).map((t) => t.title), ['c-soon', 'a-late', 'd-star', 'b-none', 'e-none']);
      d.sort = ListSort.manual;
      expect(sortTasks(d.active, d, now).map((t) => t.title), ['b-none', 'a-late', 'c-soon', 'd-star', 'e-none']);
    });

    test('newest, colour age and category sorts', () {
      final home = TaskCategory(id: 'h', name: 'Home');
      final d = AppData(categories: [home], colourByDue: false, hoursToRed: 10, starredTop: false, active: [
        task('old', ageHours: 9),
        task('new', ageHours: 1)..categoryId = 'h',
        task('mid', ageHours: 5)..categoryId = 'h',
      ]);
      d.sort = ListSort.newest;
      expect(sortTasks(d.active, d, now).map((t) => t.title), ['new', 'mid', 'old']);
      d.sort = ListSort.age;
      expect(sortTasks(d.active, d, now).map((t) => t.title), ['old', 'mid', 'new']);
      d.sort = ListSort.categoryDue;
      expect(sortTasks(d.active, d, now).map((t) => t.title), ['new', 'mid', 'old']);
    });

    test('data saved before sorting existed keeps its hand-made order', () {
      final old = AppData().toJson()..remove('sort');
      expect(AppData.fromJson(old).sort, ListSort.manual);
      expect(AppData.fromJson(old).starredTop, isTrue);
    });

    testWidgets('chips filter the list and search finds tasks', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = AppStore()
        ..addTask('Pay rent', due: DateTime.now().add(const Duration(hours: 2)))
        ..addTask('Paint fence', due: DateTime.now().add(const Duration(days: 20)))
        ..addTask('Read book');
      await tester.pumpWidget(TaskApp(store: store));
      expect(find.text('Read book'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Next 7 days'));
      await tester.pump();
      expect(find.text('Pay rent'), findsOneWidget);
      expect(find.text('Paint fence'), findsNothing);
      expect(find.text('Read book'), findsNothing);
      expect(find.textContaining('2 more not in "Next 7 days"'), findsOneWidget);

      await tester.tap(find.byTooltip('Search'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Search tasks, notes and steps'), 'fence');
      await tester.pump();
      expect(find.text('Paint fence'), findsOneWidget); // search ignores the chip
      expect(find.text('Pay rent'), findsNothing);
    });
  });

  group('43 links', () {
    test('finds web links, emails and phone numbers but not dates', () {
      final links = findLinks('See www.example.com/a?b=1. Mail bob@x.co.nz or ring +64 21 555 1234 by 2026-11-01.');
      expect(links.map((l) => l.uri.toString()), [
        'https://www.example.com/a?b=1',
        'mailto:bob@x.co.nz',
        'tel:+64215551234',
      ]);
      expect(findLinks('https://en.wikipedia.org/wiki/Fold_(disambiguation)').single.text,
          'https://en.wikipedia.org/wiki/Fold_(disambiguation)');
      expect(findLinks('Meeting 10:30-11:00 on 02/11/2026'), isEmpty);
    });
  });

  group('45 estimates', () {
    test('reads and describes times', () {
      expect(parseEstimate('45'), 45);
      expect(parseEstimate('1.5h'), 90);
      expect(parseEstimate('1h30'), 90);
      expect(parseEstimate('2 h'), 120);
      expect(parseEstimate('1d'), 1440);
      expect(parseEstimate('soon'), isNull);
      expect(describeMinutes(150), '2 h 30 min');
      expect(shortMinutes(90), '1h30');
      expect(describeEstimates([Task.create('a')..estimate = 30, Task.create('b'), Task.create('c')..estimate = 45]),
          '1 h 15 min');
      expect(describeEstimates([Task.create('a')]), isNull);
    });
  });

  group('40 about', () {
    test('changelog is newest first and matches pubspec', () {
      expect(releases.first.version, '1.10.12');
    });
  });
}
