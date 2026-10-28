import 'models.dart';

/// Numbers for the Statistics page and widgets, worked out from the open tasks and the
/// record of everything ticked off (which outlives the archive clean-up).
class Stats {
  Stats(this.data, this.now) : today = DateTime(now.year, now.month, now.day);

  final AppData data;
  final DateTime now;
  final DateTime today;

  Iterable<DoneRecord> get _done => data.done.values;

  /// Completions since [from] (or all time when null).
  List<DoneRecord> doneSince(DateTime? from) =>
      [for (final r in _done) if (from == null || !r.at.isBefore(from)) r];

  static DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Monday of the week containing [d].
  static DateTime weekOf(DateTime d) => dayOf(d).subtract(Duration(days: d.weekday - 1));

  int get doneThisWeek => doneSince(weekOf(now)).length;

  int get doneToday => doneSince(today).length;

  /// Days in a row, ending today or yesterday, with at least one task ticked off.
  int get streak {
    final days = {for (final r in _done) dayOf(r.at)};
    var day = today;
    if (!days.contains(day)) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(day)) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Tasks ticked off in each of the last [weeks] weeks, oldest first (last entry = this week).
  List<(DateTime, int)> donePerWeek([int weeks = 12]) {
    final start = weekOf(now).subtract(Duration(days: 7 * (weeks - 1)));
    final counts = List.filled(weeks, 0);
    for (final r in _done) {
      final i = weekOf(r.at).difference(start).inDays ~/ 7;
      if (i >= 0 && i < weeks) counts[i]++;
    }
    return [for (var i = 0; i < weeks; i++) (start.add(Duration(days: 7 * i)), counts[i])];
  }

  /// Share (0–1) of tasks with a due date that were done before it; null when none.
  double? onTimeShare(DateTime? from) {
    final dated = doneSince(from).where((r) => r.onTime != null).toList();
    if (dated.isEmpty) return null;
    return dated.where((r) => r.onTime!).length / dated.length;
  }

  /// Median time from adding a task to ticking it off; null when nothing was done.
  Duration? medianTimeToFinish(DateTime? from) {
    final took = doneSince(from).map((r) => r.tookMinutes).toList()..sort();
    if (took.isEmpty) return null;
    return Duration(minutes: took[took.length ~/ 2]);
  }

  int get openCount => data.active.length;

  int get overdueCount => data.active.where((t) => t.dueAt != null && t.dueAt!.isBefore(now)).length;

  /// How many tasks were open at the end of each of the last [days] days, oldest first.
  List<int> openTrend([int days = 30]) {
    final result = <int>[];
    for (var i = days - 1; i >= 0; i--) {
      final end = today.subtract(Duration(days: i - 1)); // start of the next day
      var n = data.active.where((t) => t.createdAt.isBefore(end)).length;
      for (final r in _done) {
        final created = r.at.subtract(Duration(minutes: r.tookMinutes));
        if (created.isBefore(end) && !r.at.isBefore(end)) n++;
      }
      result.add(n);
    }
    return result;
  }

  /// Done and open counts per category ('' = no category), in Settings order.
  List<(String, int, int)> byCategory(DateTime? from) {
    final done = <String, int>{};
    for (final r in doneSince(from)) {
      final key = data.category(r.categoryId)?.id ?? '';
      done[key] = (done[key] ?? 0) + 1;
    }
    final open = <String, int>{};
    for (final t in data.active) {
      final key = data.category(t.categoryId)?.id ?? '';
      open[key] = (open[key] ?? 0) + 1;
    }
    return [
      for (final c in data.categories) (c.name, done[c.id] ?? 0, open[c.id] ?? 0),
      if ((done[''] ?? 0) + (open[''] ?? 0) > 0) ('No category', done[''] ?? 0, open[''] ?? 0),
    ];
  }

  /// Days (yyyy-MM-dd) that have a task due within [span] of [from], with whether every task
  /// that day is only a future repeat ("faded"): day -> {'n': count, 'faded': bool}.
  Map<String, Map<String, Object>> dueDays(DateTime from, Duration span) {
    final out = <String, Map<String, Object>>{};
    final end = from.add(span);
    void add(DateTime d, bool faded) {
      final key = _key(d);
      final e = out.putIfAbsent(key, () => {'n': 0, 'faded': true});
      e['n'] = (e['n'] as int) + 1;
      if (!faded) e['faded'] = false;
    }

    for (final t in data.active) {
      final due = t.dueAt;
      if (due == null) continue;
      if (due.isBefore(end)) add(due, false);
      final r = t.repeat;
      if (r == null || r.fromCompletion) continue;
      var next = r.nextDue(due: due, completedAt: due);
      for (var i = 0; i < 40 && next.isBefore(end); i++) {
        add(next, true);
        next = r.nextDue(due: next, completedAt: next);
      }
    }
    return out;
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
