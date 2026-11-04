import 'dart:math';

import 'package:intl/intl.dart';

import 'models.dart';

/// Item 72: the Gantt chart's arithmetic, kept apart from the screens so it can be tested.

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

bool isWeekend(DateTime d) => d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

/// Calendar days from [a] to [b] (both taken as whole days); negative when [b] is earlier.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute);

/// The last day of [days] days of work starting on [start]. Without [weekends], Saturdays and
/// Sundays are skipped (a start on a weekend begins on the Monday).
DateTime workEnd(DateTime start, int days, {required bool weekends}) {
  var d = dayOf(start);
  if (!weekends) {
    while (isWeekend(d)) {
      d = addDays(d, 1);
    }
  }
  var left = max(days, 1) - 1;
  while (left > 0) {
    d = addDays(d, 1);
    if (weekends || !isWeekend(d)) left--;
  }
  return d;
}

/// The first day of [days] days of work ending on [end] (counting back, like [workEnd]).
DateTime workStart(DateTime end, int days, {required bool weekends}) {
  var d = dayOf(end);
  if (!weekends) {
    while (isWeekend(d)) {
      d = addDays(d, -1);
    }
  }
  var left = max(days, 1) - 1;
  while (left > 0) {
    d = addDays(d, -1);
    if (weekends || !isWeekend(d)) left--;
  }
  return d;
}

/// Days of work from [start] to [end] inclusive (at least 1).
int workDays(DateTime start, DateTime end, {required bool weekends}) {
  var n = 0;
  for (var d = dayOf(start); !d.isAfter(dayOf(end)); d = addDays(d, 1)) {
    if (weekends || !isWeekend(d)) n++;
  }
  return max(n, 1);
}

bool weekendsFor(Task t, AppData data) => t.countWeekends ?? data.ganttWeekends;

/// Where a task's bar sits: [start] to [end] as whole days. [guessedStart] when there is no start
/// date and the bar counts back from the due date. [due] is the due day (the flag).
class GanttBar {
  const GanttBar(this.task, this.start, this.end, {this.due, this.guessedStart = false});

  final Task task;
  final DateTime start;
  final DateTime end;
  final DateTime? due;
  final bool guessedStart;

  /// Expected to finish after it's due.
  bool get late => due != null && end.isAfter(due!);

  /// Days late (0 when on time).
  int get lateDays => late ? daysBetween(due!, end) : 0;

  int get length => daysBetween(start, end) + 1;
}

/// The bar for [t], or null when it has neither a start nor a due date ("Needs dates").
GanttBar? barFor(Task t, AppData data) {
  final due = t.dueAt == null ? null : dayOf(t.dueAt!);
  final weekends = weekendsFor(t, data);
  if (t.milestone) {
    final day = due ?? (t.startAt == null ? null : dayOf(t.startAt!));
    return day == null ? null : GanttBar(t, day, day, due: due);
  }
  final start = t.startAt == null ? null : dayOf(t.startAt!);
  if (start != null) {
    final takes = t.takesDays;
    final end = takes != null
        ? workEnd(start, takes, weekends: weekends)
        : due != null && !due.isBefore(start)
            ? due
            : start;
    return GanttBar(t, start, end, due: due);
  }
  if (due != null) {
    final takes = t.takesDays;
    return GanttBar(t, takes == null ? due : workStart(due, takes, weekends: weekends), due,
        due: due, guessedStart: true);
  }
  return null;
}

/// Finds a task by id, open or ticked off.
Task? anyTask(AppData data, String id) =>
    data.task(id) ?? data.archived.where((t) => t.id == id).firstOrNull;

/// The earliest day [t] can start: the day after the latest end of what it comes after, plus its
/// wait days. Null when it comes after nothing with dates. Ticked-off tasks count from when they
/// were ticked.
DateTime? earliestStart(Task t, AppData data) {
  DateTime? latest;
  for (final id in t.afterIds) {
    final p = anyTask(data, id);
    if (p == null) continue;
    final end = p.closedAt != null ? dayOf(p.closedAt!) : barFor(p, data)?.end;
    if (end == null) continue;
    if (latest == null || end.isAfter(latest)) latest = end;
  }
  return latest == null ? null : addDays(latest, 1 + (t.lagDays ?? 0));
}

/// An arrow on the chart: [to] comes after [from]. [clash] when [to] is planned to start before
/// [from] (plus the wait) ends.
class GanttLink {
  const GanttLink(this.from, this.to, this.clash);

