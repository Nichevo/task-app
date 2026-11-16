import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/csv_import.dart';
import 'package:task_blocks/input_parse.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/matrix_page.dart';
import 'package:task_blocks/screens/task_page.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/tags.dart';
import 'package:task_blocks/task_list.dart';
import 'package:task_blocks/widgets/tag_widgets.dart';

AppData roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

void main() {
  group('tags (107)', () {
    test('tags survive JSON, are kept once whatever the case, and old files have none', () {
      final s = AppStore();
      final t = s.addTask('Plan sprint');
      expect(s.addTag(t, '#Meeting'), isTrue);
      expect(s.addTag(t, 'meeting'), isFalse);
      expect(s.addTag(t, '  '), isFalse);
      s.addTag(t, 'deep  work');
      expect(t.tags, ['Meeting', 'deep work']);
      final d = roundTrip(s.data);
      expect(d.active.single.tags, ['Meeting', 'deep work']);
      final old = Task.fromJson({'id': 'x', 'title': 'Old', 'createdAt': DateTime(2026).toIso8601String()});
      expect(old.tags, isEmpty);
      expect(old.toJson().containsKey('tags'), isFalse);
    });

    test('a new tag takes the spelling already in use', () {
      final s = AppStore();
      s.addTag(s.addTask('A'), 'Coding');
      final b = s.addTask('B');
      s.addTag(b, 'coding');
      expect(b.tags, ['Coding']);
    });

    test('#words: a category name picks the category, any other word becomes a tag', () {
      final s = AppStore();
      final work = s.addCategory('Work');
      final p = parseInput('Sprint review #work #meeting #Coding tomorrow', s.data, DateTime(2026, 11, 16, 9));
      expect(p.categoryId, work.id);
      expect(p.tags, ['meeting', 'Coding']);
      expect(p.title, 'Sprint review');
      // A number stays in the name; a kept word stays too.
      expect(parseInput('Call #1 client', s.data, DateTime(2026)).title, 'Call #1 client');
      final kept = parseInput('Fix #bug now', s.data, DateTime(2026), keepTags: {'bug'});
      expect(kept.tags, isEmpty);
      expect(kept.title, 'Fix #bug now');
    });

    test('an existing tag wins over a category it is the start of', () {
      final s = AppStore();
      s.addCategory('Meetings and calls');
      s.addTag(s.addTask('Old'), 'meet');
      final p = parseInput('Standup #meet', s.data, DateTime(2026));
      expect(p.categoryId, isNull);
      expect(p.tags, ['meet']);
    });

    test('adding from the add box puts the tags on', () {
      final s = AppStore();
      final t = s.addMany(['Write tests #coding #focus']).single;
      expect(t.title, 'Write tests');
      expect(t.tags, ['coding', 'focus']);
    });

    test('filter: any picked tag, or no tag', () {
      final a = Task.create('a')..tags.add('meeting');
      final b = Task.create('b')..tags.addAll(['coding', 'Brainstorming']);
      final c = Task.create('c');
      bool pass(Task t, Set<String> f) => passesTagFilter(t, f);
      expect([a, b, c].where((t) => pass(t, {})).length, 3);
      expect([a, b, c].where((t) => pass(t, {'Meeting'})).toList(), [a]);
      expect([a, b, c].where((t) => pass(t, {'meeting', 'brainstorming'})).toList(), [a, b]);
      expect([a, b, c].where((t) => pass(t, {untaggedFilter})).toList(), [c]);
    });

    test('rename merges into an existing tag, delete takes it off everywhere, the filter follows', () {
      final s = AppStore();
      final a = s.addTask('a'), b = s.addTask('b');
      s.addTag(a, 'mtg');
      s.addTag(b, 'Meeting');
      s.addTag(b, 'mtg');
      s.setTagFilter({'mtg'});
      s.renameTag('mtg', 'meeting');
      expect(a.tags, ['Meeting']);
      expect(b.tags, ['Meeting']);
      expect(s.tagFilter, {'Meeting'});
      expect(tagsInUse(s.data).map((x) => x.tag), ['Meeting']);
      s.deleteTag('MEETING');
      expect(a.tags, isEmpty);
      expect(s.tagFilter, isEmpty);
    });

    test('a filter on a tag nobody has any more is ignored', () {
      final s = AppStore();
      s.addTag(s.addTask('a'), 'x');
      s.setTagFilter({'gone'});
      expect(s.liveTagFilter, isEmpty);
    });

    test('repeats and search keep the tags; CSV round trip', () {
      final s = AppStore();
      final t = s.addTask('Weekly review', due: DateTime(2026, 11, 20, 9))..repeat = Repeat(unit: RepeatUnit.week);
      s.addTag(t, 'review');
      s.addTag(t, 'planning');
      expect(t.nextRepeat(DateTime(2026, 11, 20)).tags, ['review', 'planning']);
      expect(matchesSearch(t, '#planning', s.data), isTrue);
      final csv = buildCsv(s.data);
      final d = AppData();
      expect(importCsvText(d, csv), 1);
      expect(d.active.single.tags, ['review', 'planning']);
    });

    testWidgets('the task page shows its tags and takes one off', (tester) async {
      final s = AppStore();
      final t = s.addTask('Design session');
      s.addTag(t, 'brainstorming');
      await tester.pumpWidget(
        MaterialApp(
          home: TaskPage(store: s, task: t),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('#brainstorming'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('#brainstorming'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(InputChip), matching: find.byIcon(Icons.clear)).first);
      await tester.pumpAndSettle();
      expect(t.tags, isEmpty);
    });

    testWidgets('the matrix filters by the picked tag', (tester) async {
      final s = AppStore();
      final a = s.addTask('Fix the leak', box: MatrixBox.doNow);
      s.addTask('Plan the garden', box: MatrixBox.decide);
      s.addTag(a, 'home');
      s.setTagFilter({'home'});
      await tester.pumpWidget(MaterialApp(home: MatrixPage(store: s)));
      await tester.pumpAndSettle();
      expect(find.text('Fix the leak'), findsOneWidget);
      expect(find.text('Plan the garden'), findsNothing);
      expect(find.byType(TagFilterChip), findsOneWidget);
      expect(find.text('#home'), findsOneWidget);
    });
  });
}
