import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/widgets/task_colors.dart';

void main() {
  group('88 worked today resets colour', () {
    final now = DateTime(2026, 11, 8, 18);
    Task old() => Task(id: 'a', title: 'a', createdAt: now.subtract(const Duration(days: 10)));

    test('undated task restarts from the moment it was ticked', () {
      final t = old();
      expect(ageProgress(t, 72, now: now), greaterThan(1));
      t.worked.add(dayKey(now));
      t.workedAt = now.subtract(const Duration(hours: 1));
      expect(t.colourStart(now), t.workedAt);
      expect(ageProgress(t, 72, now: now), closeTo(1 / 72, 1e-9));
    });

    test('a ticked day without a time counts from its start', () {
      final t = old()..worked.add(dayKey(now.subtract(const Duration(days: 1))));
      expect(t.colourStart(now), DateTime(2026, 11, 7));
    });

    test('a dated task keeps its colour', () {
      final t = old()
        ..dueAt = now.add(const Duration(days: 2))
        ..worked.add(dayKey(now))
        ..workedAt = now;
      expect(t.colourStart(now), t.createdAt);
    });

    test('workedAt survives JSON', () {
      final t = old()
        ..worked.add(dayKey(now))
        ..workedAt = now;
      final back = Task.fromJson(t.toJson());
      expect(back.workedAt, now);
      expect(back.extra.containsKey('wAt'), isFalse);
    });
  });
}
