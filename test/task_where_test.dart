import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/day_plan.dart';
import 'package:task_blocks/geocode.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/places.dart';
import 'package:task_blocks/screens/day_plan_page.dart';
import 'package:task_blocks/screens/task_page.dart';
import 'package:task_blocks/store.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 16, h, m);

/// 1.12.5: a task's location and the driving either side of it.
void main() {
  // About 6 km apart in Auckland.
  const home = (lat: -36.8485, lng: 174.7633);
  const shop = TaskWhere('Bunnings', lat: -36.9000, lng: 174.7900);
  const shop2 = TaskWhere('Mitre 10', lat: -36.8800, lng: 174.8100);

  test('rough driving estimate from the distance', () {
    expect(estimateDriveMinutes(100), 5);
    expect(estimateDriveMinutes(6000), 15); // 7.8 km of road at 40 km/h = 11.7 min
    expect(estimateDriveMinutes(30000), 60);
  });

  test('location and driving times are saved and synced with the task', () {
    final s = AppStore();
    final t = s.addTask('Buy timber');
    s.setWhere(t, shop);
    s.setDrive(t, before: 20, after: 0);
    final back = Task.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
    expect(back.where, shop);
    expect([back.driveBefore, back.driveAfter], [20, 0]);
    expect(Task.fromJson(jsonDecode(jsonEncode((s.addTask('x')).toJson())) as Map<String, dynamic>).where, isNull);
  });

  test('the Day plan shows driving: from Home, between stops, and home after the last', () {
    final s = AppStore();
    s.places.add(Place.create('Home', home.lat, home.lng));
    final a = s.addTask('Buy timber');
    s.setWhere(a, shop);
    final b = s.addTask('Pick up paint');
    s.setWhere(b, shop2);
    s.planTime(a, at(10), 60);
    s.planTime(b, at(13), 30);
    final l = layoutDay(s.data, at(0));
    final drives = [for (final d in l.drives) (d.block.task.title, d.before, d.minutes, d.from)];
    expect(drives, [
      ('Buy timber', true, 15, 'Home'),
      ('Pick up paint', true, 10, 'Bunnings'), // from the last stop, not from Home
      ('Pick up paint', false, 15, 'Home'),
    ]);
    expect(l.drives.every((d) => d.estimate), isTrue);
    // Driving is busy time.
    expect(l.free.any((f) => f.start.isBefore(at(10)) && f.end.isAfter(at(9, 50))), isFalse);
    expect(dayLoad(s.data, at(0)), greaterThan(dayLoadWithout(s, at(0))));

    // A time set on the task wins; 0 means none.
    s.setDrive(a, before: 30, after: null);
    s.setDrive(b, before: 0, after: null);
    final l2 = layoutDay(s.data, at(0));
    expect([for (final d in l2.drives) (d.block.task.title, d.before, d.minutes, d.estimate)], [
      ('Buy timber', true, 30, false),
      ('Pick up paint', false, 15, true),
    ]);
  });

  test('no pin or no Home: nothing suggested', () {
    final s = AppStore();
    final t = s.addTask('Dentist');
    s.setWhere(t, const TaskWhere('Dentist on Queen St'));
    s.planTime(t, at(9), 30);
    expect(layoutDay(s.data, at(0)).drives, isEmpty);
    s.setWhere(t, shop);
    expect(layoutDay(s.data, at(0)).drives, isEmpty, reason: 'no saved place called Home');
    expect(suggestDrive(s.data, t, after: false), isNull);
  });

  test('address search results are read and shortened', () {
    final r = parseAddresses([
      {'lat': '-36.9', 'lon': '174.79', 'display_name': 'Bunnings, 5 Carr Road, Mount Roskill, Auckland, 1041, New Zealand'},
      {'lat': 'x', 'lon': '1'},
    ]);
    expect(r.single, const TaskWhere('Bunnings, 5 Carr Road, Mount Roskill', lat: -36.9, lng: 174.79));
  });

  testWidgets('the Day plan draws the driving', (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppStore();
    s.places.add(Place.create('Home', home.lat, home.lng));
    final a = s.addTask('Buy timber');
    s.setWhere(a, shop);
    s.planTime(a, at(10), 60);
    await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s, initialDay: at(0))));
    await tester.pumpAndSettle();
    expect(find.text('≈15 min to Bunnings'), findsOneWidget);
    expect(find.text('≈15 min to Home'), findsOneWidget);
  });

  testWidgets('the task page has Location, then Driving time once set', (tester) async {
    final s = AppStore();
    final t = s.addTask('Buy timber');
    await tester.pumpWidget(MaterialApp(home: TaskPage(store: s, task: t)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Location'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Driving time'), findsNothing);
    s.setWhere(t, shop);
    await tester.pumpAndSettle();
    expect(find.text('Bunnings'), findsOneWidget);
    expect(find.text('Driving time'), findsOneWidget);
    expect(find.byTooltip('Open in Maps'), findsOneWidget);
  });
}

double dayLoadWithout(AppStore s, DateTime day) {
  final saved = {for (final t in s.data.active) t: t.where};
  for (final t in saved.keys) {
    t.where = null;
  }
  final v = dayLoad(s.data, day);
  saved.forEach((t, w) => t.where = w);
  return v;
}
