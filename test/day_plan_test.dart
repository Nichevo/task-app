import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/day_plan.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/calendar_page.dart';
import 'package:task_blocks/screens/day_plan_page.dart';
import 'package:task_blocks/store.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

// Monday 16 November 2026.
final mon = DateTime(2026, 11, 16);
DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 16, h, m);

/// Item 101: the Day plan.
void main() {
  group('saving', () {
    test('planned times, the switch and the settings survive a round trip', () {
      final s = AppStore();
      final t = s.addTask('Renew car insurance');
      final st = s.addStep(t, 'Ring the insurer');
      s.planTime(t, at(11, 45), 30, step: st, gap: 5);
      s.planTime(t, at(9), 120, shared: true);
      s.data.dayPlan
        ..snap = 10
        ..hiddenCategories.add('');
      s.data.categories.add(TaskCategory.create('Work')..dayPlan = true);
      final back = roundTrip(s.data);
      final bt = back.active.single;
      expect(bt.dayPlan, isTrue);
      expect(bt.slots, hasLength(2));
      expect(bt.slots.first.stepId, st.id);
      expect(bt.slots.first.gapAfter, 5);
      expect(bt.slots.last.shared, isTrue);
      expect(bt.slots.last.end, at(11));
      expect(back.dayPlan.snap, 10);
      expect(back.dayPlan.gapMinutes, 10, reason: 'the gap follows the time step by default');
      expect(back.dayPlan.hiddenCategories, {''});
      expect(back.categories.last.dayPlan, isTrue);
    });

    test('a broken planned time is dropped, not the task', () {
      final j = (AppStore().addTask('x')).toJson()
        ..['slots'] = [
          {'id': 'a', 'start': 'nonsense', 'min': 30},
          {'id': 'b', 'start': at(9).toIso8601String(), 'min': 30},
        ];
      expect(Task.fromJson(j).slots.single.id, 'b');
    });

    test('the next repeat keeps its times, moved with its due date', () {
      final s = AppStore();
      final t = s.addTask('Weekly review')
        ..dueAt = at(17)
        ..repeat = Repeat(every: 1, unit: RepeatUnit.week);
      final st = s.addStep(t, 'Inbox zero');
      s.planTime(t, at(15, 15), 45);
      s.planTime(t, at(15, 15), 15, step: st);
      final next = s.complete(t)!;
      expect(next.slots.map((x) => x.start), [DateTime(2026, 11, 23, 15, 15), DateTime(2026, 11, 23, 15, 15)]);
      expect(next.slots.last.stepId, next.steps.single.id);
    });
  });

  group('layout', () {
    test('gaps follow blocks, free time fills working hours, clashes go side by side', () {
      final s = AppStore();
      final a = s.addTask('Clear the inbox'), b = s.addTask('Tax return'), c = s.addTask('Paint fence');
      s.planTime(a, at(8), 30);
      s.planTime(b, at(10), 90);
      s.planTime(c, at(11), 60);
      final l = layoutDay(s.data, mon);
      expect(l.gaps.first.start, at(8, 30));
      expect(l.gaps.first.end, at(8, 45), reason: 'default gap = 15 min time step');
      final bb = l.blocks.firstWhere((x) => x.task == b), cc = l.blocks.firstWhere((x) => x.task == c);
      expect(bb.clash && cc.clash, isTrue);
      expect([bb.column, cc.column], [0, 1]);
      expect(bb.columns, 2);
      expect(l.blocks.firstWhere((x) => x.task == a).clash, isFalse);
      expect(l.free.first.start, at(8, 45));
      expect(l.free.first.end, at(10));
      expect(l.free.last.start, at(12, 15), reason: 'after the later block and its gap');
      expect(l.free.last.end, at(17));
      expect(l.clashes, 2);
    });

    test('a gap is cut short by the next block', () {
      final s = AppStore();
      s.planTime(s.addTask('a'), at(9), 30);
      s.planTime(s.addTask('b'), at(9, 35), 30);
      final l = layoutDay(s.data, mon);
      expect(l.gaps.first.minutes, 5);
      expect(l.clashes, 0);
    });

    test('a block that leaves room: no clashes inside it and its time stays free', () {
      final s = AppStore();
      final backup = s.addTask('Run the backup');
      s.planTime(backup, at(9), 180, shared: true);
      final small = s.addTask('Book the dentist');
      s.planTime(small, at(9, 30), 30);
      final l = layoutDay(s.data, mon);
      final sm = l.blocks.firstWhere((x) => x.task == small);
      expect(sm.clash, isFalse);
      expect(sm.inBand, isTrue);
      expect(l.free.first.start, at(8));
      expect(l.free.first.end, at(9, 30), reason: 'the band itself is free time');
      expect(l.sharedMinutes, 30);
    });

    test('steps planned inside their task sit in its block; others stand alone', () {
      final s = AppStore();
      final t = s.addTask('Paint the fence');
      final sand = s.addStep(t, 'Sand'), coat = s.addStep(t, 'Coat'), buy = s.addStep(t, 'Buy paint');
      s.planTime(t, at(13), 180);
      s.planTime(t, at(13), 60, step: sand);
      s.planTime(t, at(14), 45, step: coat);
      s.planTime(t, at(10), 30, step: buy);
      final l = layoutDay(s.data, mon);
      expect(l.blocks, hasLength(2));
      final frame = l.blocks.firstWhere((b) => b.step == null);
      expect(frame.inside.map((b) => b.step), [sand, coat]);
      expect(frame.clash, isFalse);
      expect(l.blocks.firstWhere((b) => b.step != null).step, buy);

      s.data.dayPlan.show = DayShow.tasks;
      expect(layoutDay(s.data, mon).blocks.map((b) => b.step), [null]);
      s.data.dayPlan.show = DayShow.steps;
      expect(layoutDay(s.data, mon).blocks, hasLength(2), reason: 'the frame stays for its steps');
    });

    test('hidden categories shrink to strips that still take up time, or go', () {
      final s = AppStore();
      final work = TaskCategory.create('Work');
      s.data.categories.add(work);
      final t = s.addTask('Report')..categoryId = work.id;
      s.planTime(t, at(9), 60);
      s.data.dayPlan.hiddenCategories.add(work.id);
      var l = layoutDay(s.data, mon);
      expect(l.blocks.single.hidden, isTrue);
      expect(l.free.first.end, at(9));
      expect(l.hiddenMinutes, 60);
      s.data.dayPlan.hiddenStrip = false;
      l = layoutDay(s.data, mon);
      expect(l.blocks, isEmpty);
      expect(l.free.single.minutes, 9 * 60);
    });

    test('first free gap and how full the day is', () {
      final s = AppStore();
      s.planTime(s.addTask('a'), at(8), 120);
      final l = layoutDay(s.data, mon);
      expect(l.firstFree(60), at(10, 15));
      expect(l.firstFree(60, from: at(14)), at(14));
      expect(dayLoad(s.data, mon), closeTo(120 / 540, 1e-9));
    });
  });

  group('tray', () {
    test('what waits to be planned', () {
      final s = AppStore();
      final now = at(8);
      final onPlan = s.addTask('Order paint');
      s.setOnDayPlan(onPlan, true);
      final dueToday = s.addTask('Book dentist')..dueAt = at(16);
      final planned = s.addTask('Tax')..dueAt = at(17);
      s.planTime(planned, at(10), 60);
      final elsewhere = s.addTask('Garage');
      s.planTime(elsewhere, DateTime(2026, 11, 18, 9), 60);
      final missed = s.addTask('Inbox');
      s.planTime(missed, DateTime(2026, 11, 13, 8), 30);
      final work = TaskCategory.create('Work')..dayPlan = true;
      s.data.categories.add(work);
      final byCategory = s.addTask('Report')..categoryId = work.id;
      final tray = trayFor(s.data, mon, at: now);
      final tasks = tray.map((i) => i.task).toList();
      expect(tasks, containsAll([onPlan, dueToday, missed, byCategory]));
      expect(tasks, isNot(contains(planned)));
      expect(tasks, isNot(contains(elsewhere)), reason: 'it has a time on another day still to come');
      expect(tray.firstWhere((i) => i.task == missed).why, startsWith('Missed'));
      expect(tray.firstWhere((i) => i.task == dueToday).why, 'Due 16:00');
    });

    test('taking a task off the Day plan removes its open times', () {
      final s = AppStore();
      final t = s.addTask('x');
      s.planTime(t, at(9), 30);
      s.setOnDayPlan(t, false);
      expect(t.slots, isEmpty);
      expect(s.data.onDayPlan(t), isFalse);
    });
  });

  group('ticking', () {
    test('a step block ticks the step; the last one says so', () {
      final s = AppStore();
      final t = s.addTask('Fence');
      final a = s.addStep(t, 'Sand'), b = s.addStep(t, 'Coat');
      final sa = s.planTime(t, at(9), 30, step: a), sb = s.planTime(t, at(10), 30, step: b);
      expect(s.tickSlot(t, sa, now: at(9, 30)), SlotTick.step);
      expect(a.done, isTrue);
      expect(t.workedOn(mon), isTrue);
      expect(s.tickSlot(t, sb, now: at(10, 30)), SlotTick.lastStep);
      s.untickSlot(t, sb);
      expect(b.done, isFalse);
    });

    test('a task block with more time planned later counts as worked, else ticks it off', () {
      final s = AppStore();
      final t = s.addTask('Garage');
      final first = s.planTime(t, at(9), 60), second = s.planTime(t, DateTime(2026, 11, 17, 9), 60);
      expect(s.tickSlot(t, first, now: at(10)), SlotTick.worked);
      expect(t.closedAt, isNull);
      expect(s.tickSlot(t, second, now: DateTime(2026, 11, 17, 10)), SlotTick.done);
      expect(t.closedAt, isNotNull);
      expect(layoutDay(s.data, mon).blocks.single.done, isTrue, reason: 'ticked-off tasks still show that day');
    });
  });

  group('page', () {
    AppStore seeded() {
      final s = AppStore();
      final work = TaskCategory.create('Work');
      s.data.categories.add(work);
      final tax = s.addTask('File the tax return')..categoryId = work.id;
      s.planTime(tax, at(10), 90);
      final fence = s.addTask('Paint the back fence');
      final sand = s.addStep(fence, 'Sand the boards'), coat = s.addStep(fence, 'First coat');
      s.addStep(fence, 'Order paint');
      s.planTime(fence, at(13), 180);
      s.planTime(fence, at(13), 60, step: sand);
      s.planTime(fence, at(14), 45, step: coat);
      final backup = s.addTask('Run the backup');
      s.planTime(backup, at(8, 30), 90, shared: true);
      s.planTime(s.addTask('Book the dentist'), at(9), 30);
      s.planTime(s.addTask('Clash with tax'), at(11), 30);
      s.setOnDayPlan(s.addTask('Order fence paint'), true);
      return s;
    }

    Future<void> pump(WidgetTester tester, AppStore s, {Size size = const Size(412, 900)}) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s, initialDay: mon)));
      await tester.pumpAndSettle();
    }

    testWidgets('draws blocks, bands, steps inside, clashes and the tray', (tester) async {
      final s = seeded();
      await pump(tester, s);
      expect(tester.takeException(), isNull);
      expect(find.text('File the tax return'), findsOneWidget);
      expect(find.text('Sand the boards'), findsOneWidget);
      expect(find.text('Leaves room'), findsOneWidget);
      expect(find.text('Clash'), findsWidgets);
      expect(find.textContaining('To plan for'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      // Hiding Work leaves a strip.
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(find.text('File the tax return'), findsNothing);
      expect(find.textContaining('Hidden'), findsWidgets);
    });

    testWidgets('a wide screen shows the tray as a panel', (tester) async {
      await pump(tester, seeded(), size: const Size(1200, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('To plan · drag onto a time'), findsOneWidget);
    });

    testWidgets('ticking a block ticks its step', (tester) async {
      final s = seeded();
      await pump(tester, s);
      final fence = s.data.active.firstWhere((t) => t.title == 'Paint the back fence');
      final sand = fence.steps.first;
      await tester.scrollUntilVisible(find.text('Sand the boards'), 100, scrollable: find.byType(Scrollable).last);
      final box = find.ancestor(of: find.text('Sand the boards'), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: box, matching: find.byType(Checkbox)));
      await tester.pumpAndSettle();
      expect(sand.done, isTrue);
    });

    testWidgets('the Calendar opens in Day mode and remembers it', (tester) async {
      final s = seeded();
      tester.view.physicalSize = const Size(824, 1800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: CalendarPage(store: s, initialDay: mon)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Day plan'));
      await tester.pumpAndSettle();
      expect(find.byType(DayPlanPage), findsOneWidget);
      expect(s.calendarMode, 'day');
      await tester.tap(find.byTooltip('Month view'));
      await tester.pumpAndSettle();
      expect(find.byType(DayPlanPage), findsNothing);
    });
  });

  test('snapping and lengths', () {
    expect(snapTime(at(9, 7), 15), at(9, 0));
    expect(snapTime(at(9, 8), 15), at(9, 15));
    expect(describeLength(90), '1 h 30');
    expect(describeLength(45), '45 min');
    expect(describeLength(120), '2 h');
  });
}
