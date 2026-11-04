import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

/// Item 73: a task made into a step, and back, without losing anything. Item 74: top bar icons.
void main() {
  group('make into a step (73)', () {
    test('the step keeps the whole task, and split out brings it all back', () {
      final s = AppStore();
      s.addCategory('Home');
      final parent = s.addTask('Paint spare room');
      final t = s.addTask('Buy primer', categoryId: s.data.categories.single.id, star: true, box: MatrixBox.decide)
        ..dueAt = DateTime(2026, 11, 6, 17)
        ..remindBefore = 30
        ..notes = 'Low-odour one'
        ..estimate = 20
        ..place = 'Shop'
        ..repeat = const Repeat(unit: RepeatUnit.month)
        ..emails.add(TaskEmail(id: 'm1', subject: 'Quote'));
      s.addStep(t, 'Check stock');
      final created = t.createdAt;
      final id = t.id;

      final (step, _) = s.makeStep(t, parent);
      expect(s.data.active.contains(t), isFalse);
      expect(s.data.deleted.containsKey(id), isTrue, reason: 'other devices drop the task too');
      expect(parent.steps.single, step);
      expect(step.title, 'Buy primer');
      expect(step.dueAt, DateTime(2026, 11, 6, 17));
      expect(step.remindBefore, 30);
      expect(step.note, 'Low-odour one');

      // The saved copy survives a sync to an older-looking file and back.
      final back = roundTrip(s.data).task(parent.id)!.steps.single;
      expect(back.carriedTask!.emails.single.subject, 'Quote');

      final (n, _) = s.splitOut(parent, step);
      expect(parent.steps, isEmpty);
      expect(n.id, id);
      expect(n.createdAt, created);
      expect(n.starred, isTrue);
      expect(n.categoryId, s.data.categories.single.id);
      expect(n.matrixBox, 'decide');
      expect(n.estimate, 20);
      expect(n.place, 'Shop');
      expect(n.repeat, isNotNull);
      expect(n.emails.single.id, 'm1');
      expect(n.steps.single.title, 'Check stock');
      expect(n.notes, 'Low-odour one');
      expect(n.splitFrom, parent.id);
      expect(s.data.active.contains(n), isTrue);
      expect(roundTrip(s.data).task(id), isNotNull, reason: 'the old deletion mark no longer hides it');
    });

    test('changes made to the step come back with the task', () {
      final s = AppStore();
      final parent = s.addTask('Paint spare room');
      final t = s.addTask('Buy primer');
      final (step, _) = s.makeStep(t, parent);
      step.title = 'Buy primer and tape';
      s.setStepDue(parent, step, DateTime(2026, 11, 9, 10), remindBefore: 15);
      s.toggleStep(parent, step);
      final (n, _) = s.splitOut(parent, step);
      expect(n.title, 'Buy primer and tape');
      expect(n.dueAt, DateTime(2026, 11, 9, 10));
      expect(n.remindBefore, 15);
      expect(n.closedAt, step.doneAt, reason: 'ticked when the step was ticked, not when split out');
      expect(s.data.archived.contains(n), isTrue);
    });

    test('tasks that came after it, and steps linked to it, now point at the parent', () {
      final s = AppStore();
      final parent = s.addTask('Paint spare room');
      final t = s.addTask('Buy primer');
      final later = s.addTask('Paint')..afterTaskId = t.id;
      final other = s.addTask('Weekend jobs');
      final linkedStep = s.addStep(other, 'Primer')..taskId = t.id;
      s.makeStep(t, parent);
      expect(later.afterTaskId, parent.id);
      expect(linkedStep.taskId, parent.id);
    });

    test('its own steps: kept inside, added to the parent, or split out', () {
      for (final own in OwnSteps.values) {
        final s = AppStore();
        final parent = s.addTask('Paint spare room');
        s.addStep(parent, 'Tape');
        final t = s.addTask('Buy things');
        s.addStep(t, 'Primer');
        s.addStep(t, 'Rollers');
        final (step, _) = s.makeStep(t, parent, own: own);
        switch (own) {
          case OwnSteps.keep:
            expect(parent.steps.map((x) => x.title), ['Tape', 'Buy things']);
            expect(step.carriedTask!.steps.map((x) => x.title), ['Primer', 'Rollers']);
          case OwnSteps.addToParent:
            expect(parent.steps.map((x) => x.title), ['Tape', 'Primer', 'Rollers', 'Buy things']);
            expect(step.carriedTask!.steps, isEmpty);
          case OwnSteps.splitOut:
            expect(parent.steps.map((x) => x.title), ['Tape', 'Buy things']);
            expect(s.data.active.map((x) => x.title), containsAll(['Primer', 'Rollers']));
            expect(step.carriedTask!.steps, isEmpty);
        }
      }
    });

    test('undo puts everything back as it was', () {
      for (final own in OwnSteps.values) {
        final s = AppStore();
        final parent = s.addTask('Paint spare room');
        final t = s.addTask('Buy things');
        s.addStep(t, 'Primer');
        s.addStep(t, 'Rollers');
        final later = s.addTask('Paint')..afterTaskId = t.id;
        final order = s.data.active.map((x) => x.id).toList();
        final (_, undo) = s.makeStep(t, parent, own: own);
        undo();
        expect(s.data.active.map((x) => x.id).toList(), order, reason: '$own');
        expect(t.steps.map((x) => x.title), ['Primer', 'Rollers'], reason: '$own');
        expect(parent.steps, isEmpty, reason: '$own');
        expect(later.afterTaskId, t.id);
        expect(s.data.deleted.containsKey(t.id), isFalse);
      }
    });

    test('on a board with steps showing, it keeps its own stage', () {
      final s = AppStore();
      final parent = s.addTask('Move house', board: true);
      s.setStepsOnBoard(parent, true);
      final t = s.addTask('Book van', board: true);
      s.setOnBoard(t, false);
      s.setOnBoard(t, true, stage: s.data.stages[2]);
      final (step, _) = s.makeStep(t, parent);
      expect(step.stageId, s.data.stages[2].id);
      expect(parent.boardSteps, contains(step));
    });
  });

  group('plain split out keeps more (73)', () {
    test('the calendar event link and the real tick time come along', () {
      final s = AppStore();
      final t = s.addTask('Trip');
      final st = s.addStep(t, 'Dentist')..eventId = 'ev1';
      s.toggleStep(t, st);
      final ticked = st.doneAt!;
      final (n, _) = s.splitOut(t, st);
      expect(n.eventId, 'ev1');
      expect(n.closedAt, ticked);
    });

    test('a linked task takes the step\'s date, reminder and note', () {
      final s = AppStore();
      final t = s.addTask('Trip');
      final st = s.addStep(t, 'Dentist');
      s.setStepDue(t, st, DateTime(2026, 12, 2, 9), remindBefore: 60);
      s.setStepNote(t, st, 'Bring card');
      final linked = s.stepToTask(t, st);
      expect(linked.dueAt, DateTime(2026, 12, 2, 9));
      expect(linked.remindBefore, 60);
      expect(linked.notes, 'Bring card');
    });

    test('unticking a step clears its tick time; it survives JSON', () {
      final s = AppStore();
      final t = s.addTask('Trip');
      final st = s.addStep(t, 'Pack');
      s.toggleStep(t, st);
      expect(roundTrip(s.data).active.single.steps.single.doneAt, st.doneAt);
      s.toggleStep(t, st);
      expect(st.doneAt, isNull);
    });
  });

  group('top bar icons (74)', () {
    test('each icon can be switched off on this device and comes back from a backup', () async {
      final s = AppStore();
      expect(TopIcon.all.every(s.topIconShown), isTrue);
      s.setTopIcon(TopIcon.calendar, false);
      expect(s.topIconShown(TopIcon.calendar), isFalse);
      final backup = s.deviceSettingsBackup();
      final other = AppStore();
      await other.restoreDeviceSettings(DeviceBackup('phone', DateTime.now(), backup));
      expect(other.topIconShown(TopIcon.calendar), isFalse);
      expect(other.topIconShown(TopIcon.search), isTrue);
    });
  });
}
