import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/task_colors.dart';

void main() {
  test('colour goes from green to red over the chosen time', () {
    final now = DateTime(2026, 1, 10, 12);
    Task aged(int hours) => Task(id: 'x', title: 't', createdAt: now.subtract(Duration(hours: hours)));
    expect(HSVColor.fromColor(ageColor(aged(0), 24, now)).hue, closeTo(120, 1));
    expect(HSVColor.fromColor(ageColor(aged(12), 24, now)).hue, closeTo(60, 1));
    expect(HSVColor.fromColor(ageColor(aged(48), 24, now)).hue, closeTo(0, 1));
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
    expect(lines[0], 'Status,Position,Task,Notes,Created,Due,Closed');
    expect(lines[1], 'Open,1,"Buy milk, eggs",,2026-01-01 09:00,,');
    expect(lines[2], 'Closed,,"Say ""hi""",,2026-01-01 00:00,,2026-01-02 08:30');
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
}
