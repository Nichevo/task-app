import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/screens/day_plan_page.dart';
import 'package:task_blocks/store.dart';

/// 1.12.6: moving a Day plan block and stretching it are kept apart. The grip along the bottom
/// edge stretches (dragged at once or held first); holding anywhere else moves.
void main() {
  final today = DateTime.now();
  DateTime at(int h, [int m = 0]) => DateTime(today.year, today.month, today.day, h, m);
  final handle = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_StretchHandle');

  Future<AppStore> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppStore();
    final t = s.addTask('Mow lawn');
    s.planTime(t, at(10), 60);
    await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s, initialDay: at(0), events: const [])));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Mow lawn'));
    await tester.pumpAndSettle();
    return s;
  }

  // 1.5 pixels a minute on a phone: 45 px is 30 minutes.
  const down = Offset(0, 45);

  testWidgets('a block shows a grip along its bottom edge', (tester) async {
    await open(tester);
    expect(handle, findsOneWidget);
    expect(stretchHandleHeight(90), greaterThanOrEqualTo(24));
    expect(stretchHandleHeight(24), 16);
  });

  testWidgets('holding the grip and dragging stretches, not moves', (tester) async {
    final s = await open(tester);
    final g = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(down);
    await tester.pump();
    expect(find.textContaining('Length 1 h 30'), findsOneWidget);
    expect(find.textContaining('Moving'), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
    final slot = s.data.active.first.slots.single;
    expect(slot.start, at(10));
    expect(slot.minutes, 90);
  });

  testWidgets('dragging the grip straight away stretches', (tester) async {
    final s = await open(tester);
    // A drag only starts after the finger has gone 20 px (the touch slop).
    await tester.drag(handle, down + const Offset(0, 20));
    await tester.pumpAndSettle();
    final slot = s.data.active.first.slots.single;
    expect(slot.start, at(10));
    expect(slot.minutes, 90);
  });

  testWidgets('holding the block itself moves it', (tester) async {
    final s = await open(tester);
    final g = await tester.startGesture(tester.getCenter(find.text('Mow lawn')));
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(down);
    await tester.pump();
    expect(find.textContaining('Moving · 10:30 – 11:30'), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    final slot = s.data.active.first.slots.single;
    expect(slot.start, at(10, 30));
    expect(slot.minutes, 60);
  });
}
