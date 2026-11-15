import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/modes.dart';
import 'package:task_blocks/screens/modes_page.dart';
import 'package:task_blocks/habits.dart';
import 'package:task_blocks/places.dart';
import 'package:task_blocks/reminders.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/task_list.dart';
import 'package:task_blocks/widgets/mode_chip.dart';

// Mon 16 Nov 2026.
DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

/// A store with Work and Home categories and a Work mode (Home hidden, Car quiet).
(AppStore, FocusMode, TaskCategory, TaskCategory, TaskCategory) setUpWork() {
  final s = AppStore();
  final work = s.addCategory('Work'), home = s.addCategory('Home'), car = s.addCategory('Car');
  final m = FocusMode.create('Work')
    ..cats[work.id] = CatShow.show
    ..cats[home.id] = CatShow.hide
    ..cats[car.id] = CatShow.quiet
    ..cats[''] = CatShow.show;
  s.addMode(m);
  return (s, m, work, home, car);
}

void main() {
  setUp(() {
    modeNow
      ..mode = null
      ..peek = false
      ..reach = null
      ..reason = null
      ..data = null
      ..noonModes = {};
  });

  group('schedule', () {
    final slots = paintSchedule(paintSchedule([], DateTime.monday, 8 * 60, 17 * 60, 'w'), DateTime.saturday, 0, 24 * 60, 'e');

    test('the mode at a time, and when it next changes', () {
      expect(scheduledAt(slots, at(16, 9)), 'w');
      expect(scheduledAt(slots, at(16, 7, 59)), everythingId);
      expect(scheduledAt(slots, at(21, 12)), 'e');
      expect(nextScheduleChange(slots, at(16, 9)), at(16, 17));
      expect(nextScheduleChange(slots, at(16, 18)), at(21, 0));
      expect(nextScheduleChange(slots, at(21, 10)), at(22, 0));
      expect(nextScheduleChange([], at(16, 9)), isNull);
    });

    test('painting cuts into what was there and joins neighbours', () {
      var s = paintSchedule(slots, DateTime.monday, 12 * 60, 13 * 60, 'x');
      expect([for (final x in s.where((x) => x.day == 1)) '${x.mode}${x.start ~/ 60}-${x.end ~/ 60}'], ['w8-12', 'x12-13', 'w13-17']);
      s = paintSchedule(s, DateTime.monday, 12 * 60, 13 * 60, 'w');
      expect([for (final x in s.where((x) => x.day == 1)) '${x.mode}${x.start ~/ 60}-${x.end ~/ 60}'], ['w8-17']);
      s = paintSchedule(s, DateTime.monday, 0, 24 * 60, everythingId);
      expect(s.where((x) => x.day == 1), isEmpty);
    });

    test('segments cover a stretch in order', () {
      final segs = scheduleSegments(slots, at(16, 6), at(16, 20));
      expect([for (final (m, a, b) in segs) '$m ${a.hour}-${b.hour}'], ['all 6-8', 'w 8-17', 'all 17-20']);
    });
  });

  test('modes, the schedule, a hand choice and the log survive saving and syncing', () {
    final (s, m, work, home, _) = setUpWork();
    m
      ..toolsOff.add(ModeTool.gantt.name)
      ..due = DueWithin.week
      ..red = true
      ..newCategory = work.id;
    s.data.modeSchedule.add(ModeSlot(day: 1, start: 480, end: 1020, mode: m.id));
    s.data.modeChoice = ModeChoice(m.id, at(16, 12), at: at(16, 9));
    s.data.modeLog.add(ModeLog(id: 'l1', mode: m.id, start: at(16, 8), end: at(16, 9), how: 'hand', peeks: 2));
    final back = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())) as Map<String, dynamic>);
    final m2 = back.mode(m.id)!;
    expect(m2.showFor(back, home.id), CatShow.hide);
    expect(m2.toolOn(ModeTool.gantt), isFalse);
    expect(m2.due, DueWithin.week);
    expect(m2.red, isTrue);
    expect(m2.newCategory, work.id);
    expect(back.modeSchedule.single.end, 1020);
    expect(back.modeChoice!.until, at(16, 12));
    expect(back.modeLog.single.peeks, 2);

    // A mode added on another device with older settings is kept; the newer hand choice wins.
    final other = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())) as Map<String, dynamic>);
    other.modes.add(FocusMode(id: 'travel', name: 'Travel'));
    other.modeChoice = ModeChoice('travel', null, at: at(16, 10));
    other.modeLog.add(ModeLog(id: 'l2', mode: 'travel', start: at(16, 10)));
    s.data.settingsUpdatedAt = DateTime.now().toUtc();
    final merged = mergeData(s.data, other);
    expect(merged.modes.map((m) => m.name), ['Work', 'Travel']);
    expect(merged.modeChoice!.mode, 'travel');
    expect(merged.modeLog.map((l) => l.id), ['l1', 'l2']);
  });

  test('what shows: shown and quiet categories, and hidden tasks that break through', () {
    final (s, m, work, home, car) = setUpWork();
    final now = DateTime.now();
    final report = s.addTask('Report', categoryId: work.id);
    final tax = s.addTask('Pay the council tax', categoryId: home.id, due: now.add(const Duration(hours: 1)));
    final mot = s.addTask('Book the MOT', categoryId: home.id, due: now.subtract(const Duration(days: 2)));
    final gutters = s.addTask('Clear the gutters', categoryId: home.id);
    final starred = s.addTask('Ring Mum', categoryId: home.id)..starred = true;
    final tyres = s.addTask('Tyres', categoryId: car.id);
    modeNow.mode = m;
    final d = s.data;
    expect(modeNow.showOf(d, report), CatShow.show);
    expect(modeNow.showOf(d, tyres), CatShow.quiet);
    expect(modeNow.breakThrough(d, tax, now), 'Due today');
    expect(modeNow.breakThrough(d, mot, now), 'Overdue');
    expect(modeNow.breakThrough(d, starred, now), 'Starred');
    expect(modeNow.breakThrough(d, gutters, now), isNull);
    expect(d.inMode(gutters), isFalse);
    expect(d.inMode(tyres), isTrue);
    m.starred = false;
    expect(d.inMode(starred), isFalse);
    // Planned on today's Day plan.
    s.planTime(gutters, DateTime(now.year, now.month, now.day, 23), 30);
    expect(modeNow.breakThrough(d, gutters, now), 'Planned today');
    // Peek shows everything.
    s.setPeek(true);
    expect(d.inMode(starred), isTrue);
    expect(tasksInMode(d, m, now), 6 - 1); // the starred one no longer breaks through
  });

  test('the board, Gantt and matrix leave out what the mode hides', () {
    final (s, m, work, home, _) = setUpWork();
    s.addTask('Kitchen quote', categoryId: work.id).kanban = true;
    s.addTask('Paint the shed', categoryId: home.id).kanban = true;
    expect(s.data.boardTasks.length, 2);
    modeNow.mode = m;
    expect(s.data.boardTasks.single.title, 'Kitchen quote');
  });

  test('the schedule picks the mode; a hand choice wins until it ends', () {
    final (s, m, _, _, _) = setUpWork();
    s.setModeSchedule([for (var d = 1; d <= 5; d++) ModeSlot(day: d, start: 8 * 60, end: 17 * 60, mode: m.id)]);
    s.refreshMode(now: at(16, 9));
    expect(modeNow.mode?.id, m.id);
    expect(modeNow.until, at(16, 17));
    expect(modeNow.byHand, isFalse);
    s.refreshMode(now: at(16, 18));
    expect(modeNow.mode, isNull);
    s.deviceModeChoice = ModeChoice(everythingId, at(17, 10), at: at(17, 8));
    s.refreshMode(now: at(17, 9));
    expect(modeNow.mode, isNull);
    expect(modeNow.byHand, isTrue);
    s.refreshMode(now: at(17, 10, 1));
    expect(modeNow.mode?.id, m.id);
    // The shared choice from another device, newer than this device's, wins.
    s.data.modeChoice = ModeChoice(m.id, null, at: at(17, 11));
    s.refreshMode(now: at(17, 20));
    expect(modeNow.mode?.id, m.id);
    expect(modeNow.byHand, isTrue);
  });

  test('the log fills in the schedule while the app was closed, and time adds up', () {
    final (s, m, _, _, _) = setUpWork();
    s.setModeSchedule([
      ModeSlot(day: 1, start: 8 * 60, end: 17 * 60, mode: m.id),
      ModeSlot(day: 2, start: 8 * 60, end: 17 * 60, mode: m.id),
    ]);
    s.data.modeLog.clear();
    s.refreshMode(now: at(16, 9)); // Work from 9
    s.refreshMode(now: at(17, 12)); // next day, Work again, app closed in between
    final logs = s.data.modeLog;
    expect([for (final l in logs) '${l.mode == m.id ? 'W' : 'E'} ${l.start.day}/${l.start.hour}-${l.end?.hour}'],
        ['W 16/9-17', 'E 16/17-8', 'W 17/8-null']);
    final minutes = minutesPerMode(logs, at(16, 0), at(17, 12), now: at(17, 12));
    expect(minutes[m.id], 8 * 60 + 4 * 60);
    expect(minutes[everythingId], 15 * 60);
  });

  test('overlapping stretches from two devices count once', () {
    final logs = [
      ModeLog(id: 'a', mode: 'w', start: at(16, 9), end: at(16, 12)),
      ModeLog(id: 'b', mode: 'w', start: at(16, 11), end: at(16, 13)),
    ];
    expect(minutesPerMode(logs, at(16, 0), at(17, 0))['w'], 4 * 60);
  });

  test('ticking off records the mode, and hidden tasks done count as breaking through', () {
    final (s, m, work, home, _) = setUpWork();
    final report = s.addTask('Report', categoryId: work.id);
    final tax = s.addTask('Tax', categoryId: home.id, due: DateTime.now().subtract(const Duration(hours: 1)));
    s.chooseMode(m.id);
    expect(modeNow.mode?.id, m.id);
    s.complete(report);
    s.complete(tax);
    expect(s.data.done[report.id]!.mode, m.id);
    expect(s.data.done[tax.id]!.outside, isTrue);
    final back = DoneRecord.fromJson(jsonDecode(jsonEncode(s.data.done[tax.id]!.toJson())) as Map<String, dynamic>);
    expect(back.outside, isTrue);
    final st = modeStats(s.data, DateTime.now().add(const Duration(minutes: 1)));
    expect(st.done[m.id], 2);
    expect(st.outside, 1);
    expect(st.byHand, 1);
  });

  test('starter modes guess categories from their names', () {
    final s = AppStore();
    final work = s.addCategory('Work'), house = s.addCategory('House'), trip = s.addCategory('Japan trip');
    s.addStarterModes();
    final byName = {for (final m in s.data.modes) m.name: m};
    expect(byName.keys, ['Work', 'Home office', 'Weekend', 'Travel']);
    expect(byName['Work']!.showFor(s.data, house.id), CatShow.hide);
    expect(byName['Home office']!.showFor(s.data, house.id), CatShow.quiet);
    expect(byName['Weekend']!.showFor(s.data, work.id), CatShow.hide);
    expect(byName['Travel']!.showFor(s.data, trip.id), CatShow.show);
    expect(byName['Work']!.newCategory, work.id);
    expect(s.data.modeSchedule.where((x) => x.mode == byName['Work']!.id).length, 5);
  });

  testWidgets('the list in a mode: chip, Still needs you, Quiet heading, resting and Peek', (tester) async {
    final (s, m, work, home, car) = setUpWork();
    m.toolsOff.add(ModeTool.calendar.name);
    s.addTask('Send the quote', categoryId: work.id);
    s.addTask('Pay the council tax', categoryId: home.id, due: DateTime.now().subtract(const Duration(hours: 2)));
    s.addTask('Clear the gutters', categoryId: home.id);
    s.addTask('Tyres', categoryId: car.id);
    s.setQuickFilter(QuickFilter.all);
    s.chooseMode(m.id);
    await tester.pumpWidget(TaskApp(store: s));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ModeTitle), findsOneWidget);
    expect(find.text('Work'), findsWidgets);
    expect(find.text('Still needs you'), findsOneWidget);
    expect(find.text('Home · Overdue'), findsOneWidget);
    expect(find.text('Send the quote'), findsOneWidget);
    expect(find.text('Clear the gutters'), findsNothing);
    expect(find.text('Quiet: Car'), findsOneWidget);
    expect(find.text('Tyres'), findsNothing);
    expect(find.byTooltip('Calendar'), findsNothing);
    await tester.tap(find.text('Quiet: Car'));
    await tester.pumpAndSettle();
    expect(find.text('Tyres'), findsOneWidget);
    await tester.tap(find.textContaining('resting. Peek'));
    await tester.pumpAndSettle();
    expect(find.text('Clear the gutters'), findsOneWidget);
    expect(find.textContaining('Back to Work'), findsOneWidget);
    // The chip opens the sheet, which goes back to Everything.
    await tester.tap(find.byType(ModeTitle));
    await tester.pumpAndSettle();
    expect(find.text('Keep it until'), findsOneWidget);
    await tester.tap(find.text('Everything'));
    await tester.pumpAndSettle();
    expect(modeNow.mode, isNull);
    expect(find.text('Clear the gutters'), findsOneWidget);
    expect(find.text('Still needs you'), findsNothing);
  });

  testWidgets('settings pages for modes and the schedule open', (tester) async {
    final (s, m, _, _, _) = setUpWork();
    s.setModeSchedule([ModeSlot(day: 1, start: 480, end: 1020, mode: m.id)]);
    for (final page in [ModesPage(store: s), ModeEditPage(store: s, mode: m), ModeSchedulePage(store: s)]) {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Mode schedule'), findsOneWidget);
    // Paint Tuesday morning by dragging down its column.
    final tue = find.text('Tue');
    final start = tester.getCenter(tue) + const Offset(0, 22 + 9 * 20.0);
    await tester.dragFrom(start, const Offset(0, 3 * 20.0));
    await tester.pumpAndSettle();
    expect(s.data.modeSchedule.where((x) => x.day == DateTime.tuesday), isNotEmpty);
  });

  group('part 2: reminders, habits, places, events', () {
    test('a hidden task\'s reminder waits and is listed when the mode ends; urgent ones still come', () {
      final (s, m, _, home, _) = setUpWork();
      s.setModeSchedule([for (var d = 1; d <= 5; d++) ModeSlot(day: d, start: 8 * 60, end: 17 * 60, mode: m.id)]);
      final gutters = s.addTask('Clear the gutters', categoryId: home.id);
      gutters.steps.add(TaskStep.create('Ladder')..dueAt = at(16, 10));
      s.addTask('Ring the plumber', categoryId: home.id, due: at(16, 11));
      s.refreshMode(now: at(16, 8));
      expect(modeNow.reach, at(16, 17));
      final plan = Reminders.plan(s.data, at(16, 8));
      // The step (no urgency) waits; the task due today breaks through.
      expect(plan.where((r) => r.title == 'Step due'), isEmpty);
      expect(plan.where((r) => r.title == 'Task due' && r.body == 'Ring the plumber'), hasLength(1));
      final summary = plan.where((r) => r.id == Reminders.heldSummaryId(0)).single;
      expect(summary.when, at(16, 17));
      expect(summary.title, 'Work is over: 1 reminder held');
      expect(summary.body, 'Clear the gutters');
      // Set to always show, it reminds as usual.
      gutters.alwaysShow = true;
      expect(Reminders.plan(s.data, at(16, 8)).where((r) => r.title == 'Step due'), hasLength(1));
      // In Everything nothing is held.
      s.refreshMode(now: at(16, 18));
      gutters.alwaysShow = false;
      gutters.steps.first.dueAt = at(16, 19);
      expect(Reminders.plan(s.data, at(16, 18)).where((r) => r.title == 'Step due'), hasLength(1));
    });

    test('habits in hidden categories pause, today and on past days the mode hid them', () {
      final (s, m, _, home, _) = setUpWork();
      final walk = s.addTask('Walk', categoryId: home.id);
      s.setHabit(walk, true);
      walk.habitRemind = 9 * 60;
      s.chooseMode(m.id);
      final today = DateTime.now();
      expect(pausedOn(walk, today), isTrue);
      expect(Reminders.plan(s.data, today).where((r) => r.title == 'Habit'), isEmpty);
      // A past day spent in Work at noon.
      final day = DateTime(2026, 11, 13);
      s.data.modeLog.add(ModeLog.open(m.id, DateTime(2026, 11, 13, 8), 'schedule')..end = DateTime(2026, 11, 13, 17));
      modeNow.noonModes = noonModesFrom(s.data, today);
      expect(pausedOn(walk, day), isTrue);
      expect(pausedOn(walk, DateTime(2026, 11, 12)), isFalse);
      // Switched off for the mode, or Everything today: not paused.
      m.pauseHabits = false;
      expect(pausedOn(walk, day), isFalse);
      m.pauseHabits = true;
      s.chooseMode(everythingId);
      expect(pausedOn(walk, today), isFalse);
    });

    test('event words match whole words; events come before places', () {
      expect(eventMatches('WFH day', ['wfh']), isTrue);
      expect(eventMatches('Flight to Rome', ['Trip', 'flight']), isTrue);
      expect(eventMatches('Inflight magazine', ['flight']), isFalse);
      expect(eventMatches('Work from home', ['work from home']), isTrue);
      final (s, m, _, _, _) = setUpWork();
      final travel = FocusMode.create('Travel')..events.add('flight');
      final office = FocusMode.create('Home office')
        ..places.add('Home')
        ..placeWhen = m.id;
      m.places.add('Office');
      s.addMode(travel);
      s.addMode(office);
      s.setModeSchedule([ModeSlot(day: 1, start: 8 * 60, end: 17 * 60, mode: m.id)]);
      final flight = [('e1', 'Flight to Rome', at(16, 7), at(16, 12))];
      expect(autoModeAt(s.data, at(16, 9), place: 'Office', events: flight)?.mode, travel.id);
      expect(autoModeAt(s.data, at(16, 9), place: 'Office', events: flight)?.until, at(16, 12));
      expect(autoModeAt(s.data, at(16, 13), place: 'Office', events: flight)?.mode, m.id);
      expect(autoModeAt(s.data, at(16, 13), place: 'office')?.reason, 'At office');
      // Home only means Home office while the schedule says Work.
      expect(autoModeAt(s.data, at(16, 13), place: 'Home')?.mode, office.id);
      expect(autoModeAt(s.data, at(16, 13), place: 'Home')?.until, at(16, 17));
      expect(autoModeAt(s.data, at(16, 18), place: 'Home'), isNull);
    });

    test('a place switches the mode, a hand choice beats it, and Ask waits for a yes', () {
      final (s, m, _, _, _) = setUpWork();
      final office = FocusMode.create('Home office')..places.add('Home');
      s.addMode(office);
      s.placeNow = 'Home';
      s.refreshMode(now: at(16, 9));
      expect(modeNow.mode?.id, office.id);
      expect(modeNow.reason, 'At Home');
      expect(s.takeAutoNote(), 'Switched to Home office: At Home');
      s.chooseMode(m.id);
      expect(modeNow.mode?.id, m.id);
      s.chooseMode(null);
      expect(modeNow.mode?.id, office.id);
      // Undo: that place no longer switches.
      s.answerAutoUndo();
      expect(modeNow.mode, isNull);
      // With Ask, a new place waits for a yes.
      s.data.modeAsk = true;
      m.places.add('Office');
      s.placeNow = 'Office';
      s.refreshMode();
      expect(modeNow.mode, isNull);
      expect(s.pendingAuto?.mode, m.id);
      s.answerAutoMode(true);
      expect(modeNow.mode?.id, m.id);
      expect(s.pendingAuto, isNull);
    });

    test('Always show keeps a task in view and survives saving', () {
      final (s, m, _, home, _) = setUpWork();
      final t = s.addTask('Passport', categoryId: home.id)..alwaysShow = true;
      s.chooseMode(m.id);
      expect(modeNow.showOf(s.data, t), CatShow.show);
      expect(s.data.inMode(t), isTrue);
      expect(Task.fromJson(jsonDecode(jsonEncode(t.toJson()))).alwaysShow, isTrue);
      final copy = FocusMode.fromJson(jsonDecode(jsonEncode((m
                ..places.add('Office')
                ..placeWhen = 'x'
                ..events.add('WFH')
                ..pauseHabits = false)
              .toJson())));
      expect([copy.places, copy.placeWhen, copy.events, copy.pauseHabits], [['Office'], 'x', ['WFH'], false]);
    });

    test('the nearest saved place the phone is inside', () {
      final home = Place.create('Home', 51.5, -0.12, radius: 150);
      final shop = Place.create('Shop', 51.501, -0.12, radius: 150);
      expect(placeAt([home, shop], 51.5003, -0.12)?.name, 'Home');
      expect(placeAt([home, shop], 51.5009, -0.12)?.name, 'Shop');
      expect(placeAt([home, shop], 51.52, -0.12), isNull);
      expect(metresBetween(51.5, -0.12, 51.501, -0.12), closeTo(111, 2));
    });
  });
}
