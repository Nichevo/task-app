import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/gantt.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';

/// Item 85: steps that come after other steps, and steps linked to existing tasks.
void main() {
  group('steps that come after steps (85)', () {
    test('moving a step later pushes the chain after it, skipping weekends', () {
      final s = AppStore();
      final t = s.addTask('Kitchen')..countWeekends = false;
      final a = s.addStep(t, 'Fit cabinets')
        ..startAt = DateTime(2026, 11, 23) // Monday
        ..takesDays = 3; // to Wed 25
      final b = s.addStep(t, 'Worktop')
        ..startAt = DateTime(2026, 11, 26)
        ..takesDays = 1
        ..dueAt = DateTime(2026, 11, 26, 17);
      final c = s.addStep(t, 'Tiling')
        ..startAt = DateTime(2026, 11, 27)
        ..takesDays = 2;
      chainSteps([a, b, c]);
      expect(b.afterIds, [a.id]);
      expect(c.afterIds, [b.id]);
      expect(stepClashes(t, b, s.data), isFalse);

      // Cabinets take two days longer: now end Fri 27.
      s.setStepPlan(t, a, start: a.startAt, takes: 5);
      expect(b.startAt, DateTime(2026, 11, 30)); // Monday, not Saturday
      expect(b.dueAt, DateTime(2026, 11, 30, 17)); // due moves with it
      expect(c.startAt, DateTime(2026, 12, 1));
      expect(stepClashes(t, c, s.data), isFalse);
    });

    test('never moves anything earlier, and Settings "never" leaves a red clash', () {
      final s = AppStore();
      final t = s.addTask('Garden')..countWeekends = true;
      final a = s.addStep(t, 'Dig')..startAt = DateTime(2026, 12, 1);
      final b = s.addStep(t, 'Plant')..startAt = DateTime(2026, 12, 10);
      s.setStepAfter(t, b, [a.id]);
      expect(b.startAt, DateTime(2026, 12, 10));

      s.data.ganttPush = GanttPush.never;
      s.setStepPlan(t, a, start: DateTime(2026, 12, 9), takes: 3);
      expect(b.startAt, DateTime(2026, 12, 10));
      expect(stepClashes(t, b, s.data), isTrue);
    });

    test('loops are refused and links survive a sync', () {
      final s = AppStore();
      final t = s.addTask('Trip');
      final a = s.addStep(t, 'Book');
      final b = s.addStep(t, 'Pack');
      final c = s.addStep(t, 'Go');
      chainSteps([a, b, c]);
      expect(stepWouldLoop(t, a, c), isTrue);
      expect(stepWouldLoop(t, a, a), isTrue);
      expect(stepWouldLoop(t, c, a), isFalse);
      expect(stepAfterLabel(t, c), 'After "Pack"');

      final back = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson()))).task(t.id)!;
      expect(back.steps[2].afterIds, [b.id]);

      s.removeStep(t, b);
      expect(c.afterIds, isEmpty);
    });
  });

  group('link a step to an existing task (85)', () {
    test('ticking that task off ticks the step; an already ticked one ticks it now', () {
      final s = AppStore();
      final t = s.addTask('Move house');
      final other = s.addTask('Book van');
      final step = s.addStep(t, 'Van');
      s.linkStep(t, step, other);
      expect(step.taskId, other.id);
      expect(step.done, isFalse);
      s.complete(other);
      expect(step.done, isTrue);

      final done = s.addTask('Get boxes');
      s.complete(done);
      final step2 = s.addStep(t, 'Boxes');
      s.linkStep(t, step2, done);
      expect(step2.done, isTrue);

      s.unlinkStep(t, step2);
      expect(step2.taskId, isNull);
    });
  });
}