  final Task from;
  final Task to;
  final bool clash;
}

/// The arrows between the tasks in [shown].
List<GanttLink> linksAmong(Iterable<Task> shown, AppData data) {
  final ids = {for (final t in shown) t.id: t};
  final out = <GanttLink>[];
  for (final t in shown) {
    if (t.closedAt != null) continue;
    final bar = barFor(t, data);
    for (final id in t.afterIds) {
      final p = ids[id];
      if (p == null) continue;
      final pEnd = p.closedAt != null ? dayOf(p.closedAt!) : barFor(p, data)?.end;
      final clash = bar != null && pEnd != null && bar.start.isBefore(addDays(pEnd, 1 + (t.lagDays ?? 0)));
      out.add(GanttLink(p, t, clash));
    }
  }
  return out;
}

/// Whether [t] clashes with anything it comes after.
bool clashes(Task t, AppData data) {
  final bar = barFor(t, data);
  final earliest = earliestStart(t, data);
  return t.closedAt == null && bar != null && earliest != null && bar.start.isBefore(earliest);
}

/// Open tasks that come after [t], directly or further down the chain, nearest first.
List<Task> followersOf(Task t, AppData data) {
  final out = <Task>[];
  final seen = {t.id};
  var wave = [t];
  while (wave.isNotEmpty) {
    final next = <Task>[];
    for (final w in wave) {
      for (final f in data.active) {
        if (seen.contains(f.id) || !f.afterIds.contains(w.id)) continue;
        seen.add(f.id);
        out.add(f);
        next.add(f);
      }
    }
    wave = next;
  }
  return out;
}

/// How many days each follower of [t] has to move later so none starts before what it comes
/// after ends (only the ones that would clash, by just enough). Works on a copy of the dates.
Map<Task, int> pushPlan(Task t, AppData data) {
  final out = <Task, int>{};
  for (final f in followersOf(t, data)) {
    final bar = barFor(f, data);
    if (bar == null) continue;
    // Ends of earlier tasks as they will be after the pushes worked out so far.
    DateTime? latest;
    for (final id in f.afterIds) {
      final p = anyTask(data, id);
      if (p == null) continue;
      var end = p.closedAt != null ? dayOf(p.closedAt!) : barFor(p, data)?.end;
      if (end == null) continue;
      final moved = out[p];
      if (moved != null) end = addDays(end, moved);
      if (latest == null || end.isAfter(latest)) latest = end;
    }
    if (latest == null) continue;
    final earliest = addDays(latest, 1 + (f.lagDays ?? 0));
    if (bar.start.isBefore(earliest)) out[f] = daysBetween(bar.start, earliest);
  }
  return out;
}

/// Moves [t]'s start and due date by [days] (its time of day stays).
void shiftDates(Task t, int days) {
  if (t.startAt != null) t.startAt = addDays(t.startAt!, days);
  if (t.dueAt != null) t.dueAt = addDays(t.dueAt!, days);
}

/// Would making [t] come after [other] make a loop?
bool wouldLoop(Task t, Task other, AppData data) =>
    other.id == t.id || followersOf(t, data).any((f) => f.id == other.id);

/// The date range a chart of [bars] needs: a few days either side, always including today.
(DateTime, DateTime) chartRange(Iterable<GanttBar> bars, DateTime now) {
  var first = dayOf(now), last = dayOf(now);
  for (final b in bars) {
    if (b.start.isBefore(first)) first = b.start;
    if (b.end.isAfter(last)) last = b.end;
    if (b.due != null && b.due!.isAfter(last)) last = b.due!;
    final ps = b.task.planStart;
    if (ps != null && dayOf(ps).isBefore(first)) first = dayOf(ps);
  }
  // Start on a Monday a few days back, run at least three weeks.
  first = addDays(first, -3);
  first = addDays(first, -(first.weekday - 1));
  last = addDays(last, 7);
  if (daysBetween(first, last) < 20) last = addDays(first, 20);
  return (first, last);
}

// --- Burn-down (item 77) ---

/// What a burn-down counts: tasks and steps left, or days of work left.
enum BurnUnit { items, days }

/// A burn-down of a set of chart tasks: work left each day from [start] to today, the ideal line
/// from [total] at [start] to nothing at [end], and when it would finish at the pace of the last
/// two weeks ([projected], null when nothing was done lately).
class BurnDown {
  const BurnDown(this.start, this.end, this.total, this.left, this.projected, this.unit);

  final DateTime start;

