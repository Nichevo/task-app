import 'dart:math';

import 'gantt.dart';
import 'models.dart';

/// Item 114 D: the critical path on the Gantt chart, and when each bar should happen.

/// When a bar should happen. Stored as [Task.timing] / [TaskStep.timing] by [id].
enum Timing {
  asap('asap', 'As soon as possible', 'Starts the day after what it comes after ends, and moves earlier when that finishes early.'),
  alap('alap', 'As late as possible', 'Ends right before what comes after it needs it (uses up the spare time).'),
  fixed('fixed', 'Start on a date', 'Stays where you put it. Warns if what it comes after isn\'t done.'),
  finishBy('finishBy', 'Must finish by', 'Works back from its due date to the latest start.');

  const Timing(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;

  static Timing? byId(String? id) => values.where((t) => t.id == id).firstOrNull;
}

/// Item 114 D: the timing given to new tasks and steps (Settings).
extension TimingPrefs on AppData {
  Timing get newTiming => Timing.byId(helperPrefs['ganttTiming'] as String?) ?? Timing.asap;
  set newTiming(Timing v) => helperPrefs['ganttTiming'] = v.id;
}

/// One bar in a critical path: a task, or a step of one.
class CpItem {
  CpItem({
    required this.task,
    this.step,
    required this.start,
    required this.days,
    required this.after,
    this.lag = 0,
    this.done = false,
    this.doneOn,
    this.due,
  });

  final Task task;
  final TaskStep? step;
  String get id => step?.id ?? task.id;
  String get title => step?.title ?? task.title;

  /// Where its bar starts now (null: no dates yet).
  final DateTime? start;

  /// Days of work.
  final int days;

  /// Ids of the items it comes after.
  final List<String> after;

  /// Days to wait after those end.
  final int lag;
  final bool done;

  /// The day it was ticked off.
  final DateTime? doneOn;
  final DateTime? due;
}

/// Where one item sits: earliest and latest start and end, and its spare (slack) working days.
class CpNode {
  CpNode(this.item);
  final CpItem item;
  late DateTime es, ef, ls, lf;

  /// Working days it can slip without moving the finish (negative: it is already too late).
  int slack = 0;
  bool critical = false;
}

class CpResult {
  CpResult(this.nodes, this.order, this.finish, this.anchor, this.weekends);

  final Map<String, CpNode> nodes;

  /// Every item, each after what it comes after.
  final List<CpNode> order;

  /// When the last one ends.
  final DateTime finish;

  /// What the latest dates are worked back from (the finish, or a due date).
  final DateTime anchor;
  final bool weekends;

  CpNode? operator [](String id) => nodes[id];

  /// The open items that set the finish, in order.
  List<CpNode> get path => [
        for (final n in order)
          if (n.critical && !n.item.done) n,
      ]..sort((a, b) => a.es.compareTo(b.es));

