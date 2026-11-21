import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/week_widgets.dart';
import 'package:task_blocks/work_meetings.dart';

/// Item 115: the week and month widgets with two clocks.
void main() {
  final now = DateTime(2026, 11, 22, 9, 42); // a Sunday

  test('clock settings default to Jingzhou on China time and sync', () {
    final d = AppData();
    expect(d.clocksOn, isTrue);
    expect(d.clockCity, 'Jingzhou');
    expect(d.clockZone, 'Asia/Shanghai');
    d
      ..clockCity = 'Wuhan office'
      ..clockHome = 'Home';
    final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
    expect(back.clockCity, 'Wuhan office');
    expect(back.clockHome, 'Home');
  });

  test('which days: the next 7, Monday to Sunday, and without the weekend', () {
    final d = AppData();
    expect(weekDays(d, now).map(dayKey), [for (var i = 22; i <= 28; i++) '2026-11-$i']);
    d.weekShown = 'monday';
    expect(weekDays(d, now).first, DateTime(2026, 11, 16));
    expect(weekDays(d, now).last, DateTime(2026, 11, 22));
    d
      ..weekShown = 'next7'
      ..weekNoWeekend = true;
    expect(weekDays(d, now).map((x) => x.weekday), [1, 2, 3, 4, 5]);
  });

  test('tasks, dated steps and work meetings land on their days; overdue goes to today', () {
    final s = AppStore();
    final gas = s.addTask('Gas bill')..dueAt = DateTime(2026, 11, 22, 10);
    s.addTask('Plumber').dueAt = DateTime(2026, 11, 19);
    final fc = s.addTask('Demand forecast');
    fc.steps.add(TaskStep.create('Fit the model')..dueAt = DateTime(2026, 11, 23));
    fc.steps.add(TaskStep.create('Done one')
      ..dueAt = DateTime(2026, 11, 23)
      ..done = true);
    s.addTask('Later').dueAt = DateTime(2026, 12, 20);
    s.data.workMeetings.add(WorkMeeting(title: 'Jingzhou call', start: DateTime(2026, 11, 23, 14), end: DateTime(2026, 11, 23, 15)));
    final w = weekWidgetData(s.data, now);
    final items = (w['items'] as List).cast<Map<String, dynamic>>();
    String on(String day) => [for (final i in items) if (i['day'] == day) i['title']].join(', ');
    expect(on('2026-11-22'), 'Plumber, Gas bill', reason: 'overdue first');
    expect(items.firstWhere((i) => i['title'] == 'Plumber')['over'], isTrue);
    expect(items.firstWhere((i) => i['id'] == gas.id)['at'], DateTime(2026, 11, 22, 10).millisecondsSinceEpoch);
    expect(on('2026-11-23'), 'Jingzhou call, Fit the model', reason: 'timed first, ticked steps left out');
    expect(items.any((i) => i['title'] == 'Later'), isFalse);
    expect((w['busy'] as Map)['2026-11-23'], greaterThanOrEqualTo(60));
    expect(w['clocks'], {'on': true, 'home': '', 'zone': 'Asia/Shanghai', 'city': 'Jingzhou'});
  });

  test('busy levels', () {
    expect(busyLevel(0, 480), 0);
    expect(busyLevel(60, 480), 1);
    expect(busyLevel(200, 480), 2);
    expect(busyLevel(380, 480), 3);
    expect(busyLevel(600, 480), 4);
  });

  test('the widgets get the week', () {
    final s = AppStore();
    s.addTask('Gas bill').dueAt = DateTime(2026, 11, 22, 10);
    final j = jsonDecode(HomeWidgets.widgetJson(s.data, now)) as Map<String, dynamic>;
    expect((j['week'] as Map)['days'], hasLength(7));
  });
}
