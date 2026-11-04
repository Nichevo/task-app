import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/achievements.dart';
import 'package:task_blocks/habits.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/habits_page.dart';
import 'package:task_blocks/screens/home_page.dart';
import 'package:task_blocks/stats.dart';
import 'package:task_blocks/store.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

// Wednesday 11 November 2026, evening.
final wed = DateTime(2026, 11, 11, 19);

Task habit(AppStore s, String name, {HabitGoal goal = HabitGoal.daily, List<String> days = const []}) {
  final t = s.addTask(name);
  s.setHabit(t, true);
  t.habitGoal = goal;
  t.worked.addAll(days);
  return t;
}

/// Item 78: the habit tracker.
void main() {
  group('streaks', () {
    test('every day: today does not break it, one free miss a week, a second one does', () {
      final s = AppStore();
      final t = habit(s, 'Walk', days: ['2026-11-07', '2026-11-08', '2026-11-09', '2026-11-10']);
      expect(streak(t, wed), 4, reason: 'today not ticked yet');
      s.setWorked(t, wed, true);
      expect(streak(t, wed), 5);
      t.worked.remove('2026-11-09');
      expect(streak(t, wed), 4, reason: 'Monday forgiven');
      t.worked.remove('2026-11-10');
      expect(streak(t, wed), 1, reason: 'two misses in one week');
      t.worked.add('2026-11-10');
      t.habitFreeMiss = false;
      expect(streak(t, wed), 2);
    });

    test('chosen days skip the others; times a week counts weeks', () {
      final s = AppStore();
      final gym = habit(s, 'Gym', goal: HabitGoal.weekdays, days: ['2026-11-02', '2026-11-04', '2026-11-06', '2026-11-09'])
        ..habitDays.clear()
        ..habitDays.addAll({1, 3, 5});
      expect(streak(gym, wed), 4, reason: 'Wednesday is today and not ticked yet');
      final read = habit(s, 'Read', goal: HabitGoal.perWeek, days: [
        '2026-10-26', '2026-10-28', // two: not enough
        '2026-11-02', '2026-11-03', '2026-11-05',
        '2026-11-09', '2026-11-10',
      ])
        ..habitTimes = 3;
      expect(streak(read, wed), 1, reason: 'this week is still going; last week met it');
      s.setWorked(read, wed, true);
      expect(streak(read, wed), 2);
      expect(streakText(read, 2), '2 weeks');
      expect(goalText(read), '3 times a week');
      expect(goalText(gym), 'Mon, Wed, Fri');
    });

    test('pausing keeps the streak; paused days are not missed', () {
      final s = AppStore();
      final t = habit(s, 'Walk', days: ['2026-11-02', '2026-11-03'])..habitFreeMiss = false;
      t.habitPauses.add('2026-11-04/2026-11-10');
      expect(streak(t, wed), 2);
      expect(scheduledOn(t, DateTime(2026, 11, 5)), isFalse);
      expect(roundTrip(s.data).task(t.id)!.habitPauses, ['2026-11-04/2026-11-10']);
    });

    test('month score and today\'s line', () {
      final s = AppStore();
      final walk = habit(s, 'Walk', days: ['2026-11-01', '2026-11-03', '2026-11-11']);
      final read = habit(s, 'Read', goal: HabitGoal.perWeek)..habitTimes = 2;
      read.worked.addAll({'2026-11-09', '2026-11-10'});
      expect(monthScore(walk, wed, wed), closeTo(3 / 11, 0.001));
      expect(dueToday(read, wed), isFalse, reason: 'twice this week already');
      expect(habitsToday(s.data, wed), (1, 1));
    });
  });

  group('habits and the rest of the app', () {
    test('a repeating task becomes a habit with its history', () {
      final s = AppStore();
      final t = s.addTask('Water plants')
        ..dueAt = DateTime(2026, 11, 2, 8)
        ..repeat = const Repeat(unit: RepeatUnit.week, weekdays: {1, 4});
      final next = s.complete(t, at: DateTime(2026, 11, 2, 9))!;
      final last = s.complete(next, at: DateTime(2026, 11, 5, 8, 30))!;
      s.setHabit(last, true);
      expect(last.habit, isTrue);
      expect(last.repeat, isNull);
      expect(last.dueAt, isNull);
      expect(last.habitGoal, HabitGoal.weekdays);
      expect(last.habitDays, {1, 4});
      expect(last.habitRemind, 8 * 60);
      expect(last.worked, containsAll(['2026-11-02', '2026-11-05']));
    });

    test('a habit leaves the board and the open count; the widgets list it apart', () {
      final s = AppStore();
      final t = s.addTask('Stretch', board: true);
      s.setHabit(t, true);
      expect(t.kanban, isFalse);
      expect(Stats(s.data, wed).openCount, 0);
      final j = jsonDecode(HomeWidgets.widgetJson(s.data, wed)) as Map<String, dynamic>;
      expect(j['tasks'], isEmpty);
      expect((j['habits'] as List).single['title'], 'Stretch');
    });

    test('a habit\'s reminder waits for a day it is not ticked', () {
      final s = AppStore();
      final t = habit(s, 'Walk')..habitRemind = 20 * 60;
      expect(nextHabitReminder(t, wed), DateTime(2026, 11, 11, 20));
      s.setWorked(t, wed, true);
      expect(nextHabitReminder(t, wed), DateTime(2026, 11, 12, 20));
      s.pauseHabit(t, true);
      expect(nextHabitReminder(t, wed), isNull);
    });

    test('achievements count habits apart from days worked', () {
      final s = AppStore();
      habit(s, 'Walk', days: ['2026-11-02', '2026-11-03', '2026-11-04']);
      final a = Achievements(s.data, AchievePeriod.lastWeek, wed);
      expect(a.daysWorked, 0);
      expect(a.unfinished, isEmpty);
      final (t, done, due) = a.habits.single;
      expect((t.title, done, due), ('Walk', 3, 7));
      expect(a.asText(), contains('- Walk: 3 of 7'));
    });
  });

  testWidgets('the list shows one habits line, and the Habits page ticks today', (tester) async {
    final s = AppStore();
    s.addTask('Buy milk');
    final t = s.addTask('Walk');
    s.setHabit(t, true);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: s)));
    await tester.pumpAndSettle();
    expect(find.text('Habits today: 0 of 1'), findsOneWidget);
    expect(find.text('Walk'), findsNothing);
    await tester.tap(find.text('Habits today: 0 of 1'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitsPage), findsOneWidget);
    final letter = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][DateTime.now().weekday - 1];
    final before = ['M', 'T', 'W', 'T', 'F', 'S', 'S'].sublist(0, DateTime.now().weekday - 1).where((l) => l == letter).length;
    await tester.tap(find.text(letter).at(before));
    await tester.pumpAndSettle();
    expect(t.workedOn(DateTime.now()), isTrue);
    expect(find.text('Today: 1 of 1 done'), findsOneWidget);
    await tester.tap(find.text('Walk'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pause (keeps the streak)'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Last 12 months'), findsOneWidget);
    await tester.tap(find.text('Pause (keeps the streak)'));
    await tester.pumpAndSettle();
    expect(t.habitPaused, isTrue);
  });
}
