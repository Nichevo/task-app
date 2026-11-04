import 'dart:math';

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
