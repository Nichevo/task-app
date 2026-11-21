import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/home_page.dart';
import 'package:task_blocks/screens/smart_list_page.dart';
import 'package:task_blocks/smart_lists.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/task_list.dart';

/// Item 114 (11): saved smart lists.
void main() {
  final now = DateTime(2026, 11, 23, 10); // a Monday

  test('each filter picks the right tasks', () {
    final s = AppStore();
    final d = s.data;
    final work = TaskCategory(id: 'w', name: 'Work');
    d.categories.add(work);
    final a = s.addTask('Reply to client')
      ..categoryId = 'w'
      ..estimate = 10
      ..dueAt = DateTime(2026, 11, 25);
    final b = s.addTask('Chase supplier')
      ..waitingOn = 'Sam'
      ..matrixBox = MatrixBox.delegate.id;
    final c = s.addTask('Fix fence')
      ..starred = true
      ..estimate = 240;
    List<String> on(SmartList l) => [for (final t in [a, b, c]) if (passesSmartList(t, l, d, now)) t.title];

    expect(on(SmartList.create('x')..categoryIds.add('w')), [a.title]);
    expect(on(SmartList.create('x')..categoryIds.add('')), [b.title, c.title]);
    expect(on(SmartList.create('x')..maxMinutes = 15), [a.title]);
    expect(on(SmartList.create('x')..waiting = true), [b.title]);
    expect(on(SmartList.create('x')..waiting = false), [a.title, c.title]);
    expect(on(SmartList.create('x')..box = MatrixBox.delegate.id), [b.title]);
    expect(on(SmartList.create('x')..starred = true), [c.title]);
    expect(on(SmartList.create('x')..due = SmartDue.week.name), [a.title]);
    expect(on(SmartList.create('x')..due = SmartDue.noDate.name), [b.title, c.title]);
    a.tags.add('client');
    expect(on(SmartList.create('x')..tags.add('client')), [a.title]);
  });

  test('lists sync with the data and the picked one stays on this device', () {
    final s = AppStore();
    expect(s.data.helperOn(Helper.smartLists), isTrue);
    expect(s.addStarterSmartLists(), 4);
    expect(s.addStarterSmartLists(), 0, reason: 'not twice');
    final l = s.data.smartLists.first;
    s.setSmartList(l.id);
    expect(s.activeSmartList?.name, 'Quick wins');
    final back = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())) as Map<String, dynamic>);
    expect(back.smartLists.map((x) => x.name), ['Quick wins', 'Waiting on others', 'At risk', 'Due this week']);
    s.moveSmartList(0, 2);
    expect(s.data.smartLists.map((x) => x.name).take(3), ['Waiting on others', 'At risk', 'Quick wins']);
    s.setHelper(Helper.smartLists, false);
    expect(s.activeSmartList, isNull, reason: 'off in Settings shows everything');
    s.setHelper(Helper.smartLists, true);
    s.deleteSmartList(l.id);
    expect(s.activeSmartList, isNull);
    expect(s.data.smartLists, hasLength(3));
  });

  test('Save as list takes the chips', () {
    final s = AppStore();
    s.addTask('Reply').tags.add('client');
    s.setTagFilter(['client']);
    final l = smartListFromChips(s, QuickFilter.behind);
    expect(l.tags, {'client'});
    expect(l.behind, isTrue);
    expect(smartListFromChips(s, QuickFilter.week).due, SmartDue.week.name);
  });

  testWidgets('pick a list in the ☰ menu, then clear it', (tester) async {
    final s = AppStore();
    s.addTask('Quick email')..estimate = 5;
    s.addTask('Big report')..estimate = 300;
    s.addStarterSmartLists();
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: HomePage(store: s)));
    expect(find.text('Big report'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('MY LISTS'), findsOneWidget);
    await tester.tap(find.text('Quick wins'));
    await tester.pumpAndSettle();
    expect(find.text('Quick email'), findsOneWidget);
    expect(find.text('Big report'), findsNothing);
    expect(find.text('⚡ Quick wins'), findsOneWidget);
    tester.widget<InputChip>(find.widgetWithText(InputChip, '⚡ Quick wins')).onDeleted!();
    await tester.pumpAndSettle();
    expect(find.text('Big report'), findsOneWidget);
    expect(s.smartListId, isNull);
  });

  testWidgets('make a new list', (tester) async {
    final s = AppStore();
    s.addTask('Chase supplier')..waitingOn = 'Sam';
    await tester.pumpWidget(MaterialApp(home: SmartListPage(store: s, list: SmartList.create(''))));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Chasers');
    await tester.tap(find.text('Either'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Waiting').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('1 open task match'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(s.data.smartLists.single.name, 'Chasers');
    expect(s.data.smartLists.single.waiting, isTrue);
  });
}
