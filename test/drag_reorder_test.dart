import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/main.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';

void main() {
  Future<AppStore> pumpList(WidgetTester tester, ListSort sort) async {
    final store = AppStore();
    store.data.sort = sort;
    for (final t in ['one', 'two', 'three']) {
      store.addTask(t);
    }
    await tester.pumpWidget(TaskApp(store: store));
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> dragFirstDown(WidgetTester tester) async {
    final handle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('drag handles show in a sorted list and a drop switches to hand-made order', (tester) async {
    final store = await pumpList(tester, ListSort.due);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    final before = store.data.active.map((t) => t.title).toList();

    await dragFirstDown(tester);
    expect(store.data.sort, ListSort.manual);
    final after = store.data.active.map((t) => t.title).toList();
    expect(after, isNot(before));
    expect(after.first, before[1]);
    expect(find.textContaining('Now in hand-made order'), findsWidgets);

    await tester.tap(find.text('Undo').first);
    await tester.pumpAndSettle();
    expect(store.data.sort, ListSort.due);
    expect(store.data.active.map((t) => t.title).toList(), before);
  });

  testWidgets('dragging in hand-made order moves the task', (tester) async {
    final store = await pumpList(tester, ListSort.manual);
    final before = store.data.active.map((t) => t.title).toList();
    await dragFirstDown(tester);
    expect(store.data.sort, ListSort.manual);
    expect(store.data.active.first.title, before[1]);
    expect(find.textContaining('Now in hand-made order'), findsNothing);
  });
}
