import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/day_plan.dart';
import 'package:task_blocks/input_parse.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/native.dart';
import 'package:task_blocks/reminders.dart';
import 'package:task_blocks/screens/day_plan_page.dart';
import 'package:task_blocks/store.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

// Monday 16 November 2026.
final mon = DateTime(2026, 11, 16);
DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 16, h, m);

CalendarEvent event(String title, DateTime start, DateTime end, {bool allDay = false}) =>
    CalendarEvent(id: title, calendarId: '1', title: title, start: start, end: end, allDay: allDay);

/// Item 101, part 2 (1.11.1): calendar events, links, pushing, steps in order, reminders and
/// quick add.
void main() {
  test('the new settings survive a round trip', () {
    final d = AppData();
    expect(d.dayPlan.showEvents, isTrue);
    expect(d.dayPlan.remindStart, isTrue);
    d.dayPlan
      ..showEvents = false
      ..remindStart = false;
    final back = roundTrip(d);
    expect(back.dayPlan.showEvents, isFalse);
    expect(back.dayPlan.remindStart, isFalse);
  });

  group('calendar events', () {
    test('timed events clash, cut gaps short, use up free time and fill the day', () {
      final s = AppStore();
      s.planTime(s.addTask('Write report'), at(9), 60);
      final events = [
        event('Stand-up', at(10, 5), at(10, 20)),
        event('Dentist', at(14), at(15)),
        event('Lunch with Sam', at(9, 30), at(10)),
        event('Holiday', mon, mon.add(const Duration(days: 1)), allDay: true),
        event('Tomorrow', at(9).add(const Duration(days: 1)), at(10).add(const Duration(days: 1))),
      ];
      final l = layoutDay(s.data, mon, events: events);
      expect(l.events.map((e) => e.event.title), ['Lunch with Sam', 'Stand-up', 'Dentist']);
      expect(l.allDay.single.title, 'Holiday');
      // Lunch overlaps the report: both clash, side by side.
      final lunch = l.events.first;
      expect(lunch.clash, isTrue);
      expect(l.blocks.single.clash, isTrue);
      expect({lunch.column, l.blocks.single.column}, {0, 1});
      expect(l.clashes, 2);
      // The 15 minute gap after the report is cut short by the stand-up.
      expect(l.gaps.single.start, at(10));
      expect(l.gaps.single.end, at(10, 5));
      // Free time skips the events.
      expect(l.free.map((f) => f.start), [at(8), at(10, 20), at(15)]);
      expect(l.eventMinutes, 30 + 15 + 60);
      expect(dayLoad(s.data, mon, events: events), greaterThan(dayLoad(s.data, mon)));
    });

    test('turned off, events are left out', () {
      final s = AppStore()..data.dayPlan.showEvents = false;
      final l = layoutDay(s.data, mon, events: [event('Dentist', at(14), at(15))]);
      expect(l.events, isEmpty);
      expect(l.free.single.minutes, 9 * 60);
    });

    test('an event that sits over a band that leaves room sits on it', () {
      final s = AppStore();
      s.planTime(s.addTask('Backup'), at(9), 120, shared: true);
      final l = layoutDay(s.data, mon, events: [event('Call', at(9, 30), at(10))]);
      expect(l.events.single.inBand, isTrue);
      expect(l.events.single.clash, isFalse);
    });
  });

  group('links', () {
    test('a task planned before what it comes after is finished is too early', () {
      final s = AppStore();
      final a = s.addTask('Draft slides'), b = s.addTask('Rehearse talk')..afterTaskId = a.id;
      s.planTime(a, at(9), 60);
      s.planTime(b, at(9, 30), 30);
      var l = layoutDay(s.data, mon);
      final link = l.links.single;
      expect(link.from.task, a);
      expect(link.to.task, b);
      expect(link.tooEarly, isTrue);
      expect(l.tooEarly, 1);
      // Later the same day it's fine.
      s.updateSlot(b, b.slots.single, start: at(11));
      l = layoutDay(s.data, mon);
      expect(l.links.single.tooEarly, isFalse);
      expect(l.tooEarly, 0);
      // What it waits for planned on a later day also makes it too early.
      s.planTime(a, at(9).add(const Duration(days: 2)), 30);
      expect(layoutDay(s.data, mon).all.firstWhere((x) => x.task == b).tooEarly, isTrue);
    });

    test('steps linked within a task', () {
      final s = AppStore();
      final t = s.addTask('Paint the fence');
      final sand = s.addStep(t, 'Sand'), coat = s.addStep(t, 'Coat');
      coat.afterIds.add(sand.id);
      s.planTime(t, at(13), 30, step: coat);
      s.planTime(t, at(14), 60, step: sand);
      final l = layoutDay(s.data, mon);
      expect(l.links.single.from.step, sand);
      expect(l.links.single.to.step, coat);
      expect(l.all.firstWhere((b) => b.step == coat).tooEarly, isTrue);
    });
  });

  group('pushing what comes after', () {
    test('a longer block moves the chain behind it, until a free stretch takes up the slack', () {
      final s = AppStore();
      final a = s.addTask('A'), b = s.addTask('B'), c = s.addTask('C'), d = s.addTask('D');
      s.planTime(a, at(9), 60);
      s.planTime(b, at(10, 15), 45); // gap 15 after A
      s.planTime(c, at(11, 15), 30); // touching B (with gap)
      s.planTime(d, at(14), 30); // far enough away
      final pa = layoutDay(s.data, mon).blocks.firstWhere((x) => x.task == a);
      final moves = pushAfter(s.data, pa, at(9), 90);
      expect(moves.map((m) => m.task.title), ['B', 'C']);
      expect(moves.first.to, at(10, 45));
      expect(moves.last.to, at(11, 45));
      s.applyPlanMoves(moves);
      expect(b.slots.single.start, at(10, 45));
      expect(c.slots.single.start, at(11, 45));
      expect(d.slots.single.start, at(14));
      s.applyPlanMoves(moves, back: true);
      expect(b.slots.single.start, at(10, 15));
    });

    test('ticked blocks, bands and earlier blocks stay; steps inside move with their task', () {
      final s = AppStore();
      final a = s.addTask('A'), b = s.addTask('B'), band = s.addTask('Band'), early = s.addTask('Early');
      final st = s.addStep(b, 'Inside');
      s.planTime(early, at(8), 30);
      s.planTime(a, at(9), 60);
      s.planTime(band, at(9, 30), 120, shared: true);
      s.planTime(b, at(10, 15), 60);
      s.planTime(b, at(10, 30), 15, step: st);
      final pa = layoutDay(s.data, mon).blocks.firstWhere((x) => x.task == a);
      final moves = pushAfter(s.data, pa, at(9), 120);
      expect(moves.map((m) => m.slot), [b.ownSlots.single, b.slotsOf(st).single]);
      expect(moves.last.to, at(11, 30));
      s.data.active.firstWhere((t) => t == b).slots.first.doneAt = at(8);
      expect(pushAfter(s.data, pa, at(9), 120).where((m) => m.task == b && m.slot.stepId == null), isEmpty);
    });
  });

  group('steps back to back', () {
    test('in order, a step after the one it comes after, with gaps', () {
      final s = AppStore()..data.dayPlan.length = 20;
      final t = s.addTask('Move house');
      final pack = s.addStep(t, 'Pack'), book = s.addStep(t, 'Book van'), done = s.addStep(t, 'Done already');
      s.toggleStep(t, done);
      pack.afterIds.add(book.id);
      final added = s.planStepsInOrder(t, at(9));
      expect(added.map((x) => x.stepId), [book.id, pack.id]);
      expect(added.last.start, at(9, 35)); // 20 min + 15 gap
      expect(t.dayPlan, isTrue);
      s.removeSlots(t, added);
      expect(t.slots, isEmpty);
    });

    test('inside a block, sharing its time evenly with no gaps', () {
      final s = AppStore();
      final t = s.addTask('Fence');
      s.addStep(t, 'One');
      s.addStep(t, 'Two');
      s.addStep(t, 'Three');
      s.planTime(t, at(13), 90);
      final added = s.planStepsInOrder(t, at(13), within: 90);
      expect(added.map((x) => x.minutes), [30, 30, 30]);
      expect(added.last.end, at(14, 30));
      final l = layoutDay(s.data, mon);
      expect(l.blocks.single.inside, hasLength(3));
    });
  });

  group('reminders', () {
    test('one as each planned time starts, unless turned off', () {
      final s = AppStore();
      final t = s.addTask('Write report');
      final st = s.addStep(t, 'Outline');
      final sl = s.planTime(t, at(9), 60);
      s.planTime(t, at(10, 15), 30, step: st);
      final ticked = s.planTime(t, at(11), 30)..doneAt = at(8);
      final now = at(8);
      var plan = Reminders.plan(s.data, now).where((r) => r.title.startsWith('Planned now')).toList();
      expect(plan, hasLength(2));
      expect(plan.first.id, Reminders.slotReminderId(sl.id));
      expect(plan.first.when, at(9));
      expect(plan.first.title, 'Planned now, 09:00 to 10:00');
      expect(plan.last.body, contains('Outline'));
      expect(plan.any((r) => r.id == Reminders.slotReminderId(ticked.id)), isFalse);
      expect(Reminders.slotReminderId(sl.id), lessThan(-536870912 - 2), reason: 'never meets a step reminder id');
      s.data.dayPlan.remindStart = false;
      plan = Reminders.plan(s.data, now).where((r) => r.title.startsWith('Planned now')).toList();
      expect(plan, isEmpty);
    });

    test('moving a planned time reschedules', () {
      final s = AppStore();
      final t = s.addTask('Write report');
      final sl = s.planTime(t, at(9), 60);
      final k1 = Reminders.scheduleKey(s.data, at(8));
      s.updateSlot(t, sl, start: at(10));
      expect(Reminders.scheduleKey(s.data, at(8)), isNot(k1));
    });
  });

  group('quick add', () {
    final now = at(10);

    test('"@14:00 45m" plans a time today', () {
      final p = parseInput('Call the bank @14:00 45m', AppData(), now);
      expect(p.title, 'Call the bank');
      expect(p.planAt, at(14));
      expect(p.planMinutes, 45);
    });

    test('12-hour times, hours, and the due day', () {
      final p = parseInput('Mow the lawn tomorrow @2pm 1.5h', AppData(), now);
      expect(p.title, 'Mow the lawn');
      expect(p.planAt, at(14).add(const Duration(days: 1)));
      expect(p.planMinutes, 90);
    });

    test('a time already gone today means tomorrow; no length uses the default', () {
      final p = parseInput('Stretch @9', AppData(), now);
      expect(p.planAt, at(9).add(const Duration(days: 1)));
      expect(p.planMinutes, isNull);
    });

    test('email addresses and odd times are left alone', () {
      expect(parseInput('Mail jo@example.com', AppData(), now).planAt, isNull);
      expect(parseInput('Gate code @99', AppData(), now).planAt, isNull);
      expect(takePlanTime('x @7:30 90 min').minutes, 90);
    });

    test('adding the task gives it the time', () {
      final s = AppStore();
      final p = parseInput('Call the bank @14:00 45m', s.data, now);
      final t = s.addTask(p.title, due: p.due, plan: p.plan);
      expect(t.dayPlan, isTrue);
      expect(t.slots.single.start, at(14));
      expect(t.slots.single.minutes, 45);
      expect(t.estimate, 45);
      final q = parseInput('Stretch @9:30', s.data, now);
      final t2 = s.addTask(q.title, plan: q.plan);
      expect(t2.slots.single.minutes, s.data.dayPlan.length);
      expect(t2.estimate, isNull);
    });
  });

  testWidgets('the page draws events and all-day chips', (tester) async {
    final s = AppStore();
    s.planTime(s.addTask('Write report'), at(9), 60);
    tester.view.physicalSize = const Size(824, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DayPlanPage(store: s, initialDay: mon, events: [
        event('Team stand-up', at(9, 30), at(10)),
        event('Bank holiday', mon, mon.add(const Duration(days: 1)), allDay: true),
      ]),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Team stand-up', findRichText: true), findsOneWidget);
    expect(find.text('Bank holiday'), findsOneWidget);
    await tester.tap(find.text('Bank holiday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide calendar events'));
    await tester.pumpAndSettle();
    expect(s.data.dayPlan.showEvents, isFalse);
    expect(find.text('Bank holiday'), findsNothing);
  });

  testWidgets('the page shows "Too early" and draws the links', (tester) async {
    final s = AppStore();
    final a = s.addTask('Draft slides'), b = s.addTask('Rehearse talk')..afterTaskId = a.id;
    s.planTime(a, at(9), 90);
    s.planTime(b, at(10), 60);
    tester.view.physicalSize = const Size(824, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s, initialDay: mon)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Too early'), findsWidgets);
    expect(find.text('1 too early', skipOffstage: false), findsOneWidget);
    // The filter menu turns calendar events off.
    await tester.tap(find.byTooltip('Show'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar events'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(s.data.dayPlan.showEvents, isFalse);
  });
}
