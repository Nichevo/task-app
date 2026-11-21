import 'dart:math';

import 'day_plan.dart';
import 'estimates.dart';
import 'gantt.dart' show stepsBefore;
import 'models.dart';
import 'native.dart' show CalendarEvent;
import 'widgets/task_colors.dart' show ageProgress;

/// Item 114 C: Plan my day and What should I do now. Both rank the same way: what is overdue,
/// then due soonest, the matrix Do box, starred, In progress, then the oldest (reddest).

/// One thing to do: a task, or the next open step of one.
class Pick {
  Pick(this.task, this.step, this.minutes, this.score, this.why);
  final Task task;
  final TaskStep? step;

  /// How long to give it (its estimate, stretched by how far off estimates usually are).
  final int minutes;
  final double score;

  /// Short reasons, most important first ("Due Friday", "Do box"...).
  final List<String> why;

  String get title => step?.title ?? task.title;

  /// "Step 2 of 5" for a step.
  String? get stepLabel {
    final s = step;
    if (s == null) return null;
    return 'Step ${task.steps.indexOf(s) + 1} of ${task.steps.length}';
  }
}

/// A planned suggestion: [pick] at [start].
class PlannedPick {
  PlannedPick(this.pick, this.start);
  final Pick pick;
  final DateTime start;
  DateTime get end => start.add(Duration(minutes: pick.minutes));
}

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

/// The next open step of [t] that isn't waiting for another open step; null when it has none.
TaskStep? nextStep(Task t) {
  for (final s in t.steps) {
    if (s.done) continue;
    if (stepsBefore(t, s).any((b) => !b.done)) continue;
    return s;
  }
  return null;
}

/// How much [t] should be done next, with why. [now] is when it would be done.
(double, List<String>) scoreTask(AppData data, Task t, DateTime now) {
  var score = 0.0;
  final why = <String>[];
  final due = t.dueAt;
  if (due != null) {
    final days = _d(due).difference(_d(now)).inDays;
    if (due.isBefore(now)) {
      score += 100 + min(30, now.difference(due).inDays * 3);
      why.add('Overdue');
    } else if (days == 0) {
      score += 80;
      why.add('Due today');
    } else if (days <= 7) {
      score += 60 - days * 6;
      why.add(days == 1 ? 'Due tomorrow' : 'Due in $days days');
    } else {
      score += max(0, 15 - days / 3);
    }
  }
  switch (MatrixBox.byId(t.matrixBox)) {
    case MatrixBox.doNow:
      score += 30;
      why.add('${data.boxName(MatrixBox.doNow)} box');
    case MatrixBox.decide:
      score += 10;
    case MatrixBox.delete:
      score -= 30;
    default:
      break;
  }
  if (t.starred) {
    score += 20;
    why.add('Starred');
  }
  if (t.kanban && (t.stageId == 'doing' || data.stage(t.stageId)?.name.trim().toLowerCase() == 'in progress')) {
    score += 15;
    why.add('In progress');
  }
  final age = ageProgress(t, data.hoursToRed, byDue: data.colourByDue, now: now);
  score += min(15, age * 12);
  if (age >= 1 && due == null) why.add('Getting old');
  return (score, why);
}

/// The length to give [t] (or [step]), allowing for how far off estimates usually are.
int pickMinutes(AppData data, Task t, TaskStep? step, DateTime now) {
  final base = planLength(data, t, step);
  final f = estimateFactor(data, t.categoryId, now);
  final snap = max(5, data.dayPlan.snap);
  return max(snap, ((base * f) / snap).round() * snap);
}

