import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/critical_path.dart';
import 'package:task_blocks/gantt.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/gantt_page.dart';
import 'package:task_blocks/screens/plan_back_page.dart';
import 'package:task_blocks/store.dart';

/// Item 114 D: critical path and when each bar should happen.
void main() {
  // A Monday a few weeks ahead.
  final mon = () {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day + 21);
    return DateTime(d.year, d.month, d.day + (DateTime.monday - d.weekday + 7) % 7);
  }();
  DateTime day(int n) => addDays(mon, n);

  /// The tender from the mock-up: brief (done) -> pricing 2d -> method 2d -> proof 2d, with case
  /// studies 1d and CVs 1d feeding proof too.
  (AppStore, Task, Map<String, TaskStep>) tender() {
    final s = AppStore();
    final t = s.addTask('Tender')
      ..gantt = true
      ..dueAt = day(11).add(const Duration(hours: 17));
    TaskStep step(String name, int start, int days, [List<TaskStep> after = const []]) {
      final x = s.addStep(t, name)
        ..startAt = day(start)
        ..takesDays = days;
      x.afterIds.addAll(after.map((a) => a.id));
      return x;
    }

    final brief = step('Read brief', 0, 1)
      ..done = true
      ..doneAt = day(0);
    final pricing = step('Pricing', 1, 2, [brief]);
    final cases = step('Case studies', 1, 1, [brief]);
    final method = step('Method statement', 3, 2, [pricing]);
    final cvs = step('Get CVs', 1, 1);
    final proof = step('Proof', 7, 2, [method, cases, cvs]);
    return (s, t, {'brief': brief, 'pricing': pricing, 'cases': cases, 'method': method, 'cvs': cvs, 'proof': proof});
  }

  group('critical path', () {
    test('chain, slack and finish', () {
      final (s, t, st) = tender();
      st['proof']!.startAt = day(8); // Tue next week, method ends Fri (day 4): Mon spare
      final r = criticalPath(stepItems(t, s.data), weekends: false);
      expect(r.finish, day(9));
      expect(r[st['proof']!.id]!.slack, 0);
      expect(r[st['method']!.id]!.slack, 1, reason: 'the Monday between');
      expect(r[st['cases']!.id]!.slack, 4);
      expect(r[st['cvs']!.id]!.slack, 4);
      expect(r.path.map((n) => n.item.title), ['Proof']);
      st['proof']!.startAt = day(5); // straight after (Sat -> Mon)
      final r2 = criticalPath(stepItems(t, s.data), weekends: false);
      expect(r2.path.map((n) => n.item.title), ['Pricing', 'Method statement', 'Proof']);
      expect(describeSlack(r2[st['cases']!.id]!), '3 d spare');
    });

    test('worked back from the due date: start no later than', () {
      final (s, t, st) = tender();
      st['proof']!.startAt = day(7);
      final r = taskStepPath(t, s.data)!;
      expect(r.anchor, day(11));
      expect(r[st['proof']!.id]!.lf, day(11));
      expect(r[st['proof']!.id]!.ls, day(10));
      expect(r[st['method']!.id]!.lf, day(9));
      expect(r[st['pricing']!.id]!.ls, day(4));
      expect(r.path.first.item.title, 'Pricing');
    });

    test('earliest starts from a day', () {
      final (s, t, st) = tender();
      final r = criticalPath(stepItems(t, s.data, undated: true), weekends: false, from: day(1));
      expect(r[st['pricing']!.id]!.es, day(1));
      expect(r[st['method']!.id]!.es, day(3));
      expect(r[st['proof']!.id]!.es, day(7), reason: 'after the weekend');
    });
  });

  group('timing', () {
    test('as soon as possible pulls a step up to what it comes after, and pushes it', () {
      final (s, t, st) = tender();
      st['proof']!.timing = Timing.asap.id;
      s.keepStepOrder(t);
      expect(st['proof']!.startAt, day(7), reason: 'Fri end, next working day is Mon (day 7)');
      st['method']!.takesDays = 1;
      s.keepStepOrder(t);
      expect(stepBar(t, st['proof']!, s.data)!.start, day(4));
    });

    test('as late as possible ends right before what needs it, or the due date', () {
      final (s, t, st) = tender();
      st['cases']!.timing = Timing.alap.id;
      st['cvs']!.timing = Timing.alap.id;
      st['proof']!.timing = Timing.alap.id;
      s.keepStepOrder(t);
      expect(stepBar(t, st['proof']!, s.data)!.end, day(11));
      expect(stepBar(t, st['cases']!, s.data)!.end, day(9));
      expect(stepBar(t, st['cvs']!, s.data)!.start, day(9));
    });

    test('must finish by works back from its due date; fixed stays', () {
      final (s, t, st) = tender();
      final m = st['method']!;
      s.setTiming(t, m, Timing.finishBy);
      expect(m.dueAt, isNotNull);
      expect(m.startAt, isNull);
      expect(stepBar(t, m, s.data)!.start, day(3));
      s.setTiming(t, st['cvs']!, Timing.fixed);
      st['cvs']!.startAt = day(2);
      s.keepStepOrder(t);
      expect(st['cvs']!.startAt, day(2));
    });

    test('a start picked by hand makes it fixed; new items get the default', () {
      final s = AppStore();
      final t = s.addTask('X');
      expect(t.timing, 'asap');
      final st = s.addStep(t, 'one')..timing = Timing.asap.id;
      s.setStepPlan(t, st, start: mon, takes: 1);
      expect(st.timing, 'fixed');
      s.data.newTiming = Timing.alap;
      expect(s.addTask('Y').timing, 'alap');
      s.setHelper(Helper.criticalPath, false);
      expect(s.addTask('Z').timing, isNull);
    });

    test('tasks: as soon as possible follows the task before it', () {
      final s = AppStore();
      final a = s.addTask('A')
        ..gantt = true
        ..startAt = day(0)
        ..takesDays = 3;
      final b = s.addTask('B')
        ..gantt = true
        ..startAt = day(7)
        ..takesDays = 2
        ..afterTaskId = a.id
        ..timing = Timing.asap.id;
      s.keepTaskTimings();
      expect(b.startAt, day(3));
      s.moveOnGantt(a, 1);
      expect(a.timing, 'fixed');
      expect(b.startAt, day(4));
      final r = tasksPath([a, b], s.data)!;
      expect(r.path.map((n) => n.item.task), [a, b]);
    });

    test('timing survives a save', () {
      final (s, t, st) = tender();
      t.timing = 'alap';
      st['cases']!.timing = 'finishBy';
      final back = AppData.fromJson(s.data.toJson());
      final bt = back.active.single;
      expect(bt.timing, 'alap');
      expect(bt.steps.firstWhere((x) => x.title == 'Case studies').timing, 'finishBy');
    });
  });

  group('screens', () {
    Finder bar(String title) =>
        find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('$title\n')).first;

    testWidgets('the critical path button colours the chain and sums it up', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppStore();
      final today = dayOf(DateTime.now());
      final a = s.addTask('Survey')
        ..gantt = true
        ..startAt = today
        ..takesDays = 2
        ..countWeekends = true;
      s.addTask('Build')
        ..gantt = true
        ..startAt = addDays(today, 2)
        ..takesDays = 3
        ..countWeekends = true
        ..afterTaskId = a.id;
      s.addTask('Side job')
        ..gantt = true
        ..startAt = today
        ..takesDays = 1
        ..countWeekends = true;
      s.data.ganttWeekends = true;
      await tester.pumpWidget(MaterialApp(home: GanttPage(store: s)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Critical path'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Critical path: Survey → Build'), findsOneWidget);
      expect(find.text('4 d spare'), findsOneWidget);
      s.setHelper(Helper.criticalPath, false);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Critical path'), findsNothing);
      expect(find.textContaining('Critical path:'), findsNothing);
    });

    testWidgets('tapping a bar asks when it should happen', (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppStore();
      final today = dayOf(DateTime.now());
      final a = s.addTask('Survey')
        ..gantt = true
        ..startAt = today
        ..takesDays = 2
        ..countWeekends = true;
      final b = s.addTask('Build')
        ..gantt = true
        ..startAt = addDays(today, 5)
        ..takesDays = 2
        ..countWeekends = true
        ..afterTaskId = a.id
        ..timing = null;
      await tester.pumpWidget(MaterialApp(home: GanttPage(store: s)));
      await tester.pumpAndSettle();
      await tester.tap(bar('Build'));
      await tester.pumpAndSettle();
      expect(find.text('When should it happen?'), findsOneWidget);
      expect(find.textContaining('comes after Survey'), findsOneWidget);
      await tester.tap(find.text('As soon as possible'));
      await tester.pumpAndSettle();
      expect(b.timing, 'asap');
      expect(b.startAt, addDays(today, 2));
      await tester.tap(find.text('+1 day'));
      await tester.pumpAndSettle();
      expect(b.startAt, addDays(today, 3));
      expect(b.timing, 'fixed', reason: 'moved by hand');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('When should it happen?'), findsNothing);
    });

    testWidgets('plan back from the due date sets every step', (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (s, t, st) = tender();
      for (final x in t.steps) {
        x.startAt = null;
      }
      await tester.pumpWidget(MaterialApp(home: PlanBackPage(store: s, task: t, today: mon)));
      await tester.pumpAndSettle();
      expect(find.text('START NO LATER THAN'), findsOneWidget);
      expect(find.text('Pricing'), findsOneWidget);
      expect(find.text('sets the start'), findsNWidgets(3));
      await tester.tap(find.text('Set these dates'));
      await tester.pumpAndSettle();
      expect(st['proof']!.startAt, day(10));
      expect(st['method']!.startAt, day(8));
      expect(st['pricing']!.startAt, day(4));
      expect(st['cases']!.startAt, day(9));
    });
  });
}
