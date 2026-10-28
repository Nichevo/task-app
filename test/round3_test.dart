import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/csv_import.dart';
import 'package:task_blocks/input_parse.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/calendar_page.dart';
import 'package:task_blocks/screens/stats_page.dart';
import 'package:task_blocks/stats.dart';
import 'package:task_blocks/store.dart';

void main() {
  group('input parsing', () {
    late AppData data;
    late TaskCategory shopping, work;
    setUp(() {
      data = AppData();
      shopping = TaskCategory.create('Shopping');
      work = TaskCategory.create('Work')..keywords.addAll(['invoice', 'client']);
      data.categories.addAll([shopping, work]);
    });

    test('#tag sets the category and is removed from the title', () {
      final p = parseInput('Buy milk #shopping tomorrow', data, DateTime(2026, 10, 28, 9));
      expect(p.title, 'Buy milk');
      expect(p.categoryId, shopping.id);
      expect(p.source, CategorySource.tag);
      expect(p.due, DateTime(2026, 10, 29, 17));
    });

    test('a category keyword wins', () {
      final p = parseInput('Send the invoice to Pat', data, DateTime(2026, 10, 28));
      expect(p.categoryId, work.id);
      expect(p.source, CategorySource.keyword);
    });

    test('learns from tasks already filed, and stays quiet when nothing matches', () {
      data.active.addAll([
        Task.create('Buy bread')..categoryId = shopping.id,
        Task.create('Buy eggs and bread')..categoryId = shopping.id,
        Task.create('Call the plumber'),
      ]);
      expect(parseInput('Bread rolls', data, DateTime.now()).categoryId, shopping.id);
      expect(parseInput('Bread rolls', data, DateTime.now()).source, CategorySource.learned);
      expect(parseInput('Paint the fence', data, DateTime.now()).categoryId, isNull);
      data.autoCategory = AutoCategory.off;
      expect(parseInput('Bread rolls', data, DateTime.now()).categoryId, isNull);
    });

    test('splitLines drops bullets and numbering', () {
      expect(splitLines('- milk\n2. eggs\n• bread\n\n[ ] jam'), ['milk', 'eggs', 'bread', 'jam']);
    });
  });

  group('checklists', () {
    test('steps tick, a step can become a linked task, and repeats start unticked', () {
      final s = AppStore()..addTask('Pack for trip');
      final t = s.data.active.single..repeat = const Repeat(unit: RepeatUnit.week);
      s.addStep(t, 'Passport');
      final charger = s.addStep(t, 'Charger');
      expect(s.toggleStep(t, t.steps.first), isFalse);
      expect(t.stepsDone, 1);

      final linked = s.stepToTask(t, charger);
      expect(s.data.active.map((x) => x.title), ['Pack for trip', 'Charger']);
      expect(charger.taskId, linked.id);
      s.complete(linked);
      expect(charger.done, isTrue);

      final next = s.complete(t)!;
      expect(next.steps.map((x) => x.title), ['Passport', 'Charger']);
      expect(next.steps.every((x) => !x.done), isTrue);
    });

    test('templates add steps and survive JSON', () {
      final s = AppStore()..addTask('Bills');
      final tpl = s.saveTemplate('Monthly', ['Rent', 'Power', '']);
      expect(tpl.steps, ['Rent', 'Power']);
      s.applyTemplate(s.data.active.single, tpl);
      final back = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())));
      expect(back.templates.single.name, 'Monthly');
      expect(back.active.single.steps.map((x) => x.title), ['Rent', 'Power']);
    });

    test('steps go through the CSV export and import', () {
      final d = AppData(active: [Task(id: '1', title: 'Trip', createdAt: DateTime(2026, 1, 1))]);
      d.active.single.steps.addAll([TaskStep.create('Passport')..done = true, TaskStep.create('Charger')]);
      final csv = buildCsv(d);
      expect(csv, contains('[x] Passport; [ ] Charger'));
      final fresh = AppData();
      expect(importCsvText(fresh, csv), 1);
      expect(fresh.active.single.steps.map((x) => x.done), [true, false]);
    });
  });

  group('statistics', () {
    test('done records are kept when the archive is cleaned and merge by union', () {
      final s = AppStore()..addTask('Old job');
      final t = s.data.active.single..dueAt = DateTime.now().add(const Duration(days: 1));
      s.complete(t, at: DateTime.now().subtract(const Duration(days: 40)));
      expect(s.data.done[t.id]!.onTime, isTrue);
      s.data.archiveKeepDays = 30;
      s.changed(settings: true);
      expect(s.data.archived, isEmpty);
      expect(s.data.done.containsKey(t.id), isTrue);

      final other = AppData(done: {'x': DoneRecord(at: DateTime(2026, 1, 1), tookMinutes: 5)});
      final m = mergeData(s.data, other);
      expect(m.done.keys, containsAll([t.id, 'x']));
    });

    test('streak, weekly counts and on-time share', () {
      final now = DateTime(2026, 10, 28, 12); // a Wednesday
      final d = AppData(done: {
        'a': DoneRecord(at: DateTime(2026, 10, 28, 9), tookMinutes: 60, onTime: true),
        'b': DoneRecord(at: DateTime(2026, 10, 27, 9), tookMinutes: 120, onTime: false),
        'c': DoneRecord(at: DateTime(2026, 10, 20, 9), tookMinutes: 30),
      });
      final st = Stats(d, now);
      expect(st.streak, 2);
      expect(st.doneThisWeek, 2);
      expect(st.donePerWeek(2).map((e) => e.$2), [1, 2]);
      expect(st.onTimeShare(null), 0.5);
      expect(st.medianTimeToFinish(null), const Duration(minutes: 60));
    });

    test('restoring a task forgets its done record', () {
      final s = AppStore()..addTask('x');
      final t = s.data.active.single;
      s.complete(t);
      s.restore(t);
      expect(s.data.done, isEmpty);
    });
  });

  group('overdue settings and merge', () {
    test('new settings round-trip and follow the newest settings', () {
      final a = AppData(overdueMode: OverdueMode.nudge, nudgeHours: 6, settingsUpdatedAt: DateTime.utc(2026, 1, 2));
      final b = AppData(overdueMode: OverdueMode.daily, settingsUpdatedAt: DateTime.utc(2026, 1, 1));
      expect(mergeData(b, a).overdueMode, OverdueMode.nudge);
      final back = AppData.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(back.nudgeHours, 6);
      expect(back.autoCategory, AutoCategory.suggest);
    });
  });

  testWidgets('category chip appears for a #tag and the task gets the category', (tester) async {
    final store = AppStore();
    store.addCategory('Home');
    await tester.pumpWidget(TaskApp(store: store));
    await tester.enterText(find.byType(TextField), 'Fix tap #home');
    await tester.pump();
    expect(find.widgetWithText(InputChip, 'Home'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(store.data.active.single.title, 'Fix tap');
    expect(store.data.active.single.categoryId, store.data.categories.single.id);
  });

  testWidgets('pasting several lines offers them as separate tasks', (tester) async {
    final store = AppStore();
    await tester.pumpWidget(TaskApp(store: store));
    await tester.enterText(find.byType(TextField), 'milk\neggs\nbread');
    await tester.pumpAndSettle();
    expect(find.text('Add 3 tasks?'), findsOneWidget);
    await tester.tap(find.text('Add 3'));
    await tester.pumpAndSettle();
    expect(store.data.active.map((t) => t.title), ['milk', 'eggs', 'bread']);
  });

  testWidgets('statistics page shows the counts', (tester) async {
    final store = AppStore()..addTask('a');
    store.complete(store.data.active.single);
    await tester.pumpWidget(MaterialApp(home: StatsPage(store: store)));
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget); // streak
  });

  testWidgets('calendar page lists the chosen day and shows faded repeats', (tester) async {
    final store = AppStore()..addTask('Bins');
    final day = DateTime(2030, 1, 7, 9);
    store.data.active.single
      ..dueAt = day
      ..repeat = const Repeat(unit: RepeatUnit.week);
    await tester.pumpWidget(MaterialApp(home: CalendarPage(store: store, initialDay: day)));
    expect(find.text('Monday 7 January'), findsOneWidget);
    expect(find.text('Bins'), findsOneWidget);
    await tester.tap(find.text('14'));
    await tester.pump();
    expect(find.byTooltip('A later repeat'), findsOneWidget);
  });
}
