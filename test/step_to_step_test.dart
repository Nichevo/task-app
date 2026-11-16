import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/step_links.dart';

/// Item 106: linking a step to another step, and the smarter link picker.
void main() {
  group('link a step to a step (106)', () {
    test('ticking the other step ticks this one, across tasks and along a chain', () {
      final s = AppStore();
      final a = s.addTask('House');
      final b = s.addTask('Garden');
      final pay = s.addStep(a, 'Pay builder');
      final fence = s.addStep(b, 'Fence paid');
      final note = s.addStep(b, 'Tell neighbour');
      s.linkStepToStep(b, fence, pay);
      s.linkStepToStep(b, note, fence);
      expect(fence.linkStepId, pay.id);
      expect(fence.done, isFalse);

      s.toggleStep(a, pay);
      expect(fence.done, isTrue);
      expect(note.done, isTrue);

      // Unticking leaves the linked ones ticked, like a linked task.
      s.toggleStep(a, pay);
      expect(fence.done, isTrue);
    });

    test('linking to a ticked step ticks it now; a step has a task or a step link, not both', () {
      final s = AppStore();
      final t = s.addTask('Trip');
      final other = s.addTask('Visa');
      final a = s.addStep(t, 'Book');
      final b = s.addStep(t, 'Pack');
      s.toggleStep(t, a);
      s.linkStep(t, b, other);
      expect(b.taskId, other.id);
      s.linkStepToStep(t, b, a);
      expect(b.taskId, isNull);
      expect(b.linkStepId, a.id);
      expect(b.done, isTrue);
      s.unlinkStep(t, b);
      expect(b.linkStepId, isNull);
    });

    test('a two-way link does not loop, and the link survives a save', () {
      final s = AppStore();
      final t = s.addTask('Party');
      final a = s.addStep(t, 'Cake');
      final b = s.addStep(t, 'Candles');
      s.linkStepToStep(t, a, b);
      s.linkStepToStep(t, b, a);
      s.toggleStep(t, a);
      expect(b.done, isTrue);

      final back = TaskStep.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect(back.linkStepId, b.id);
    });

    test('labels say which step and, for another task, where it is', () {
      final s = AppStore();
      final a = s.addTask('House');
      final b = s.addTask('Garden');
      final pay = s.addStep(a, 'Pay builder');
      final x = s.addStep(a, 'Snag list');
      final y = s.addStep(b, 'Fence');
      s.linkStepToStep(a, x, pay);
      s.linkStepToStep(b, y, pay);
      expect(stepLinkLabel(x, s.data, within: a), 'Step: Pay builder');
      expect(stepLinkLabel(y, s.data, within: b), 'Step: Pay builder (House)');
      expect(stepLinkedTask(y, s.data), a);
    });
  });

  group('link picker order (106)', () {
    test('steps in this task first, then the same category, then the rest', () {
      final s = AppStore();
      final work = TaskCategory.create('Work');
      final home = TaskCategory.create('Home');
      s.data.categories.addAll([work, home]);
      final other = s.addTask('Paint shed')..categoryId = home.id;
      final t = s.addTask('Report')..categoryId = work.id;
      final mate = s.addTask('Slides')..categoryId = work.id;
      final me = s.addStep(t, 'Write');
      final sib = s.addStep(t, 'Check');
      final ticked = s.addStep(t, 'Old');
      s.toggleStep(t, ticked);
      final mateStep = s.addStep(mate, 'Draft slides');
      final otherStep = s.addStep(other, 'Buy paint');

      final groups = linkChoices(s.data, t, me);
      expect([for (final g in groups) g.heading], ['Steps in this task', 'In Work', 'Everything else']);
      expect([for (final r in groups[0].rows) r.step], [sib]); // not itself, not ticked ones
      expect([for (final r in groups[1].rows) r.step?.title ?? r.task.title], ['Slides', mateStep.title]);
      expect([for (final r in groups[2].rows) r.step?.title ?? r.task.title], ['Paint shed', otherStep.title]);
    });

    test('search finds steps by name and keeps their task as a heading row', () {
      final s = AppStore();
      final t = s.addTask('Report');
      final me = s.addStep(t, 'Write');
      final a = s.addTask('Garden');
      s.addStep(a, 'Buy paint');
      s.addStep(a, 'Mow');
      final b = s.addTask('Paint shed');
      s.addStep(b, 'Sand');

      final groups = linkChoices(s.data, t, me, query: 'paint');
      expect(groups.single.heading, 'Other tasks');
      expect([for (final r in groups.single.rows) r.step?.title ?? '[${r.task.title}]'],
          ['[Garden]', 'Buy paint', '[Paint shed]', 'Sand']);
    });
  });
}
