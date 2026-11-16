import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/day_plan.dart';
import 'package:task_blocks/gantt.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/takes_dialog.dart';

/// 1.12.10: how long a task or step takes can be given in hours as well as days.
void main() {
  test('hours read and fill working days (9 h by default)', () {
    final d = AppStore().data;
    expect(parseTakes('6', d, hours: true), (days: 1, minutes: 360));
    expect(parseTakes('1.5', d, hours: true), (days: 1, minutes: 90));
    expect(parseTakes('12h', d, hours: false), (days: 2, minutes: 720));
    expect(parseTakes('1h30', d, hours: false), (days: 1, minutes: 90));
    expect(parseTakes('90m', d, hours: false), (days: 1, minutes: 90));
    expect(parseTakes('3', d, hours: false), (days: 3, minutes: null));
    expect(parseTakes('2 days', d, hours: true), (days: 2, minutes: null));
    expect(parseTakes('0', d, hours: true), isNull);
    expect(parseTakes('soon', d, hours: true), isNull);
  });

  test('labels, and hours stop counting once the days change another way', () {
    final d = AppStore().data;
    expect(describeTakes(1, 360, d), '6 h');
    expect(describeTakes(2, 720, d), '12 h (2 work days)');
    expect(describeTakes(3, null, d), '3 work days');
    expect(describeTakes(3, 720, d), '3 work days');
    d.dayPlan.workEnd = d.dayPlan.workStart + 4 * 60;
    expect(daysForMinutes(720, d), 3);
  });

  test('saved, copied to a step split out, and used for a new Day plan time', () {
    final s = AppStore();
    final t = s.addTask('Write report')
      ..takesDays = 1
      ..takesMinutes = 180;
    final st = s.addStep(t, 'Draft');
    s.setStepPlan(t, st, takes: 1, minutes: 120);
    final back = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())));
    expect(back.active.single.takesMinutes, 180);
    expect(back.active.single.steps.single.takesMinutes, 120);
    expect(planLength(s.data, t), 180);
    expect(planLength(s.data, t, st), 120);
    t.estimate = 45;
    expect(planLength(s.data, t), 45, reason: 'an estimate comes first');
    final (n, _) = s.splitOut(t, st);
    expect(n.takesMinutes, 120);
  });

  testWidgets('the task page asks in hours', (tester) async {
    final s = AppStore();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async {
            final r = await askTakes(c, s.data, title: 'How long?');
            if (r != null) s.addTask('took ${r.days}/${r.minutes}');
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hours'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '6');
    await tester.pump();
    expect(find.textContaining('On the Gantt chart: 1 day'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(s.data.active.single.title, 'took 1/360');
  });
}
