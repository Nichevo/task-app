import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/gantt.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/template_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/repeat_dialog.dart';

/// Item 114 F: project templates and smarter repeats.
void main() {
  group('repeats', () {
    test('the last Friday and the second Tuesday of the month', () {
      const lastFri = Repeat(unit: RepeatUnit.month, nth: -1, nthWeekday: DateTime.friday);
      final d = lastFri.nextDue(due: DateTime(2026, 11, 27, 9), completedAt: DateTime(2026, 11, 27, 10));
      expect(d, DateTime(2026, 12, 25, 9));
      expect(lastFri.nextDue(due: d, completedAt: d), DateTime(2027, 1, 29, 9));
      const secondTue = Repeat(unit: RepeatUnit.month, nth: 2, nthWeekday: DateTime.tuesday);
      expect(secondTue.nextDue(due: DateTime(2026, 11, 10), completedAt: DateTime(2026, 11, 10)), DateTime(2026, 12, 8));
      expect(lastFri.describe(), 'Every month on the last Friday');
    });

    test('the last working day, and weekends moved to Monday', () {
      const r = Repeat(unit: RepeatUnit.month, lastWorkday: true);
      expect(r.nextDue(due: DateTime(2026, 11, 30), completedAt: DateTime(2026, 11, 30)), DateTime(2026, 12, 31));
      expect(r.nextDue(due: DateTime(2026, 12, 31), completedAt: DateTime(2026, 12, 31)), DateTime(2027, 1, 29), reason: '31 Jan is a Sunday');
      const weekly = Repeat(unit: RepeatUnit.day, every: 1, skipWeekends: true);
      expect(weekly.nextDue(due: DateTime(2026, 11, 20), completedAt: DateTime(2026, 11, 20, 12)), DateTime(2026, 11, 23));
      const monthly = Repeat(unit: RepeatUnit.month, skipWeekends: true);
      expect(monthly.nextDue(due: DateTime(2026, 10, 21), completedAt: DateTime(2026, 10, 21)), DateTime(2026, 11, 23),
          reason: '21 Nov is a Saturday');
    });

    test('ends after N times or on a date', () {
      final s = AppStore();
      final t = s.addTask('Count stock')
        ..dueAt = DateTime(2026, 11, 2, 9)
        ..repeat = const Repeat(unit: RepeatUnit.week, left: 1);
      final next = s.complete(t, at: DateTime(2026, 11, 2, 10))!;
      expect(next.repeat!.left, 0);
      expect(next.repeat!.describe(), 'Every week (last time)');
      expect(s.complete(next, at: DateTime(2026, 11, 9, 10)), isNull, reason: 'the last one');
      const until = Repeat(unit: RepeatUnit.week, until: null);
      expect(until.allows(DateTime(2030)), isTrue);
      final u = Repeat(unit: RepeatUnit.week, until: DateTime(2026, 11, 20));
      expect(u.allows(DateTime(2026, 11, 20, 17)), isTrue);
      expect(u.allows(DateTime(2026, 11, 21)), isFalse);
      final back = Repeat.fromJson(u.toJson());
      expect(back.until, DateTime(2026, 11, 20));
      final r = Repeat.fromJson(const Repeat(unit: RepeatUnit.month, nth: -1, nthWeekday: 5, skipWeekends: true, left: 3).toJson());
      expect((r.nth, r.nthWeekday, r.skipWeekends, r.left), (-1, 5, true, 3));
    });

    test('skipping one counts towards the times', () {
      final s = AppStore();
      final t = s.addTask('Count stock')
        ..dueAt = DateTime(2026, 11, 2, 9)
        ..repeat = const Repeat(unit: RepeatUnit.week, left: 3);
      final undo = s.skip(t, at: DateTime(2026, 11, 2, 10));
      expect(t.repeat!.left, 2);
      undo();
      expect(t.repeat!.left, 3);
    });

    testWidgets('the dialog offers the month rules and ends', (tester) async {
      Repeat? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => got = await showDialog<Repeat>(
              context: c,
              builder: (_) => RepeatDialog(initial: const Repeat(unit: RepeatUnit.month), due: DateTime(2026, 11, 27)),
            ),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('The 27th of each month'), findsOneWidget);
      await tester.tap(find.text('The last Friday'));
      await tester.tap(find.text('Skip weekends'));
      await tester.tap(find.text('After N times'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((got!.nth, got!.nthWeekday, got!.skipWeekends, got!.left), (-1, DateTime.friday, true, 9));
    });
  });

  group('templates', () {
    ChecklistTemplate trip(AppStore s) {
      final tpl = s.saveTemplate('Overseas trip', ['Check passport', 'Book flights', 'Book hotel', 'Pack'])..dateLabel = 'departure date';
      tpl.items.addAll([
        TemplateStep(title: 'Check passport', offset: -56, days: 1),
        TemplateStep(title: 'Book flights', offset: -42, minutes: 60),
        TemplateStep(title: 'Book hotel', offset: -35, days: 1, after: [1]),
        TemplateStep(title: 'Pack', offset: -1, minutes: 90),
      ]);
      return tpl;
    }

    test('a new task from a template has its steps timed around its date', () {
      final s = AppStore();
      final tpl = trip(s);
      expect(tpl.project, isTrue);
      final t = s.newFromTemplate(tpl, title: 'Japan trip', date: DateTime(2027, 3, 13));
      expect(t.dueAt, DateTime(2027, 3, 13, 17));
      expect(t.gantt, isTrue);
      expect(t.steps.map((x) => x.title), ['Check passport', 'Book flights', 'Book hotel', 'Pack']);
      expect(t.steps[0].startAt, DateTime(2027, 1, 16));
      expect(t.steps[1].takesMinutes, 60);
      expect(t.steps[2].afterIds, [t.steps[1].id]);
      expect(t.steps[3].startAt, DateTime(2027, 3, 12));
    });

    test('saving a task as a template keeps lengths, links and timing', () {
      final s = AppStore();
      final t = s.newFromTemplate(trip(s), title: 'Japan trip', date: DateTime(2027, 3, 13));
      final tpl = s.templateFromTask(t, 'Trip again');
      expect(tpl.items[0].offset, daysBetween(DateTime(2027, 3, 13), stepBar(t, t.steps[0], s.data)!.start));
      expect(tpl.items[2].after, [1]);
      expect(tpl.items[1].minutes, 60);
      final back = ChecklistTemplate.fromJson(tpl.toJson());
      expect(back.items[2].after, [1]);
      expect(back.project, isTrue);
    });

    test('editing the step list keeps each step\'s timing', () {
      final s = AppStore();
      final tpl = trip(s);
      s.updateTemplate(tpl, steps: ['Book flights', 'Book hotel', 'Pack', 'Get yen']);
      expect(tpl.items.map((i) => i.offset), [-42, -35, -1, null]);
      expect(tpl.items[1].after, [0]);
    });

    test('a plain template still adds plain steps; starters are added once', () {
      final s = AppStore();
      final plain = s.saveTemplate('Monthly', ['Rent', 'Power']);
      final t = s.addTask('Bills');
      s.applyTemplate(t, plain);
      expect(t.steps.map((x) => x.startAt), [null, null]);
      expect(s.addStarterTemplates(), 4);
      expect(s.addStarterTemplates(), 0);
      final f = s.data.templates.firstWhere((x) => x.name == 'Demand forecast');
      final job = s.newFromTemplate(f, title: 'Q1 forecast', date: DateTime(2027, 2, 26));
      expect(job.steps.length, 8);
      expect(job.steps.last.afterIds, [job.steps[6].id]);
      expect(job.tags, ['forecast']);
    });

    testWidgets('the template page adds a timed step', (tester) async {
      final s = AppStore();
      final tpl = trip(s);
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: TemplatePage(store: s, template: tpl)));
      expect(find.text('8 weeks before'), findsOneWidget);
      expect(find.text('1 day before'), findsOneWidget);
      await tester.tap(find.text('Step'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unpack');
      await tester.tap(find.text('Starts a set time from the departure date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('before'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('after').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tpl.items.last.title, 'Unpack');
      expect(tpl.items.last.offset, 7);
      expect(tpl.steps.last, 'Unpack');
      expect(find.text('1 week after'), findsOneWidget);
    });
  });
}
