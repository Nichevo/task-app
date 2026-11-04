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

  int get openCount => data.tasksNotHabits.length;

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

  // --- Round 4: sources, repeats, timing, added charts ---

  /// Every task added that the app still knows about: open and archived tasks, plus tasks the
  /// archive clean-up deleted (from their completion records). Deleted-by-hand tasks are gone.
  List<AddedItem> get added {
    final out = <AddedItem>[];
    final seen = <String>{};
    for (final t in data.allTasks) {
      seen.add(t.id);
      out.add(AddedItem(t.id, t.createdAt, t.categoryId, t.source, t.closedAt));
    }
    data.done.forEach((id, r) {
      if (!seen.contains(id)) out.add(AddedItem(id, r.createdAt, r.categoryId, r.source, r.at));
    });
    return out;
  }

  /// Per source, for tasks added since [from]: how many were added and how many of those are
  /// done; plus how many tasks from that source were ticked off in the period. Most added first.
  List<SourceRow> bySource(DateTime? from) {
    final rows = <String?, SourceRow>{};
    SourceRow row(String? src) => rows.putIfAbsent(src, () => SourceRow(src));
    for (final a in added) {
      if (from != null && a.createdAt.isBefore(from)) continue;
      final r = row(a.source);
      r.added++;
      if (a.doneAt != null) r.addedDone++;
    }
    for (final e in data.done.entries) {
      final r = e.value;
      if (from != null && r.at.isBefore(from)) continue;
      // Older records have no source; the task itself may still say.
      row(r.source ?? data.task(e.key)?.source).done += 1;
    }
    return rows.values.toList()..sort((a, b) => b.added != a.added ? b.added.compareTo(a.added) : b.done.compareTo(a.done));
  }

  /// One row per repeating series with what happened to it since [from], busiest first.
  List<SeriesRow> repeats(DateTime? from) {
    final rows = <String, SeriesRow>{};
    SeriesRow row(String id) => rows.putIfAbsent(id, () => SeriesRow(id));
    bool inPeriod(DateTime d) => from == null || !d.isBefore(from);
    for (final e in data.done.entries) {
      final r = e.value;
      final series = r.series ?? data.task(e.key)?.seriesId;
      if (series == null || !inPeriod(r.at)) continue;
      final sr = row(series);
      sr.done++;
      sr.missed += r.missed;
      sr.name ??= r.title;
    }
    for (final k in data.skips.values) {
      if (!inPeriod(k.at)) continue;
      final sr = row(k.series);
      sr.skipped++;
      sr.missed += k.missed;
    }
    // Open repeating tasks: cycles already gone by unticked count as missed now.
    for (final t in data.active.where((t) => t.repeat != null)) {
      final r = row(t.series)..name = t.title;
      r.missed += missedCycles(t, now);
      r.open = true;
    }
    for (final r in rows.values) {
      r.name ??= data.task(r.id)?.title ?? 'Repeating task';
    }
    return rows.values.where((r) => r.done + r.skipped + r.missed > 0).toList()
      ..sort((a, b) => (b.done + b.skipped + b.missed).compareTo(a.done + a.skipped + a.missed));
  }

  /// How early or late tasks with a due date were ticked off since [from] (records from 1.4 on).
  Timing timing(DateTime? from) {
    final t = Timing();
    final late = <int>[];
    for (final r in doneSince(from)) {
      final due = r.due;
      if (due == null) continue;
      late.add(r.lateMinutes!);
      final days = dayOf(r.at).difference(dayOf(due)).inDays;
      final b = days < -7
          ? 0
          : days < 0
          ? 1
          : days == 0
          ? 2
          : days <= 7
          ? 3
          : 4;
      t.buckets[b]++;
    }
    late.sort();
    if (late.isNotEmpty) t.medianLateMinutes = late[late.length ~/ 2];
    return t;
  }

  /// Added, done and still-open counts per day (periods up to 31 days), week (up to a year) or
  /// month, for the period since [from] (all time when null), oldest first. [categoryId] '' is
  /// "no category"; null is every category.
  /// Kanban numbers for the period from [from]; null when nothing has ever been on the board.
  KanbanStats? kanban(DateTime? from) {
    bool inPeriod(DateTime d) => from == null || !d.isBefore(from);
    final tasks = data.allTasks.where((t) => t.moves.isNotEmpty).toList();
    final known = {for (final t in tasks) t.id};
    final gone = data.done.entries.where((e) => !known.contains(e.key) && e.value.stageMinutes != null);
    if (tasks.isEmpty && gone.isEmpty) return null;

    final spells = {for (final st in data.stages) st.id: <int>[]};
    for (final t in tasks) {
      for (final s in stageStints(t)) {
        if (s.end != null && inPeriod(s.end!)) spells[s.stageId]?.add(s.end!.difference(s.start).inMinutes);
      }
    }
    // Tasks already cleaned out of the archive: their totals per stage.
    for (final e in gone) {
      if (!inPeriod(e.value.at)) continue;
      e.value.stageMinutes!.forEach((id, m) => spells[id]?.add(m));
    }

    // Item 56: checklist steps on the board, counted apart from tasks.
    final stepSpells = {for (final st in data.stages) st.id: <int>[]};
    var stepMoves = 0;
    for (final t in data.allTasks) {
      for (final step in t.steps) {
        for (final s in moveStints(step.moves)) {
          if (s.end != null && inPeriod(s.end!)) stepSpells[s.stageId]?.add(s.end!.difference(s.start).inMinutes);
        }
        for (final m in step.moves) {
          if (inPeriod(m.at) && m.fromId != null && m.toId != null) stepMoves++;
        }
      }
    }

    final order = {for (final (i, st) in data.stages.indexed) st.id: i};
    var moves = 0, back = 0;
    DateTime? first;
    for (final t in tasks) {
      var wentBack = false;
      for (final m in t.moves) {
        if (first == null || m.at.isBefore(first)) first = m.at;
        if (!inPeriod(m.at) || m.fromId == null || m.toId == null) continue;
        moves++;
        final a = order[m.fromId], b = order[m.toId];
        if (a != null && b != null && b < a && m.how != MoveHow.reopened) wentBack = true;
      }
      if (wentBack) back++;
    }
    final start = from ?? first ?? now;
    final weeks = now.difference(start).inHours / (24 * 7);

    final longest = [
      for (final t in data.boardTasks)
        if ((data.stage(t.stageId), t.stageSince) case (final st?, final since?)) (t, st, now.difference(since)),
    ]..sort((x, y) => y.$3.compareTo(x.$3));

    return KanbanStats(
      stages: [for (final st in data.stages) StageRow(st, spells[st.id]!..sort())],
      movesPerWeek: weeks < 1 ? moves.toDouble() : moves / weeks,
      steps: stepSpells.values.every((l) => l.isEmpty)
          ? null
          : [for (final st in data.stages) StageRow(st, stepSpells[st.id]!..sort())],
      stepMovesPerWeek: weeks < 1 ? stepMoves.toDouble() : stepMoves / weeks,
      backwards: back,
      longest: longest.take(5).toList(),
    );
  }

  List<Bucket> addedVsDone(DateTime? from, {String? categoryId}) {
    final items = [
      for (final a in added)
        if (categoryId == null || (data.category(a.categoryId)?.id ?? '') == categoryId) a,
    ];
    var start = from ?? (items.isEmpty ? today : items.map((a) => a.createdAt).reduce((x, y) => x.isBefore(y) ? x : y));
    final span = today.difference(dayOf(start)).inDays + 1;
    final unit = span <= 31 ? BucketUnit.day : span <= 372 ? BucketUnit.week : BucketUnit.month;
    start = switch (unit) {
      BucketUnit.day => dayOf(start),
      BucketUnit.week => weekOf(start),
      BucketUnit.month => DateTime(start.year, start.month),
    };
    DateTime nextOf(DateTime d) => switch (unit) {
          BucketUnit.day => DateTime(d.year, d.month, d.day + 1),
          BucketUnit.week => DateTime(d.year, d.month, d.day + 7),
          BucketUnit.month => DateTime(d.year, d.month + 1),
        };
    final out = <Bucket>[];
    for (var d = start; !d.isAfter(today) && out.length < 400; d = nextOf(d)) {
      final end = nextOf(d);
      var a = 0, dn = 0, open = 0;
      for (final i in items) {
        if (!i.createdAt.isBefore(d) && i.createdAt.isBefore(end)) a++;
        final done = i.doneAt;
        if (done != null && !done.isBefore(d) && done.isBefore(end)) dn++;
        if (i.createdAt.isBefore(end) && (done == null || !done.isBefore(end))) open++;
      }
      out.add(Bucket(d, unit, a, dn, open));
    }
    return out;
  }

  /// Numbers for the weekly review: the 7 days before [at] and the 7 days after.
  ({int added, int done, int overdue, int dueNext}) weekReview(DateTime at) {
    final from = at.subtract(const Duration(days: 7));
    final next = at.add(const Duration(days: 7));
    return (
      added: added.where((a) => !a.createdAt.isBefore(from) && a.createdAt.isBefore(at)).length,
      done: _done.where((r) => !r.at.isBefore(from) && r.at.isBefore(at)).length,
      overdue: data.active.where((t) => t.dueAt != null && t.dueAt!.isBefore(at)).length,
      dueNext: data.active.where((t) => t.dueAt != null && !t.dueAt!.isBefore(at) && t.dueAt!.isBefore(next)).length,
    );
  }
}

