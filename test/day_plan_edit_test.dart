import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/day_plan.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/modes.dart';
import 'package:task_blocks/screens/day_plan_page.dart';
import 'package:task_blocks/screens/task_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/day_plan_add.dart';

/// Item 109 (1.12.10): editing from the Day plan. A tap on a block opens its task, a tap on an
/// empty time adds a task or a step there, and a focus mode starts the Day plan on its own
/// categories.
void main() {
  final today = DateTime.now();
  DateTime at(int h, [int m = 0]) => DateTime(today.year, today.month, today.day, h, m);

  setUp(() {
    modeNow
      ..mode = null
      ..peek = false;
    modeChipTweaks.clear();
  });

  /// Work shown, Home hidden, Car quiet.
  (AppStore, FocusMode, TaskCategory, TaskCategory, TaskCategory) setUpWork() {
    final s = AppStore();
    final work = s.addCategory('Work'), home = s.addCategory('Home'), car = s.addCategory('Car');
    final m = FocusMode.create('Work')
      ..cats[work.id] = CatShow.show
      ..cats[home.id] = CatShow.hide
      ..cats[car.id] = CatShow.quiet
      ..cats[''] = CatShow.hide;
    s.addMode(m);
    return (s, m, work, home, car);
  }

  group('focus mode categories', () {
    test('in a mode only the categories it shows are on; the saved choice is untouched', () {
      final (s, m, work, home, car) = setUpWork();
      expect(dayPlanHidden(s.data), isEmpty);
      modeNow.mode = m;
      expect(dayPlanHidden(s.data), {home.id, car.id, ''});
      toggleDayPlanCategory(s.data, car.id);
      expect(dayPlanHidden(s.data), {home.id, ''});
      expect(modeChipsChanged(s.data), isTrue);
      expect(s.data.dayPlan.hiddenCategories, isEmpty);
      // Opening the Day plan again starts from the mode.
      modeChipTweaks.clear();
      expect(dayPlanHidden(s.data), {home.id, car.id, ''});
      modeNow.mode = null;
      toggleDayPlanCategory(s.data, work.id);
      expect(s.data.dayPlan.hiddenCategories, {work.id});
    });

    test('quiet categories leave the plan in a mode, but what still needs you stays', () {
      final (s, m, work, _, car) = setUpWork();
      final report = s.addTask('Report', categoryId: work.id);
      final tyres = s.addTask('Tyres', categoryId: car.id);
      final wof = s.addTask('WOF', categoryId: car.id, due: at(0).subtract(const Duration(days: 1)));
      for (final t in [report, tyres, wof]) {
        s.planTime(t, at(9), 30);
      }
      modeNow.mode = m;
      final l = layoutDay(s.data, at(0));
      final hidden = {for (final b in l.blocks) b.task.title: b.hidden};
      expect(hidden, {'Report': false, 'Tyres': true, 'WOF': false});
    });

    testWidgets('the Day plan opens with the mode chip and only its categories selected', (tester) async {
      final (s, m, work, home, _) = setUpWork();
      modeNow.mode = m;
      await tester.pumpWidget(MaterialApp(home: DayPlanPage(store: s, initialDay: at(0), events: const [])));
      await tester.pumpAndSettle();
      expect(find.text('Work mode'), findsOneWidget);
      FilterChip chip(String name) => tester.widget<FilterChip>(find.widgetWithText(FilterChip, name));
      expect(chip('Work').selected, isTrue);
      expect(chip('Home').selected, isFalse);
      expect(chip('Car').selected, isFalse);
      await tester.tap(find.widgetWithText(FilterChip, 'Car'));
      await tester.pumpAndSettle();
      expect(chip('Car').selected, isTrue);
      // The mode chip now puts the mode's categories back.
      await tester.tap(find.widgetWithText(ActionChip, 'Work'));
      await tester.pumpAndSettle();
      expect(chip('Car').selected, isFalse);
      expect(s.data.dayPlan.hiddenCategories, isEmpty);
    });
  });

  group('owners', () {
    test('tasks planned around the time come first, then what the plan shows', () {
      final s = AppStore();
      final a = s.addTask('Far'), b = s.addTask('Near'), c = s.addTask('Unplanned'), d = s.addTask('Starred')..starred = true;
      s.planTime(a, at(8), 30);
      s.planTime(b, at(13), 60);
      expect(ownerChoices(s.data, at(14, 15)), [b, a, d, c]);
      expect(ownerChoices(s.data, at(13, 30), exclude: b).first, a);
    });

    test('making a planned task a step keeps its time, and splitting it out gives it back', () {
      final s = AppStore();
      final parent = s.addTask('House'), t = s.addTask('Ring builder');
      final slot = s.planTime(t, at(10), 45);
      final (step, undo) = s.makeStep(t, parent);
      expect(parent.slots.single.stepId, step.id);
      expect(parent.slots.single.start, at(10));
      final l = layoutDay(s.data, at(0));
      expect(l.blocks.single.step, step);
      undo();
      expect(parent.slots, isEmpty);
      expect(t.slots.single, slot);

      final (step2, _) = s.makeStep(t, parent);
      s.updateSlot(parent, parent.slots.single, start: at(11));
      final (back, _) = s.splitOut(parent, step2);
      expect(parent.slots, isEmpty);
      expect(back.ownSlots.single.start, at(11));
    });
  });

  group('taps', () {
    Future<AppStore> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 900);
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

    testWidgets('a tap on a block opens its task; ⋮ has the Day plan choices', (tester) async {
      await open(tester);
      await tester.tap(find.text('Mow lawn'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Change the time…'), findsOneWidget);
      expect(find.text('Make it a step of…'), findsOneWidget);
    });

    testWidgets('a tap on an empty time adds a step to the task planned there', (tester) async {
      final s = await open(tester);
      // 1.5 px a minute: an hour and a half below the block's top is 11:30.
      final top = tester.getTopLeft(find.text('Mow lawn'));
      await tester.tapAt(top + const Offset(60, 135 - 6));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add to'), findsOneWidget);
      expect(find.text('11:30'), findsOneWidget);
      await tester.tap(find.text('New step'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Edges');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mow lawn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add step'));
      await tester.pumpAndSettle();
      final t = s.data.active.single;
      expect(t.steps.single.title, 'Edges');
      expect(t.slotsOf(t.steps.single).single.start, at(11, 30));
    });

    testWidgets('or a new task there', (tester) async {
      final s = await open(tester);
      final top = tester.getTopLeft(find.text('Mow lawn'));
      await tester.tapAt(top + const Offset(60, 135 - 6));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Call Sam');
      await tester.pump();
      expect(find.text('Add task'), findsOneWidget);
      await tester.tap(find.text('Add task'));
      await tester.pumpAndSettle();
      final t = s.data.active.firstWhere((t) => t.title == 'Call Sam');
      expect(t.ownSlots.single.start, at(11, 30));
      expect(t.ownSlots.single.minutes, s.data.dayPlan.length);
      expect(find.textContaining('Added "Call Sam" at 11:30'), findsOneWidget);
    });
  });

  test('item 113: the Day plan search finds open steps, with their task', () {
    final s = AppStore();
    final t = s.addTask('AI showcase');
    s.addStep(t, 'Poster group review');
    s.addStep(t, 'Plotter training');
    t.steps.last.done = true;
    s.addTask('Poster printing');
    final all = ownerChoices(s.data, DateTime.now());
    expect(matchingSteps(all, ''), isEmpty);
    final hits = matchingSteps(all, 'poster');
    expect(hits.map((p) => (p.task.title, p.step!.title)), [('AI showcase', 'Poster group review')]);
    expect(matchingSteps(all, 'plotter'), isEmpty); // ticked
  });
}
