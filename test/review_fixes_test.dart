import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/reminders.dart';

void main() {
  group('reminders (review fixes)', () {
    final now = DateTime(2026, 11, 12, 10);

    test('H1: a task snoozed after its due time is reminded again when the snooze ends', () {
      final t = Task.create('Call the bank')
        ..dueAt = DateTime(2026, 11, 12, 9)
        ..snoozedUntil = DateTime(2026, 11, 12, 11);
      final plan = Reminders.plan(AppData()..active.add(t), now);
      expect(plan.map((r) => (r.title, r.when)), [('Snoozed task', DateTime(2026, 11, 12, 11))]);
      expect(plan.single.task, t, reason: 'it keeps the Done and Snooze buttons');
    });

    test('H1: snoozed before it is due, the due reminder waits for the snooze to end', () {
      final t = Task.create('Pay rent')
        ..dueAt = DateTime(2026, 11, 12, 12)
        ..snoozedUntil = DateTime(2026, 11, 12, 15);
      final plan = Reminders.plan(AppData()..active.add(t), now);
      expect(plan.map((r) => r.when), [DateTime(2026, 11, 12, 15)]);
    });

    test('a task not snoozed is reminded at its due time only', () {
      final t = Task.create('Gym')..dueAt = DateTime(2026, 11, 12, 18);
      final plan = Reminders.plan(AppData()..active.add(t), now);
      expect(plan.map((r) => (r.title, r.when)), [('Task due', DateTime(2026, 11, 12, 18))]);
    });

    test('nudges start after a snooze ends', () {
      final t = Task.create('Reply to email')
        ..dueAt = DateTime(2026, 11, 12, 9)
        ..snoozedUntil = DateTime(2026, 11, 12, 11);
      final d = AppData(overdueMode: OverdueMode.nudge, nudgeHours: 3)..active.add(t);
      final nudges = Reminders.plan(d, now).where((r) => r.title == 'Still to do').toList();
      expect(nudges.first.when, DateTime(2026, 11, 12, 14));
    });

    test('M2: tapping a task reminder names its task; buttons and summaries do not', () {
      expect(Reminders.tappedTask(null), isNull);
    });

    test('L3: the daily summary is worked out for each of the next days', () {
      final a = Task.create('Overdue already')..dueAt = DateTime(2026, 11, 10, 9);
      final b = Task.create('Due tomorrow noon')..dueAt = DateTime(2026, 11, 13, 12);
      final d = AppData(overdueMode: OverdueMode.daily, overdueAt: 8 * 60)..active.addAll([a, b]);
      final days = Reminders.dailySummaries(d, now);
      expect(days.length, 7);
      expect(days[0].when, DateTime(2026, 11, 13, 8));
      expect(days[0].title, '1 task overdue');
      expect(days[1].title, '2 tasks overdue');
      expect({for (final r in days) r.id}.length, 7, reason: 'each day has its own notification');
    });
  });
}