/// A task as far as the statistics need it.
/// Item 52: the Kanban card on the Statistics page.
class KanbanStats {
  KanbanStats({
    required this.stages,
    required this.movesPerWeek,
    required this.backwards,
    required this.longest,
    this.steps,
    this.stepMovesPerWeek = 0,
  });

  /// Item 56: time checklist steps spent in each stage; null when no step has moved on yet.
  final List<StageRow>? steps;
  final double stepMovesPerWeek;

  /// One row per current stage, in board order.
  final List<StageRow> stages;
  final double movesPerWeek;

  /// Tasks moved back to an earlier stage at least once in the period.
  final int backwards;

  /// Open board tasks that have been in their stage longest, longest first.
  final List<(Task, KanbanStage, Duration)> longest;
}

class StageRow {
  StageRow(this.stage, this.minutes);

  final KanbanStage stage;

  /// Finished spells in this stage, in minutes, sorted.
  final List<int> minutes;

  int get count => minutes.length;
  double? get average => minutes.isEmpty ? null : minutes.reduce((a, b) => a + b) / minutes.length;
  int? get median => minutes.isEmpty ? null : minutes[minutes.length ~/ 2];
}

class AddedItem {
  const AddedItem(this.id, this.createdAt, this.categoryId, this.source, this.doneAt);