/// Every open task worth suggesting (by [score]); a task with steps is suggested as its next
/// open step. [hidden] says which tasks to leave out (a focus mode, the Day plan's chips).
List<Pick> rankPicks(AppData data, DateTime now, {bool Function(Task t)? hidden}) {
  final out = <Pick>[];
  for (final t in data.active) {
    if (t.habit || t.isSnoozed(now) || data.isLocked(t) || (hidden?.call(t) ?? false)) continue;
    if (t.matrixBox == MatrixBox.delegate.id && (t.waitingOn?.isNotEmpty ?? false)) continue;
    final step = t.steps.isEmpty ? null : nextStep(t);
    if (t.steps.isNotEmpty && step == null && t.steps.any((s) => !s.done)) continue;
    final (score, why) = scoreTask(data, t, now);
    out.add(Pick(t, step, pickMinutes(data, t, step, now), score, why));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// Item 114 C: the Plan my day options in [AppData.helperPrefs].
extension PlanPrefs on AppData {
  /// Share of the free time left free (0.15 = 15%).
  double get planLeaveFree => (helperPrefs['planFree'] as num?)?.toDouble() ?? 0.15;
  set planLeaveFree(double v) => helperPrefs['planFree'] = v;

  /// Lunch, minutes after midnight; null start = no lunch kept.
  int? get lunchStart => helperPrefs.containsKey('lunchStart') ? (helperPrefs['lunchStart'] as num?)?.toInt() : 12 * 60;
  set lunchStart(int? v) => helperPrefs['lunchStart'] = v;
  int get lunchMinutes => (helperPrefs['lunchLen'] as num?)?.toInt() ?? 60;
  set lunchMinutes(int v) => helperPrefs['lunchLen'] = v;

  /// What now may use where the phone is.
  bool get nowUsesPlace => helperPrefs['nowPlace'] as bool? ?? true;
  set nowUsesPlace(bool v) => helperPrefs['nowPlace'] = v;
}

/// Item 114 C: fills [day]'s free working time with the most important open tasks and steps,
/// best first, each in the first free stretch it fits. Leaves [AppData.planLeaveFree] of the
/// free time free and keeps lunch. [attempt] > 0 tries a different mix (Try again). Nothing is
/// saved: the caller plans the result.
List<PlannedPick> planDay(AppData data, DateTime day, {DateTime? now, List<CalendarEvent> events = const [], int attempt = 0}) {
  now ??= DateTime.now();
  final layout = layoutDay(data, day, events: events);
  final snap = max(5, data.dayPlan.snap);
  final gap = data.dayPlan.gapMinutes;
  // Free stretches, from now on when it's today, without lunch.
  var free = <(DateTime, DateTime)>[
    for (final f in layout.free) (f.start, f.end),
  ];
  if (_d(day) == _d(now)) {
    final from = snapUp(now, snap);
    free = [
      for (final (s, e) in free)
        if (e.isAfter(from)) (s.isBefore(from) ? from : s, e),
    ];
  }
  final ls = data.lunchStart;
  if (ls != null) {
    final l0 = DateTime(day.year, day.month, day.day).add(Duration(minutes: ls));
    final l1 = l0.add(Duration(minutes: data.lunchMinutes));
    free = [
      for (final (s, e) in free) ...[
        if (s.isBefore(l0)) (s, e.isBefore(l0) ? e : l0),
        if (e.isAfter(l1)) (s.isAfter(l1) ? s : l1, e),
      ],
    ].where((x) => x.$2.difference(x.$1).inMinutes >= snap).toList();
  }
  final total = free.fold(0, (a, x) => a + x.$2.difference(x.$1).inMinutes);
  var budget = (total * (1 - data.planLeaveFree)).round();
  // Already planned on this day: not again.
  final planned = {
    for (final b in layout.all) '${b.task.id}/${b.step?.id ?? ''}',
  };
  var picks = rankPicks(data, day.isAfter(now) ? DateTime(day.year, day.month, day.day, 9) : now,
          hidden: (t) => planHides(data, t, now: now))
      .where((p) => !planned.contains('${p.task.id}/${p.step?.id ?? ''}') && !planned.contains('${p.task.id}/'))
      .toList();
  if (attempt > 0) {
    // A different mix: the order shaken among picks of about the same weight.
    final rnd = Random(attempt);
    picks = [for (final p in picks) (p, p.score + rnd.nextDouble() * 40)].toList()
        .sorted((a, b) => b.$2.compareTo(a.$2))
        .map((x) => x.$1)
        .toList();
  }
  final out = <PlannedPick>[];
  for (final p in picks) {
    if (budget < snap) break;
    if (p.minutes > budget + snap) continue;
    final i = free.indexWhere((x) => x.$2.difference(x.$1).inMinutes >= p.minutes);
    if (i < 0) continue;
    final (s, e) = free[i];
    out.add(PlannedPick(p, s));
    budget -= p.minutes;
    final next = s.add(Duration(minutes: p.minutes + gap));
    free[i] = (next, e);
    if (!next.isBefore(e)) free.removeAt(i);
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

extension<T> on List<T> {
  List<T> sorted(int Function(T a, T b) compare) => [...this]..sort(compare);
}

/// Item 114 C: what fits now.
class NowAdvice {
  NowAdvice(this.picks, {this.freeMinutes, this.until, this.planned = false});

  /// Best first; empty when there is nothing to suggest.
  final List<Pick> picks;

  /// Minutes until the next meeting, event or planned time (null: nothing else today).
  final int? freeMinutes;

  /// What comes next ("Team lunch").
  final String? until;

  /// The first pick is planned for now on the Day plan.
  final bool planned;
}

/// Item 114 C: one thing to do now (and a few more), from the time to the next fixed thing
/// today, the focus mode and where the phone is ([place], a saved place's name).
NowAdvice whatNow(AppData data, DateTime now, {List<CalendarEvent> events = const [], String? place}) {
  final layout = layoutDay(data, now, events: events);
  // Something planned right now comes first.
  final current = layout.all
      .where((b) => !b.done && !b.start.isAfter(now) && b.end.isAfter(now) && !b.shared)
      .firstOrNull;
  // The next fixed thing: a block, a work meeting or a phone event starting later today.
  final starts = <(DateTime, String)>[
    for (final b in layout.all)
      if (!b.done && b.start.isAfter(now) && !identical(b, current)) (b.start, b.step?.title ?? b.task.title),
    for (final e in layout.events)
      if (e.start.isAfter(now)) (e.start, e.event.title),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final next = starts.firstOrNull;
  final free = next?.$1.difference(now).inMinutes;
  final picks = <Pick>[];
  for (final p in rankPicks(data, now, hidden: (t) => !data.inMode(t))) {
    var score = p.score;
    final why = [...p.why];
    if (free != null) {
      if (p.minutes <= free) {
        score += 25;
        why.insert(0, next == null ? 'Fits' : 'Fits before ${next.$2}');
      } else {
        score -= 20;
      }
      if (free <= 30 && p.minutes <= 15) {
        score += 10;
        why.add('Quick win');
      }
    }
    final at = p.task.place ?? p.task.where?.name;
    if (place != null && at != null) {
      if (at.toLowerCase() == place.toLowerCase()) {
        score += 30;
        why.insert(0, 'You\'re at $place');
      } else {
        score -= 40;
      }
    }
    picks.add(Pick(p.task, p.step, p.minutes, score, why));
  }
  picks.sort((a, b) => b.score.compareTo(a.score));
  if (current != null) {
    final t = current.task;
    final step = current.step;
    picks.removeWhere((p) => identical(p.task, t) && p.step == step);
    picks.insert(0, Pick(t, step, current.end.difference(now).inMinutes, double.infinity, ['Planned now']));
  }
  return NowAdvice(picks.take(4).toList(), freeMinutes: free, until: next?.$2, planned: current != null);
}
