import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/reminders.dart';

void main() {
  group('item 99: snooze reminders set from the button', () {
    final now = DateTime(2026, 11, 12, 10);

    test('a task reminder carries its name, so a snooze button can remind again by itself', () {
      final t = Task.create('Call the bank')..dueAt = DateTime(2026, 11, 12, 11);
      final r = Reminders.plan(AppData()..active.add(t), now).first;
      final j = jsonDecode(Reminders.payloadFor(r, '/app')) as Map;
      expect(j, {'task': t.id, 'dir': '/app', 'title': 'Call the bank'});
    });

    test('a repeating task says so, for its Skip button', () {
      final t = Task.create('Bins')
        ..dueAt = DateTime(2026, 11, 12, 11)
        ..repeat = const Repeat(unit: RepeatUnit.week);
      final r = Reminders.plan(AppData()..active.add(t), now).first;
      expect((jsonDecode(Reminders.payloadFor(r, '/app')) as Map)['repeat'], true);
    });

    test('the snooze reminder set by a button has the id the app plans for it', () {
      final t = Task.create('Call the bank')
        ..dueAt = DateTime(2026, 11, 12, 9)
        ..snoozedUntil = DateTime(2026, 11, 12, 11);
      final planned = Reminders.plan(AppData()..active.add(t), now).single;
      // Reminders.snoozeEnded uses taskBase + 8, so the app's next scheduling replaces it.
      expect(planned.id, Reminders.taskBase(t.id) + 8);
    });
  });
}