  final String id;
  final DateTime createdAt;
  final String? categoryId;
  final String? source;
  final DateTime? doneAt;
}

class SourceRow {
  SourceRow(this.source);

  final String? source;
  int added = 0;

  /// Of those added in the period, how many are done.
  int addedDone = 0;

  /// Ticked off in the period (whenever added).
  int done = 0;

  double? get share => added == 0 ? null : addedDone / added;
}

class SeriesRow {
  SeriesRow(this.id);

  final String id;
  String? name;
  int done = 0, skipped = 0, missed = 0;

  /// Still has an open task.
  bool open = false;

  double get share => done / (done + skipped + missed);
}

class Timing {
  /// Over a week early, 1–7 days early, same day, 1–7 days late, over a week late.
  final buckets = List.filled(5, 0);

  /// Median minutes after the due time (negative = before); null with nothing to count.
  int? medianLateMinutes;

  static const labels = ['Over a week early', '1–7 days early', 'Same day', '1–7 days late', 'Over a week late'];

  int get total => buckets.fold(0, (a, b) => a + b);
  int get early => buckets[0] + buckets[1];
  int get sameDay => buckets[2];
  int get late => buckets[3] + buckets[4];
}

enum BucketUnit { day, week, month }

class Bucket {
  const Bucket(this.start, this.unit, this.added, this.done, this.open);

  final DateTime start;
  final BucketUnit unit;
  final int added, done;

  /// Open at the end of it.
  final int open;
}
