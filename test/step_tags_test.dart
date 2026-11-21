import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/task_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/tags.dart';
import 'package:task_blocks/task_list.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

void main() {
  group('tags on steps (112)', () {
    test('step tags survive JSON and take the spelling in use', () {
      final s = AppStore();
      final t = s.addTask('Release');
      s.addTag(t, 'Coding');
      final st = s.addStep(t, 'Write tests');
      expect(s.addStepTag(t, st, '#coding'), isTrue);
      expect(s.addStepTag(t, st, 'CODING'), isFalse);
      s.addStepTag(t, st, 'review');
      expect(st.tags, ['Coding', 'review']);
      expect(roundTrip(s.data).active.single.steps.single.tags, ['Coding', 'review']);
      final old = TaskStep.fromJson({'id': 's1', 'title': 'Old'});
      expect(old.tags, isEmpty);
      expect(old.toJson().containsKey('tags'), isFalse);
      s.removeStepTag(t, st, 'REVIEW');
      expect(st.tags, ['Coding']);
    });

    test('#words typed into a new step become its tags', () {
      final s = AppStore();
      final t = s.addTask('Launch');
      s.addTag(s.addTask('Other'), 'Meeting');
      final st = s.addStep(t, 'Call the team #meeting #prep step #2', readTags: true);
      expect(st.title, 'Call the team step #2');
      expect(st.tags, ['Meeting', 'prep']);
      final only = s.addStep(t, '#idea', readTags: true);
      expect(only.title, '#idea');
      expect(only.tags, isEmpty);
      // Not typed by hand: left as it is.
      expect(s.addStep(t, 'Event #3 #x').title, 'Event #3 #x');
    });

    test('the filter lets a task through for an open step, and steps inherit the task tags', () {
      final s = AppStore();
      final a = s.addTask('Website'), b = s.addTask('Garden'), c = s.addTask('Plain');
      final code = s.addStep(a, 'Fix CSS');
      final copy = s.addStep(a, 'Write copy');
      s.addStepTag(a, code, 'coding');
      final dig = s.addStep(b, 'Dig');
      s.addTag(b, 'home');
      expect(passesTagFilter(a, {'coding'}), isTrue);
      expect(passesTagFilter(b, {'coding'}), isFalse);
      expect(passesTagFilter(c, {'coding'}), isFalse);
      expect(stepPassesTagFilter(a, code, {'Coding'}), isTrue);
      expect(stepPassesTagFilter(a, copy, {'coding'}), isFalse);
      expect(stepPassesTagFilter(b, dig, {'home'}), isTrue);
      // "No tag": a step with none of its own in a task with none.
      expect(stepPassesTagFilter(a, copy, {untaggedFilter}), isTrue);
      expect(stepPassesTagFilter(a, code, {untaggedFilter}), isFalse);
      expect(stepPassesTagFilter(b, dig, {untaggedFilter}), isFalse);
      // A ticked step no longer lets its task through.
      s.toggleStep(a, code);
      expect(passesTagFilter(a, {'coding'}), isFalse);
      // Step tags are in use, so a filter on them stays live.
      s.setTagFilter({'coding'});
      expect(s.liveTagFilter, {'coding'});
      expect(matchesSearch(a, '#coding', s.data), isTrue);
    });

    test('Settings rename and delete reach steps; counts include them', () {
      final s = AppStore();
      final a = s.addTask('a'), b = s.addTask('b');
      final st = s.addStep(a, 'one');
      s.addStepTag(a, st, 'mtg');
      s.addTag(b, 'mtg');
      expect(tagsInUse(s.data).single.open, 2);
      s.renameTag('mtg', 'Meeting');
      expect(st.tags, ['Meeting']);
      expect(b.tags, ['Meeting']);
      s.deleteTag('meeting');
      expect(st.tags, isEmpty);
      expect(tagsInUse(s.data), isEmpty);
    });

    test('step to task carries the tags; repeats copy them', () {
      final s = AppStore();
      final t = s.addTask('Trip', due: DateTime(2026, 12, 1, 9))..repeat = Repeat(unit: RepeatUnit.week);
      s.addTag(t, 'travel');
      final st = s.addStep(t, 'Book hotel');
      s.addStepTag(t, st, 'admin');
      expect(t.nextRepeat(DateTime(2026, 12, 1))!.steps.single.tags, ['admin']);
      final linked = s.stepToTask(t, st);
      expect(linked.tags, ['travel', 'admin']);
    });

    testWidgets('the step menu tags a step and its row shows the tag', (tester) async {
      final s = AppStore();
      final t = s.addTask('Write report');
      final st = s.addStep(t, 'Gather numbers');
      s.addTag(s.addTask('x'), 'research');
      await tester.pumpWidget(MaterialApp(home: TaskPage(store: s, task: t)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Gather numbers'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Gather numbers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a tag').last);
      await tester.pumpAndSettle();
      expect(find.text('Tags for step "Gather numbers"'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, '#research'));
      await tester.pumpAndSettle();
      expect(st.tags, ['research']);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('#research'), findsOneWidget);
    });
  });
}