  /// The earliest of the latest starts of the open items: start no later than this.
  DateTime? get startBy {
    DateTime? out;
    for (final n in order) {
      if (n.item.done) continue;
      if (out == null || n.ls.isBefore(out)) out = n.ls;
    }
    return out;
  }
}

DateTime _nextWork(DateTime d, bool weekends) {
  var x = dayOf(d);
  while (!weekends && isWeekend(x)) {
    x = addDays(x, 1);
  }
  return x;
}

DateTime _prevWork(DateTime d, bool weekends) {
  var x = dayOf(d);
  while (!weekends && isWeekend(x)) {
    x = addDays(x, -1);
  }
  return x;
}

/// Working days from [a] to [b]: 0 on the same day, negative when [b] is before [a].
int workGap(DateTime a, DateTime b, {required bool weekends}) {
  if (daysBetween(a, b) == 0) return 0;
  if (b.isBefore(a)) return -workGap(b, a, weekends: weekends);
  var n = 0;
  for (var d = addDays(dayOf(a), 1); !d.isAfter(dayOf(b)); d = addDays(d, 1)) {
    if (weekends || !isWeekend(d)) n++;
  }
  return n;
}

/// [items] in an order where each comes after what it comes after (loops are broken).
List<CpItem> _sorted(List<CpItem> items) {
  final ids = {for (final i in items) i.id};
  final left = {for (final i in items) i.id: i.after.where((a) => ids.contains(a) && a != i.id).toSet()};
  final out = <CpItem>[];
  final placed = <String>{};
  while (out.length < items.length) {
    var any = false;
    for (final i in items) {
      if (placed.contains(i.id) || !left[i.id]!.every(placed.contains)) continue;
      out.add(i);
      placed.add(i.id);
      any = true;
    }
    if (!any) {
      // A loop: take the first one left as it is.
      final i = items.firstWhere((i) => !placed.contains(i.id));
      out.add(i);
      placed.add(i.id);
    }
  }
  return out;
}

/// Works out the critical path of [items].
///
/// With [from], every open item starts as early as its links allow, the ones that come after
/// nothing on [from] (earliest starts). Without it, each starts where its bar is now. The latest
/// dates are worked back from [anchor] (a due date) or, without it, from the finish. The items
/// with the least spare time (none, or less) are critical.
CpResult criticalPath(List<CpItem> items, {required bool weekends, DateTime? from, DateTime? anchor}) {
  final order = _sorted(items);
  final nodes = <String, CpNode>{for (final i in order) i.id: CpNode(i)};
  final fallback = dayOf(from ?? DateTime.now());
  for (final i in order) {
    final n = nodes[i.id]!;
    if (i.done) {
      final day = dayOf(i.doneOn ?? i.start ?? fallback);
      n.es = n.ef = day;
      continue;
    }
    DateTime? es = from == null ? i.start : null;
    if (es == null) {
      DateTime? latest;
      for (final a in i.after) {
        final p = nodes[a];
        if (p == null || identical(p, n) || !_ready(p, order, i)) continue;
        if (latest == null || p.ef.isAfter(latest)) latest = p.ef;
      }
      es = latest == null ? (i.start != null && from == null ? i.start! : fallback) : addDays(latest, 1 + i.lag);
      if (from != null && es.isBefore(dayOf(from))) es = dayOf(from);
    }
    n.es = _nextWork(es, weekends);
    n.ef = workEnd(n.es, i.days, weekends: weekends);
  }
  var finish = order.isEmpty ? fallback : nodes[order.first.id]!.ef;
  for (final n in nodes.values) {
    if (n.ef.isAfter(finish)) finish = n.ef;
  }
  final end = dayOf(anchor ?? finish);
  for (var k = order.length - 1; k >= 0; k--) {
    final i = order[k];
    final n = nodes[i.id]!;
    DateTime lf = end;
    for (final f in order.skip(k + 1)) {
      if (!f.after.contains(i.id)) continue;
      final s = nodes[f.id]!;
      if (f.done) continue;
      final limit = _prevWork(addDays(s.ls, -1 - f.lag), weekends);
      if (limit.isBefore(lf)) lf = limit;
    }
    if (i.done) {
      n.lf = n.ef;
      n.ls = n.es;
      continue;
    }
    n.lf = _prevWork(lf, weekends);
    n.ls = workStart(n.lf, i.days, weekends: weekends);
    n.slack = workGap(n.es, n.ls, weekends: weekends);
  }
  final open = [for (final n in nodes.values) if (!n.item.done) n.slack];
  final tight = open.isEmpty ? 0 : max(0, open.reduce(min));
  for (final n in nodes.values) {
    n.critical = !n.item.done && n.slack <= tight;
  }
  return CpResult(nodes, [for (final i in order) nodes[i.id]!], finish, end, weekends);
}

/// Whether [p] was worked out before [i] (always, unless a loop was broken).
bool _ready(CpNode p, List<CpItem> order, CpItem i) => order.indexOf(p.item) < order.indexOf(i);

// --- What goes in ---

/// The items for [t]'s steps. [undated] also takes steps without dates (a day each unless they
/// have a length), for working out dates they don't have yet.
List<CpItem> stepItems(Task t, AppData data, {bool undated = false}) {
  final weekends = weekendsFor(t, data);
  return [
    for (final s in t.steps)
      if (stepBar(t, s, data) case final b when b != null || undated || s.done)
        CpItem(
          task: t,
          step: s,
          start: b?.start,
          days: b != null && !stepIsPoint(s) ? workDays(b.start, b.end, weekends: weekends) : max(1, s.takesDays ?? 1),
          after: s.afterIds,
          done: s.done,
          doneOn: s.doneAt == null ? b?.end : dayOf(s.doneAt!),
          due: s.dueAt,
        ),
  ];
}

/// The items for [tasks] that have bars.
List<CpItem> taskItems(Iterable<Task> tasks, AppData data) {
  return [
    for (final t in tasks)
      if (barFor(t, data) case final b?)
        CpItem(
          task: t,
          start: b.start,
          days: workDays(b.start, b.end, weekends: weekendsFor(t, data)),
          after: t.afterIds,
          lag: t.lagDays ?? 0,
          done: t.closedAt != null,
          doneOn: t.closedAt == null ? null : dayOf(t.closedAt!),
          due: t.dueAt,
        ),
  ];
}

/// The critical path of [t]'s steps, worked back from the task's due date when it has one and
/// that is after the finish (so spare time shows).
CpResult? taskStepPath(Task t, AppData data) {
  final items = stepItems(t, data);
  if (items.where((i) => !i.done).isEmpty) return null;
  final r = criticalPath(items, weekends: weekendsFor(t, data));
  final due = t.dueAt;
  if (due == null || dayOf(due).isBefore(r.finish)) return r;
  return criticalPath(items, weekends: weekendsFor(t, data), anchor: due);
}

/// The critical path across [tasks], worked back from the latest due date among the ones that
/// end last, when that is after the finish.
CpResult? tasksPath(Iterable<Task> tasks, AppData data) {
  final items = taskItems(tasks, data);
  if (items.where((i) => !i.done).isEmpty) return null;
  final weekends = data.ganttWeekends;
  final r = criticalPath(items, weekends: weekends);
  DateTime? due;
  for (final n in r.order) {
    final d = n.item.due;
    if (n.item.done || d == null || daysBetween(n.ef, r.finish) != 0) continue;
    if (due == null || d.isAfter(due)) due = d;
  }
  if (due == null || dayOf(due).isBefore(r.finish)) return r;
  return criticalPath(items, weekends: weekends, anchor: due);
}

// --- Keeping each bar where its timing says ---

/// Moves a bar so it starts on [start] (its start and due date together). Returns whether it moved.
bool _startOn(Task t, TaskStep? s, DateTime start, AppData data) {
  final bar = s == null ? barFor(t, data) : stepBar(t, s, data);
  if (bar == null) {
    // No dates yet: a start, when it has a length.
    if (s != null && s.takesDays != null) {
      s.startAt = start;
      return true;
    }
    if (s == null && t.gantt && t.takesDays != null) {
      t.startAt = start;
      return true;
    }
    return false;
  }
  final days = daysBetween(bar.start, start);
  if (days == 0) return false;
  if (s == null) {
    shiftDates(t, days);
  } else {
    if (s.startAt != null) s.startAt = addDays(s.startAt!, days);
    if (s.dueAt != null) s.dueAt = addDays(s.dueAt!, days);
    if (s.startAt == null && s.dueAt == null) s.startAt = start;
  }
  return true;
}

/// Puts each open bar of [t]'s steps where its timing says: as soon as possible after what it
/// comes after, as late as possible before what comes after it (or the task's due date), or
/// worked back from its own due date. Fixed ones, and ones without a timing, stay. Returns how
/// many moved.
int applyStepTimings(Task t, AppData data) {
  final weekends = weekendsFor(t, data);
  final moved = <String>{};
  final order = _sorted(stepItems(t, data, undated: true));
  for (var pass = 0; pass < 3; pass++) {
    var any = false;
    for (final i in order) {
      final s = i.step!;
      if (s.done) continue;
      final timing = Timing.byId(s.timing);
      if (timing == Timing.finishBy) {
        if (s.dueAt != null && s.takesDays != null && s.startAt != null) {
          s.startAt = null;
          moved.add(s.id);
          any = true;
        }
        continue;
      }
      if (timing != Timing.asap && timing != Timing.alap) continue;
      final earliest = stepEarliestStart(t, s, data);
      if (timing == Timing.asap) {
        if (earliest == null) continue;
        if (_startOn(t, s, _nextWork(earliest, weekends), data)) {
          moved.add(s.id);
          any = true;
        }
      }
    }
    // As late as possible: last first.
    for (final i in order.reversed) {
      final s = i.step!;
      if (s.done || Timing.byId(s.timing) != Timing.alap) continue;
      DateTime? limit;
      var followers = false;
      for (final f in t.steps) {
        if (f.done || !f.afterIds.contains(s.id)) continue;
        followers = true;
        final fb = stepBar(t, f, data);
        if (fb == null) continue;
        final l = _prevWork(addDays(fb.start, -1), weekends);
        if (limit == null || l.isBefore(limit)) limit = l;
      }
      if (!followers && t.dueAt != null) limit = _prevWork(t.dueAt!, weekends);
      if (limit == null) continue;
      final days = max(1, i.days);
      var start = workStart(limit, days, weekends: weekends);
      final earliest = stepEarliestStart(t, s, data);
      if (earliest != null && start.isBefore(earliest)) start = _nextWork(earliest, weekends);
      if (_startOn(t, s, start, data)) {
        moved.add(s.id);
        any = true;
      }
    }
    if (!any) break;
  }
  return moved.length;
}

/// The same for open tasks on the Gantt chart. Returns the tasks that moved.
Set<Task> applyTaskTimings(AppData data) {
  final moved = <Task>{};
  final tasks = data.ganttTasks.where((t) => t.closedAt == null).toList();
  final order = _sorted([
    for (final t in tasks) CpItem(task: t, start: null, days: 1, after: t.afterIds),
  ]);
  for (var pass = 0; pass < 3; pass++) {
    var any = false;
    for (final i in order) {
      final t = i.task;
      final timing = Timing.byId(t.timing);
      if (timing == Timing.finishBy) {
        if (t.dueAt != null && t.takesDays != null && t.startAt != null && !t.milestone) {
          t.startAt = null;
          moved.add(t);
          any = true;
        }
        continue;
      }
      if (timing != Timing.asap) continue;
      final earliest = earliestStart(t, data);
      if (earliest == null) continue;
      if (_startOn(t, null, _nextWork(earliest, weekendsFor(t, data)), data)) {
        moved.add(t);
        any = true;
      }
    }
    for (final i in order.reversed) {
      final t = i.task;
      if (Timing.byId(t.timing) != Timing.alap) continue;
      final weekends = weekendsFor(t, data);
      final bar = barFor(t, data);
      if (bar == null) continue;
      DateTime? limit;
      var followers = false;
      for (final f in tasks) {
        if (!f.afterIds.contains(t.id)) continue;
        followers = true;
        final fb = barFor(f, data);
        if (fb == null) continue;
        final l = _prevWork(addDays(fb.start, -1 - (f.lagDays ?? 0)), weekends);
        if (limit == null || l.isBefore(limit)) limit = l;
      }
      if (!followers && t.dueAt != null) limit = _prevWork(t.dueAt!, weekends);
      if (limit == null) continue;
      var start = workStart(limit, workDays(bar.start, bar.end, weekends: weekends), weekends: weekends);
      final earliest = earliestStart(t, data);
      if (earliest != null && start.isBefore(earliest)) start = _nextWork(earliest, weekends);
      if (_startOn(t, null, start, data)) {
        moved.add(t);
        any = true;
      }
    }
    if (!any) break;
  }
  return moved;
}

/// "2 d spare", "critical", "1 d late".
String describeSlack(CpNode n) {
  if (n.item.done) return 'done';
  if (n.slack < 0) return '${-n.slack} d late';
  if (n.critical) return 'critical';
  return '${n.slack} d spare';
}

