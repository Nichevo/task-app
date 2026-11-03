import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/side_panel.dart';
import 'package:task_blocks/store.dart';

void main() {
  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(900 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  test('the agenda groups overdue, today, tomorrow and the week, with dated steps', () {
    final now = DateTime(2026, 11, 3, 12);
    final s = AppStore();
    s.addTask('Late', due: DateTime(2026, 11, 1, 9));
    s.addTask('Lunch', due: DateTime(2026, 11, 3, 13));
    final t = s.addTask('Move house', due: DateTime(2026, 11, 20));
    s.setStepDue(t, s.addStep(t, 'Book the van'), DateTime(2026, 11, 4, 9));
    s.addTask('Far off', due: DateTime(2026, 12, 1));
    s.addTask('Snoozed', due: DateTime(2026, 11, 5))
      .snoozedUntil = DateTime(2026, 11, 10);
    final g = agendaGroups(s.data, now);
    expect([for (final (n, _) in g) n], ['Overdue', 'Today', 'Tomorrow']);
    expect(g[0].$2.single.task.title, 'Late');
    expect(g[1].$2.single.task.title, 'Lunch');
    expect(g[2].$2.single.step!.title, 'Book the van');
  });

  test('panel choices are saved on the device and with the device backup', () {
    final s = AppStore()
      ..panelStart = PanelView.board
      ..panelRemember = true
      ..unfoldOpens = UnfoldOpens.matrix;
    s.panelHidden.add(PanelView.events);
    s.showPanel(PanelView.calendar);
    final j = s.deviceSettingsBackup();
    expect(j['panelStart'], 'board');
    expect(j['panelLast'], 'calendar');
    expect(j['panelHidden'], ['events']);
    expect(j['unfoldOpens'], 'matrix');
    expect(s.shownPanelViews, isNot(contains(PanelView.events)));
    s.panelHidden.addAll(PanelView.values);
    expect(s.shownPanelViews, [PanelView.agenda]);
  });

  testWidgets('the panel starts on Agenda and the chips switch views; the matrix gets half the screen',
      (tester) async {
    wide(tester);
    final s = AppStore();
    s.addTask('Fix the leak', due: DateTime.now().add(const Duration(hours: 1)), box: MatrixBox.doNow);
    await tester.pumpWidget(TaskApp(store: s));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(SidePanel), matching: find.text('Today')), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Board'));
    await tester.pumpAndSettle();
    expect(find.text('Open the whole board'), findsOneWidget);
    expect(s.panelView, PanelView.board);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Matrix'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(SidePanel));
    expect(panel.width, closeTo(450, 2));

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Statistics'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Statistics'));
    await tester.pumpAndSettle();
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('All statistics'), findsOneWidget);
  });

  testWidgets('opening a task from the agenda comes back to it', (tester) async {
    wide(tester);
    final s = AppStore();
    s.addTask('Ring the vet', due: DateTime.now().add(const Duration(hours: 2)));
    await tester.pumpWidget(TaskApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(SidePanel), matching: find.text('Ring the vet')));
    await tester.pumpAndSettle();
    expect(find.byType(SidePanel), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(SidePanel), matching: find.text('Today')), findsOneWidget);
  });

  testWidgets('settings page changes the start view and the chips', (tester) async {
    final s = AppStore();
    tester.view.physicalSize = const Size(500 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PanelSettingsPage(store: s)));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Archive'));
    await tester.pump();
    expect(s.panelHidden, contains(PanelView.archive));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'By source'));
    await tester.pump();
    expect(s.panelStats, contains(PanelStat.source));
  });
}
