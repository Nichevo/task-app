import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/archive_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/task_colors.dart';

void main() {
  test('colour goes from green to red over the chosen time', () {
    final now = DateTime(2026, 1, 10, 12);
    Task aged(int hours) => Task(id: 'x', title: 't', createdAt: now.subtract(Duration(hours: hours)));
    expect(HSVColor.fromColor(ageColor(aged(0), 24, now: now)).hue, closeTo(120, 1));
    expect(HSVColor.fromColor(ageColor(aged(12), 24, now: now)).hue, closeTo(60, 1));
    expect(HSVColor.fromColor(ageColor(aged(48), 24, now: now)).hue, closeTo(0, 1));
  });

  test('store moves ticked tasks to the archive and reorders', () {
    final s = AppStore();
    s.addTask('a');
    s.addTask('b');
    s.addTask('c');
    s.reorder(2, 0);
    expect(s.data.active.map((t) => t.title), ['c', 'a', 'b']);
    s.complete(s.data.active[1]);
    expect(s.data.active.map((t) => t.title), ['c', 'b']);
    expect(s.data.archived.single.closedAt, isNotNull);
    s.restore(s.data.archived.single, 1);
    expect(s.data.active.map((t) => t.title), ['c', 'a', 'b']);
    expect(s.data.active[1].closedAt, isNull);
  });

  test('csv has all tasks and escapes commas and quotes', () {
    final d = AppData(
      active: [Task(id: '1', title: 'Buy milk, eggs', createdAt: DateTime(2026, 1, 1, 9))],
      archived: [
        Task(id: '2', title: 'Say "hi"', createdAt: DateTime(2026, 1, 1), closedAt: DateTime(2026, 1, 2, 8, 30))
      ],
    );
    final lines = buildCsv(d).trim().split('\r\n');
    expect(lines[0], 'Status,Position,Task,Notes,Category,Created,Due,Closed,Starred,Repeats');
    expect(lines[1], 'Open,1,"Buy milk, eggs",,,2026-01-01 09:00,,,,');
    expect(lines[2], 'Closed,,"Say ""hi""",,,2026-01-01 00:00,,2026-01-02 08:30,,');
  });

  test('data survives a JSON round trip', () {
    final d = AppData(hoursToRed: 168, active: [Task.create('x')..dueAt = DateTime(2026, 3, 1)]);
    final back = AppData.fromJson(d.toJson());
    expect(back.hoursToRed, 168);
    expect(back.active.single.title, 'x');
    expect(back.active.single.dueAt, DateTime(2026, 3, 1));
  });

  testWidgets('typing adds a task and ticking archives it', (tester) async {
    final store = AppStore();
    await tester.pumpWidget(TaskApp(store: store));
    await tester.enterText(find.byType(TextField), 'Call the bank');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Call the bank'), findsOneWidget);

    await tester.tap(find.text('Call the bank'));
    await tester.pumpAndSettle();
    expect(find.text('No due date'), findsOneWidget);

    await tester.tap(find.byTooltip('Tick off'));
    await tester.pump();
    expect(store.data.active, isEmpty);
    expect(store.data.archived.single.title, 'Call the bank');
  });

  testWidgets('unfolded (wide) screen shows the task beside the list', (tester) async {
    tester.view.physicalSize = const Size(880 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = AppStore()..addTask('Fix gate latch');
    await tester.pumpWidget(TaskApp(store: store));
    expect(find.text('Archive (0)'), findsOneWidget); // archive in the right pane

    await tester.tap(find.text('Fix gate latch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit / set due date'));
    await tester.pumpAndSettle();
    expect(find.text('Tasks'), findsOneWidget); // list still visible
    expect(find.widgetWithText(TextField, 'Fix gate latch'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Archive (0)'), findsOneWidget);
  });

  testWidgets('folded (narrow) screen opens the task full screen', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = AppStore()..addTask('Fix gate latch');
    await tester.pumpWidget(TaskApp(store: store));
    expect(find.textContaining('Archive ('), findsNothing);

    await tester.tap(find.text('Fix gate latch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit / set due date'));
    await tester.pumpAndSettle();
    expect(find.text('Tasks'), findsNothing);
    expect(find.widgetWithText(TextField, 'Fix gate latch'), findsOneWidget);
  });

  group('sync merge', () {
    final t0 = DateTime.utc(2026, 10, 1, 9);
    Task task(String id, {int editedMin = 0, DateTime? closed, String? title}) => Task(
        id: id,
        title: title ?? id,
        createdAt: t0,
        closedAt: closed,
        updatedAt: t0.add(Duration(minutes: editedMin)));

    test('keeps tasks added on each device and the newest edit of each', () {
      final phone = AppData(active: [task('a', editedMin: 5, title: 'a phone'), task('p')]);
      final pc = AppData(active: [task('a', editedMin: 2, title: 'a pc'), task('w')]);
      final m = mergeData(phone, pc);
      expect(m.active.map((t) => t.title), containsAll(['a phone', 'p', 'w']));
      expect(m.active.length, 3);
    });

    test('a deletion beats older edits but not newer ones', () {
      final phone = AppData(active: [task('a'), task('b', editedMin: 30)]);
      final pc = AppData(deleted: {'a': t0.add(const Duration(minutes: 10)), 'b': t0.add(const Duration(minutes: 10))});
      final m = mergeData(phone, pc);
      expect(m.active.map((t) => t.id), ['b']);
    });

    test('ticked off on one device moves to the archive on both', () {
      final phone = AppData(active: [task('a')]);
      final pc = AppData(archived: [task('a', editedMin: 1, closed: t0.add(const Duration(minutes: 1)))]);
      final m = mergeData(phone, pc);
      expect(m.active, isEmpty);
      expect(m.archived.single.id, 'a');
    });

    test('order comes from the device that reordered last', () {
      final phone = AppData(active: [task('a'), task('b'), task('c')], orderUpdatedAt: t0);
      final pc = AppData(
          active: [task('c'), task('a'), task('b')], orderUpdatedAt: t0.add(const Duration(hours: 1)));
      expect(mergeData(phone, pc).active.map((t) => t.id), ['c', 'a', 'b']);
      expect(mergeData(pc, phone).active.map((t) => t.id), ['c', 'a', 'b']);
    });

    test('settings come from the device that changed them last', () {
      final phone = AppData(hoursToRed: 24, settingsUpdatedAt: t0.add(const Duration(days: 1)));
      final pc = AppData(hoursToRed: 168, settingsUpdatedAt: t0, updatedAt: t0.add(const Duration(days: 2)));
      expect(mergeData(phone, pc).hoursToRed, 24);
    });

    test('survives a JSON round trip', () {
      final d = AppData(active: [task('a')], deleted: {'x': t0});
      final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(back.deleted['x'], t0);
      expect(back.active.single.updatedAt, t0);
    });
  });

  test('colour by due date reaches red at the due date', () {
    final now = DateTime(2026, 1, 10, 12);
    final t = Task(id: 'x', title: 't', createdAt: now.subtract(const Duration(hours: 10)))
      ..dueAt = now.add(const Duration(hours: 10));
    expect(HSVColor.fromColor(ageColor(t, 1000, byDue: true, now: now)).hue, closeTo(60, 1));
    expect(HSVColor.fromColor(ageColor(t, 1000, now: now)).hue, closeTo(120, 2));
  });

  test('archive clean-up deletes tasks closed too long ago', () {
    final s = AppStore();
    s.data.archived.addAll([
      Task(id: 'old', title: 'old', createdAt: DateTime(2020), closedAt: DateTime.now().subtract(const Duration(days: 40))),
      Task(id: 'new', title: 'new', createdAt: DateTime(2020), closedAt: DateTime.now().subtract(const Duration(days: 5))),
    ]);
    s.data.archiveKeepDays = 30;
    s.changed(settings: true);
    expect(s.data.archived.map((t) => t.id), ['new']);
    expect(s.data.deleted.containsKey('old'), isTrue);
  });

  testWidgets('swipe right ticks off, swipe left deletes with undo', (tester) async {
    final store = AppStore()
      ..addTask('One')
      ..addTask('Two');
    await tester.pumpWidget(TaskApp(store: store));
    await tester.drag(find.text('One'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(store.data.archived.single.title, 'One');

    await tester.drag(find.text('Two'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(store.data.active, isEmpty);
    expect(store.data.archived.length, 1);
    await tester.tap(find.text('Undo').last);
    await tester.pump();
    expect(store.data.active.single.title, 'Two');
  });

  testWidgets('archive search filters by name and notes', (tester) async {
    final store = AppStore();
    for (final n in ['Pay water bill', 'Return books']) {
      store.addTask(n);
      store.complete(store.data.active.single);
    }
    await tester.pumpWidget(MaterialApp(home: ArchivePage(store: store)));
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'water');
    await tester.pump();
    expect(find.text('Pay water bill'), findsOneWidget);
    expect(find.text('Return books'), findsNothing);
  });
}
