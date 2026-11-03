import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/home_widgets.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/kanban_page.dart';
import 'package:task_blocks/store.dart';

/// Hands the store what a widget or another app left, as the Android side would.
class FakeWidgets extends HomeWidgets {
  List<WidgetMove> moves = [];
  List<dynamic> pushed = [];

  @override
  Future<List<WidgetMove>> takeMoves() async {
    final m = moves;
    moves = [];
    return m;
  }

  @override
  Future<List<dynamic>> takePushed() async {
    final p = pushed;
    pushed = [];
    return p;
  }
}

void main() {
  group('board and matrix widgets (68)', () {
    test('the widgets get the stages, box names, and each task\'s stage, time there and box', () {
      final now = DateTime(2026, 11, 3, 12);
      final s = AppStore();
      s.setBoxName(MatrixBox.doNow, 'Now');
      final t = s.addTask('Fix the fence', board: true, box: MatrixBox.doNow);
      s.moveToStage(t, s.data.stages[2], how: MoveHow.menu);
      s.setStepsOnBoard(t, true);
      final st = s.addStep(t, 'Dig post holes');
      s.setStepsOnBoard(t, false);
      s.setStepsOnBoard(t, true);
      s.addTask('Later', board: true).snoozedUntil = DateTime(2026, 11, 10);
      s.addTask('Hidden').snoozedUntil = DateTime(2026, 11, 10);
      final j = jsonDecode(HomeWidgets.widgetJson(s.data, now)) as Map;
      expect([for (final x in j['stages']) x['id']], ['backlog', 'next', 'doing', 'blocked', 'done']);
      expect(j['boxes']['do'], 'Now');
      expect(j['boxes']['delete'], 'Delete');
      final tasks = {for (final x in j['tasks']) x['title']: x};
      expect(tasks['Fix the fence']['stage'], 'doing');
      expect(tasks['Fix the fence']['box'], 'do');
      expect(tasks['Fix the fence']['since'], isA<int>());
      final step = (tasks['Fix the fence']['steps'] as List).single;
      expect(step['id'], st.id);
      expect(step['stage'], 'backlog');
      expect(tasks['Later']['snoozed'], isTrue, reason: 'the board counts snoozed tasks');
      expect(tasks.containsKey('Hidden'), isFalse, reason: 'snoozed and not on the board');
    });

    test('a widget move is saved as a board move made by "Widget"', () {
      final s = AppStore();
      final t = s.addTask('Fix the fence', board: true);
      final next = s.data.stages[1];
      expect(s.applyWidgetMove((task: t.id, step: null, stage: next.id, at: DateTime.now())), isTrue);
      expect(t.stageId, next.id);
      expect(t.moves.last.how, MoveHow.widget);
      expect(MoveHow.label(MoveHow.widget), 'Widget');
      expect(s.applyWidgetMove((task: t.id, step: null, stage: 'gone', at: DateTime.now())), isFalse);
      expect(s.applyWidgetMove((task: 'gone', step: null, stage: next.id, at: DateTime.now())), isFalse);
      final off = s.addTask('Not on the board');
      expect(s.applyWidgetMove((task: off.id, step: null, stage: next.id, at: DateTime.now())), isFalse);
      expect(off.kanban, isFalse);
    });

    test('into the last stage ticks off only when the board always does; steps tick', () {
      final s = AppStore();
      final last = s.data.stages.last;
      final t = s.addTask('Fix the fence', board: true);
      s.applyWidgetMove((task: t.id, step: null, stage: last.id, at: DateTime.now()));
      expect(t.closedAt, isNull, reason: '"Ask" can\'t ask on a widget, so it stays open');
      s.data.kanbanDone = KanbanDone.always;
      final u = s.addTask('Paint the shed', board: true);
      s.applyWidgetMove((task: u.id, step: null, stage: last.id, at: DateTime.now()));
      expect(u.closedAt, isNotNull);

      final v = s.addTask('Move house', board: true);
      s.setStepsOnBoard(v, true);
      final st = s.addStep(v, 'Pack');
      s.setStepsOnBoard(v, false);
      s.setStepsOnBoard(v, true);
      s.applyWidgetMove((task: v.id, step: st.id, stage: last.id, at: DateTime.now()));
      expect(st.done, isTrue);
      expect(st.moves.last.how, MoveHow.widget);
    });

    testWidgets('a board widget opens the board on its stage on a phone', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final s = AppStore();
      final t = s.addTask('Fix the fence', board: true);
      s.moveToStage(t, s.data.stages[3], how: MoveHow.menu);
      await tester.pumpWidget(MaterialApp(home: KanbanPage(store: s, initialStage: 'blocked')));
      await tester.pumpAndSettle();
      expect(find.text('Fix the fence'), findsOneWidget);
    });
  });

  group('tasks sent by other Android apps (48B)', () {
    test('are added like inbox files: source, ref, steps, category board default', () {
      final s = AppStore();
      s.addCategory('Work');
      s.setCategoryBoard(s.data.categories.single, on: true);
      final added = s.addPushed([
        {'title': 'Renew car insurance', 'source': 'intent', 'ref': 'tasker-1', 'steps': ['Get quotes', 'Pay']},
        {'title': 'Send the report', 'category': 'Work', 'source': 'intent'},
        {'notes': 'no title'},
        {'title': 'Renew car insurance', 'source': 'intent', 'ref': 'tasker-1'},
      ]);
      expect(added.map((t) => t.title), ['Renew car insurance', 'Send the report']);
      expect(added.first.source, TaskSource.intent);
      expect(added.first.sourceRef, 'tasker-1');
      expect(added.first.steps.map((x) => x.title), ['Get quotes', 'Pay']);
      expect(added.last.kanban, isTrue, reason: 'Work puts new tasks on the board');
      expect(TaskSource.label(TaskSource.intent), 'Another Android app');
    });

    test('pending moves and sent tasks are picked up when the app opens or comes back', () async {
      final w = FakeWidgets();
      final s = AppStore(widgets: w);
      final t = s.addTask('Fix the fence', board: true);
      w.moves = [(task: t.id, step: null, stage: 'doing', at: DateTime.now())];
      w.pushed = [
        {'title': 'Ring the vet tomorrow', 'source': 'intent'},
      ];
      await s.applyPending();
      expect(t.stageId, 'doing');
      final vet = s.data.active.firstWhere((x) => x.title == 'Ring the vet');
      expect(vet.dueAt, isNotNull, reason: 'dates in the title are read');
      await s.applyPending();
      expect(s.data.active.where((x) => x.title == 'Ring the vet'), hasLength(1));
    });
  });
}
