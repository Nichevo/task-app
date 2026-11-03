import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/csv_import.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/native.dart';
import 'package:task_blocks/reminders.dart';
import 'package:task_blocks/screens/calendar_page.dart';
import 'package:task_blocks/store.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

void main() {
  group('step dates and notes (61)', () {
    test('a step keeps its date, reminder and note through JSON', () {
      final s = AppStore();
      final t = s.addTask('Move house');
      final st = s.addStep(t, 'Book the van');
      s.setStepDue(t, st, DateTime(2026, 11, 20, 9), remindBefore: 1440);
      s.setStepNote(t, st, '  Ask for the big one ');
      final back = roundTrip(s.data).active.single.steps.single;
      expect(back.dueAt, DateTime(2026, 11, 20, 9));
      expect(back.remindBefore, 1440);
      expect(back.note, 'Ask for the big one');
      s.setStepDue(t, st, null, remindBefore: 60);
      expect(st.remindBefore, isNull);
    });

    test('a repeat moves step dates along with the task', () {
      final t = Task.create('Monthly report')
        ..dueAt = DateTime(2026, 11, 30, 17)
        ..repeat = const Repeat(unit: RepeatUnit.month);
      t.steps.add(TaskStep.create('Draft')
        ..dueAt = DateTime(2026, 11, 27, 9)
        ..note = 'Use last month\'s');
      t.steps.add(TaskStep.create('Send'));
      final next = t.nextRepeat(DateTime(2026, 11, 30, 18));
      expect(next.dueAt, DateTime(2026, 12, 30, 17));
      expect(next.steps.first.dueAt, DateTime(2026, 12, 27, 9));
      expect(next.steps.first.note, 'Use last month\'s');
      expect(next.steps.last.dueAt, isNull);
    });

    test('step dates change the reminders key, done steps and other edits don\'t matter', () {
      final now = DateTime(2026, 11, 3);
      final s = AppStore();
      final t = s.addTask('Move house');
      final st = s.addStep(t, 'Book the van');
      final before = Reminders.scheduleKey(s.data, now);
      s.setStepDue(t, st, DateTime(2026, 11, 20, 9));
      expect(Reminders.scheduleKey(s.data, now), isNot(before));
    });

    test('CSV keeps step dates', () {
      final s = AppStore();
      final t = s.addTask('Move house');
      s.setStepDue(t, s.addStep(t, 'Book the van'), DateTime(2026, 11, 20, 9));
      s.addStep(t, 'Pack');
      final csv = buildCsv(s.data);
      expect(csv, contains('[ ] Book the van (due 2026-11-20 09:00); [ ] Pack'));
      final d = AppData();
      importCsvText(d, csv);
      expect(d.active.single.steps.first.title, 'Book the van');
      expect(d.active.single.steps.first.dueAt, DateTime(2026, 11, 20, 9));
      expect(d.active.single.steps.last.dueAt, isNull);
    });

    testWidgets('the calendar shows a dated step on its day with the task name', (tester) async {
      final s = AppStore();
      final t = s.addTask('Move house');
      s.setStepDue(t, s.addStep(t, 'Book the van'), DateTime(2026, 11, 20, 9));
      await tester.pumpWidget(MaterialApp(home: CalendarPage(store: s, initialDay: DateTime(2026, 11, 20))));
      await tester.pumpAndSettle();
      expect(find.text('Book the van'), findsOneWidget);
      expect(find.text('09:00 · Step of Move house'), findsOneWidget);
    });
  });

  group('split out (61)', () {
    test('a step becomes a task of its own, taking what it needs from the task', () {
      final s = AppStore();
      s.addCategory('Home');
      final t = s.addTask('Move house', categoryId: s.data.categories.single.id, box: MatrixBox.decide, star: true)
        ..dueAt = DateTime(2026, 12, 1, 17)
        ..place = 'Home'
        ..estimate = 30
        ..notes = 'Big job'
        ..repeat = const Repeat(unit: RepeatUnit.month);
      final st = s.addStep(t, 'Book the van');
      s.setStepNote(t, st, 'Ask for the big one');
      s.addStep(t, 'Pack');
      final (n, _) = s.splitOut(t, st);
      expect(t.steps.map((x) => x.title), ['Pack']);
      expect(n.title, 'Book the van');
      expect(n.categoryId, t.categoryId);
      expect(n.starred, isTrue);
      expect(n.place, 'Home');
      expect(n.estimate, 30);
      expect(n.matrixBox, 'decide');
      expect(n.dueAt, DateTime(2026, 12, 1, 17), reason: "the task's date when the step has none");
      expect(n.repeat, isNull);
      expect(n.steps, isEmpty);
      expect(n.notes, 'Ask for the big one');
      expect(n.splitFrom, t.id);
      expect(s.data.active.indexOf(n), s.data.active.indexOf(t) + 1);
      expect(roundTrip(s.data).task(n.id)!.splitFrom, t.id);
    });

    test("a dated step keeps its own date, and a step on the board keeps its stage and history", () {
      final s = AppStore();
      final t = s.addTask('Move house', board: true);
      s.setStepsOnBoard(t, true);
      final st = s.addStep(t, 'Book the van');
      s.moveStepToStage(t, st, s.data.stages[2], how: MoveHow.menu);
      s.setStepDue(t, st, DateTime(2026, 11, 20, 9), remindBefore: 60);
      final moves = st.moves.length;
      final (n, _) = s.splitOut(t, st);
      expect(n.dueAt, DateTime(2026, 11, 20, 9));
      expect(n.remindBefore, 60);
      expect(n.kanban, isTrue);
      expect(n.stageId, s.data.stages[2].id);
      expect(n.moves, hasLength(moves));
    });

    test('a step of a task on the board goes on the board in the task\'s stage', () {
      final s = AppStore();
      final t = s.addTask('Move house', board: true);
      s.setOnBoard(t, false);
      s.setOnBoard(t, true, stage: s.data.stages[1]);
      final (n, _) = s.splitOut(t, s.addStep(t, 'Pack'));
      expect(n.kanban, isTrue);
      expect(n.stageId, s.data.stages[1].id);
    });

    test('undo puts the step back where it was', () {
      final s = AppStore();
      final t = s.addTask('Move house');
      s.addStep(t, 'A');
      final b = s.addStep(t, 'B');
      s.addStep(t, 'C');
      final (n, undo) = s.splitOut(t, b);
      undo();
      expect(t.steps.map((x) => x.title), ['A', 'B', 'C']);
      expect(s.data.active.contains(n), isFalse);
      expect(s.data.deleted.containsKey(n.id), isTrue, reason: 'so other devices drop it too');
    });

    test('a step already made into a linked task frees that task', () {
      final s = AppStore();
      final t = s.addTask('Move house');
      final st = s.addStep(t, 'Book the van');
      final linked = s.stepToTask(t, st);
      final (n, undo) = s.splitOut(t, st);
      expect(n, same(linked));
      expect(n.splitFrom, t.id);
      expect(t.steps, isEmpty);
      undo();
      expect(t.steps.single.taskId, linked.id);
      expect(linked.splitFrom, isNull);
    });
  });

  group('calendar event as a step (58)', () {
    test('the event becomes a dated step and is not offered again', () {
      final s = AppStore();
      final t = s.addTask('Wedding');
      final e = CalendarEvent(
          id: 'ev1', calendarId: 'c', title: 'Suit fitting', start: DateTime(2026, 11, 14, 10, 30), allDay: false, location: 'High St');
      final st = s.addEventAsStep(t, e);
      expect(st.title, 'Suit fitting (Sat 14 Nov, 10:30)');
      expect(st.dueAt, DateTime(2026, 11, 14, 10, 30));
      expect(st.note, 'At High St');
      expect(s.data.stepTaskForEvent('ev1'), same(t));
      expect(roundTrip(s.data).active.single.steps.single.eventId, 'ev1');
      final allDay = s.addEventAsStep(
          t, CalendarEvent(id: 'ev2', calendarId: 'c', title: 'Stag do', start: DateTime(2026, 11, 21), allDay: true));
      expect(allDay.dueAt, DateTime(2026, 11, 21, 9));
      expect(allDay.title, 'Stag do (Sat 21 Nov)');
    });
  });

  test('the email check while open is a device setting, saved with the device backup (70)', () {
    final s = AppStore();
    expect(s.emailCheckMinutes, 0);
    s.setEmailCheckMinutes(60);
    expect(s.deviceSettingsBackup()['emailCheckMinutes'], 60);
    s.setEmailCheckMinutes(0);
    expect(s.deviceSettingsBackup().containsKey('emailCheckMinutes'), isFalse);
  });
}
