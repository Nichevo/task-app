import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/reminders.dart';

void main() {
  test('reminders are only rescheduled when something they depend on changes', () {
    final now = DateTime(2026, 11, 3, 10);
    final d = AppData();
    final t = Task.create('Pay rent')..dueAt = DateTime(2026, 11, 5, 9);
    d.active.add(t);
    final first = Reminders.scheduleKey(d, now);
    t.notes = 'Standing order';
    d.updatedAt = DateTime.now();
    expect(Reminders.scheduleKey(d, now), first, reason: 'notes and save times don\'t matter');
    expect(Reminders.scheduleKey(d, now.add(const Duration(hours: 3))), first);
    t.dueAt = DateTime(2026, 11, 6, 9);
    final moved = Reminders.scheduleKey(d, now);
    expect(moved, isNot(first));
    t.title = 'Pay the rent';
    expect(Reminders.scheduleKey(d, now), isNot(moved));
    d.defaultRemindBefore = 30;
    expect(Reminders.scheduleKey(d, now), isNot(Reminders.scheduleKey(AppData()..active.add(t), now)));
    expect(Reminders.scheduleKey(d, now.add(const Duration(days: 1))), isNot(Reminders.scheduleKey(d, now)),
        reason: 'once a day for the daily and weekly ones');
  });
}
