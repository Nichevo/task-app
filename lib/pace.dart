import 'models.dart';

/// Item 96: whether a task (or step) is keeping up with its due date: the share of work done
/// against the share of time gone since it started.
enum Pace {
  behind('Behind'),
  onPace('On pace'),
  ahead('Ahead');

  const Pace(this.label);
  final String label;
}

/// Work done and time gone for one task or step, with the verdict.
class PaceInfo {
  const PaceInfo({this.done, this.used, this.verdict, this.stepsBehind});

  /// Share of work done, 0 to 1; null when there is nothing to measure it by (no steps and no
  /// progress set by hand).
  final double? done;

  /// Share of the time to the due date already gone: 0 at the start, 1 at the due date, more
  /// when overdue. Null without a due date.
  final double? used;

  /// Null when it can't be told: no due date, or nothing to measure work by and not overdue.
  final Pace? verdict;

  /// For a task measured by its steps: about how many steps behind (or ahead, negative).
  final int? stepsBehind;

  bool get overdue => (used ?? 0) >= 1;

  /// "Behind by 2 steps", "On pace", "Overdue", or null.
  String? get label {
    final v = verdict;
    if (v == null) return null;
    if (v == Pace.behind && overdue && (done ?? 0) < 1) return 'Overdue';
    final n = stepsBehind;
    if (v == Pace.behind && n != null && n > 0) return 'Behind by $n step${n == 1 ? '' : 's'}';
    return v.label;
  }

  static const none = PaceInfo();
}

/// Share of the time from [start] to [due] gone at [now]. Not capped, so overdue is over 1.
double? timeUsed(DateTime? start, DateTime? due, DateTime now) {
  if (due == null) return null;
  final total = start == null ? 0 : due.difference(start).inMinutes;
  if (total <= 0) return now.isBefore(due) ? 0 : 1;
  return now.difference(start!).inMinutes / total;
}

/// When a task's time starts counting: its start day when it is on the Gantt chart, otherwise
/// when its colour clock started (added, or later if it waited or was snoozed), as the card's
/// colour does. (Moving a task into In progress fills in its start day, so that alone mustn't
/// restart the clock.)
DateTime paceStart(Task t, DateTime now) {
  final s = t.gantt ? t.startAt : null;
  return s != null ? DateTime(s.year, s.month, s.day) : t.colourStart(now);
}

/// Whether the task has anything to measure work by.
bool hasProgress(Task t) => t.progress != null || t.steps.isNotEmpty;

/// The task's pace. Open tasks only; habits never have one.
PaceInfo taskPace(Task t, DateTime now) {
  if (t.closedAt != null || t.habit) return PaceInfo.none;
  final done = hasProgress(t) ? t.progressShare : null;
  final used = timeUsed(paceStart(t, now), t.dueAt, now);
  if (used == null) return PaceInfo(done: done);
  if (used >= 1) return PaceInfo(done: done, used: used, verdict: Pace.behind);
  if (done == null) return PaceInfo(used: used);
  final gap = used - done;
  // Measured by steps: half a step either way counts as on pace. By hand: ten percent.
  final steps = t.progress == null ? t.steps.length : 0;
  if (steps > 0) {
    final n = gap * steps;
    final verdict = n >= 0.5
        ? Pace.behind
        : n <= -0.5
        ? Pace.ahead
        : Pace.onPace;
    return PaceInfo(done: done, used: used, verdict: verdict, stepsBehind: n.round());
  }
  final verdict = gap >= 0.1
      ? Pace.behind
      : gap <= -0.1
      ? Pace.ahead
      : Pace.onPace;
  return PaceInfo(done: done, used: used, verdict: verdict);
}

/// A step's pace, by its own progress and its own due date (counted from its start day on the
/// Gantt chart, or else from when its task's time started). Ticked steps have none.
PaceInfo stepPace(Task t, TaskStep st, DateTime now) {
  if (st.done) return const PaceInfo(done: 1);
  final s = t.gantt ? st.startAt : null;
  final start = s != null ? DateTime(s.year, s.month, s.day) : paceStart(t, now);
  final used = timeUsed(start, st.dueAt, now);
  final done = st.share;
  if (used == null) return PaceInfo(done: done);
  if (used >= 1) return PaceInfo(done: done, used: used, verdict: Pace.behind);
  final gap = used - done;
  final verdict = gap >= 0.1
      ? Pace.behind
      : gap <= -0.1
      ? Pace.ahead
      : Pace.onPace;
  return PaceInfo(done: done, used: used, verdict: verdict);
}