  /// The planned finish: the latest bar end.
  final DateTime end;
  final double total;

  /// Work left at the end of each day from [start] to today.
  final List<double> left;
  final DateTime? projected;
  final BurnUnit unit;

  double get now => left.isEmpty ? total : left.last;

  /// The ideal amount left on [d].
  double idealOn(DateTime d) {
    final span = max(daysBetween(start, end), 1);
    return (total * (1 - daysBetween(start, d) / span)).clamp(0, total).toDouble();
  }

  /// Days the projected finish is after the plan (negative when early); null without a projection.
  int? get daysLate => projected == null ? null : daysBetween(end, projected!);
}

/// Every chart task in [categoryId] (null = all, '' = no category), open or ticked off.
List<Task> burnTasks(AppData data, String? categoryId) {
  bool inCat(Task t) => categoryId == null ||
      (categoryId.isEmpty ? data.category(t.categoryId) == null : t.categoryId == categoryId);
  return [
    for (final t in data.active)
      if (t.gantt && inCat(t)) t,
    for (final t in data.archived)
      if (t.gantt && inCat(t)) t,
  ];
}

/// The burn-down for [tasks] (see [burnTasks]), or null when none has dates.
BurnDown? burnDown(List<Task> tasks, AppData data, DateTime now, {BurnUnit unit = BurnUnit.items}) {
  // Each piece of work: how much it is worth and when it was done (null = not yet).
  final pieces = <(double, DateTime?)>[];
  DateTime? start, end;
  for (final t in tasks) {
    final bar = barFor(t, data);
    if (bar == null) continue;
    final s = t.planStart != null ? dayOf(t.planStart!) : bar.start;
    if (start == null || s.isBefore(start)) start = s;
    if (end == null || bar.end.isAfter(end)) end = bar.end;
    final weight = unit == BurnUnit.items ? null : workDays(bar.start, bar.end, weekends: weekendsFor(t, data)).toDouble();
    if (t.steps.isEmpty) {
      pieces.add((weight ?? 1, t.closedAt));
    } else {
      final each = weight == null ? 1.0 : weight / t.steps.length;
      for (final st in t.steps) {
        // A step ticked before tick times were kept (1.8.6) counts as done from the start.
        pieces.add((each, st.done ? (st.doneAt ?? t.closedAt ?? DateTime(2000)) : t.closedAt));
      }
    }
  }
  if (start == null || end == null) return null;
  final today = dayOf(now);
  if (start.isAfter(today)) start = today;
  final total = pieces.fold(0.0, (a, p) => a + p.$1);
  final left = <double>[];
  for (var d = start; !d.isAfter(today); d = addDays(d, 1)) {
    final next = addDays(d, 1);
    left.add(total - pieces.where((p) => p.$2 != null && p.$2!.isBefore(next)).fold(0.0, (a, p) => a + p.$1));
  }
  // Pace over the last 14 days (or since the start, if sooner).
  final from = addDays(today, -13).isBefore(start) ? start : addDays(today, -13);
  final days = daysBetween(from, today) + 1;
  final doneLately =
      pieces.where((p) => p.$2 != null && !p.$2!.isBefore(from)).fold(0.0, (a, p) => a + p.$1);
  final remaining = left.last;
  DateTime? projected;
  if (remaining <= 0) {
    projected = today;
  } else if (doneLately > 0) {
    projected = addDays(today, (remaining / (doneLately / days)).ceil());
  }
  return BurnDown(start, end, total, left, projected, unit);
}

/// One line about a burn-down, for the chart's caption and for sharing.
String burnSummary(BurnDown b) {
  final left = b.now == b.now.roundToDouble() ? b.now.toInt().toString() : b.now.toStringAsFixed(1);
  final unit = b.unit == BurnUnit.items
      ? (left == '1' ? 'task or step' : 'tasks and steps')
      : (left == '1' ? 'day of work' : 'days of work');
  final fmt = DateFormat('EEE d MMM');
  final late = b.daysLate;
  final pace = b.projected == null
      ? 'nothing done in the last two weeks'
      : b.now <= 0
          ? 'all done'
          : 'at this pace done ${fmt.format(b.projected!)}'
              '${late == null || late == 0 ? ', on plan' : late > 0 ? ', $late day${late == 1 ? '' : 's'} after the plan' : ', ${-late} day${late == -1 ? '' : 's'} early'}';
  return '$left $unit left, planned to finish ${fmt.format(b.end)}; $pace';
}
