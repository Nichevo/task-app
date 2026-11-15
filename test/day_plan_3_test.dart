import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/screens/day_plan_page.dart';
import 'package:task_blocks/screens/side_panel.dart';
import 'package:task_blocks/store.dart';

// Monday 16 November 2026.
final mon = DateTime(2026, 11, 16);
DateTime at(int h, [int m = 0, int day = 16]) => DateTime(2026, 11, day, h, m);

/// Item 101, part 3 (1.11.2): the Fold side panel, two days side by side and the widget data.
void main() {
  test('the panel has a Day plan view and the Timeline view is called Gantt (stored name kept)', () {
    expect(PanelView.dayPlan.label, 'Day plan');
    expect(PanelView.timeline.label, 'Gantt');
    expect(PanelView.timeline.name, 'timeline');
    final s = AppStore()
      ..panelRemember = true
      ..showPanel(PanelView.dayPlan);
    expect(s.deviceSettingsBackup()['panelLast'], 'dayPlan');
  });

  testWidgets('the side panel shows the Day plan with a slim bar and a full-size button', (tester) async {
    final s = AppStore();
    s.planTime(s.addTask('Write report'), DateTime.now().copyWith(hour: 9, minute: 0), 60);
    s.showPanel(PanelView.dayPlan);
    tester.view.physicalSize = const Size(840, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SidePanel(store: s, onOpen: (_) {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DayPlanPage), findsOneWidget);
    expect(find.text('Write report'), findsOneWidget);
    expect(find.text('Gantt'), findsOneWidget);
    await tester.tap(find.byTooltip('Open the Day plan'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open the Day plan'), findsNothing, reason: 'the full-size page has no such button');
    expect(find.textContaining('Day plan · '), findsOneWidget);
  });

  testWidgets('two days side by side on a wide screen, remembered on the device', (tester) async {
    final s = AppStore();
    s.planTime(s.addTask('Monday task'), at(9), 60);
    s.planTime(s.addTask('Tuesday task'), at(10, 0, 17), 60);
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s, initialDay: mon)));
    await tester.pumpAndSettle();
    expect(find.text('Tuesday task'), findsNothing);
    await tester.tap(find.byTooltip('Two days side by side'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(s.dayPlanTwoDays, isTrue);
    expect(find.text('Monday task'), findsOneWidget);
    expect(find.text('Tuesday task'), findsOneWidget);
    expect(find.textContaining('Tuesday 17 Nov'), findsOneWidget);
    // The tray panel still fits beside both days.
    expect(find.text('To plan · drag onto a time'), findsOneWidget);
  });

  testWidgets('on a narrow screen there is no two-day button', (tester) async {
    final s = AppStore()..dayPlanTwoDays = true;
    tester.view.physicalSize = const Size(824, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s, initialDay: mon)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Two days side by side'), findsNothing);
    expect(find.byTooltip('One day'), findsNothing);
  });

  test("the widgets get the week's open planned times in order", () {
    final s = AppStore();
    final report = s.addTask('Write report');
    final fence = s.addTask('Paint fence');
    final sand = s.addStep(fence, 'Sand'), coat = s.addStep(fence, 'Coat');
    s.planTime(report, at(14), 60);
    s.planTime(report, at(9), 60); // more of its time later today
    s.planTime(fence, at(11), 30, step: sand);
    s.planTime(fence, at(12), 30, step: coat);
    s.toggleStep(fence, coat);
    s.planTime(report, at(8), 30).doneAt = at(8, 30);
    s.planTime(report, at(9, 0, 15), 30); // yesterday
    s.planTime(report, at(9, 0, 24), 30); // over a week away
    final rows = jsonDecode(HomeWidgets.widgetJson(s.data, at(7)))['plan'] as List;
    expect(rows.map((r) => r['title']), ['Write report', 'Sand', 'Write report']);
    expect(rows[0]['later'], isTrue);
    expect(rows[2]['later'], isTrue, reason: 'more is planned on the 24th');
    expect(rows[1]['task'], 'Paint fence');
    expect(rows[1]['step'], sand.id);
    expect(rows[0]['end'] - rows[0]['at'], 3600000);
  });
}
