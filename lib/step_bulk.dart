import 'gantt.dart';
import 'models.dart';

/// Item 80: the arithmetic behind "Edit all steps", kept apart from the screen so it can be
/// tested. Changing several steps at once, moving their dates and lining them up in order.

/// A copy of all of [t]'s steps, so the screen can undo a change.
List<Map<String, dynamic>> snapshotSteps(Task t) => [for (final s in t.steps) s.toJson()];

/// Puts [t]'s steps back as they were in [snap].
void restoreSteps(Task t, List<Map<String, dynamic>> snap) {
  t.steps
    ..clear()
    ..addAll(snap.map(TaskStep.fromJson));
}

/// Moves the start and due dates of [steps] by [days] (earlier when negative). Steps without
/// dates are left alone.
void moveStepDates(Iterable<TaskStep> steps, int days) {
  if (days == 0) return;
  for (final s in steps) {
    if (s.startAt != null) s.startAt = addDays(s.startAt!, days);
    if (s.dueAt != null) s.dueAt = addDays(s.dueAt!, days);
  }
}

/// What "Line up in order" does with due dates.
enum LineUpDue {
  /// Only steps without a due date get one (their end day).
  fillMissing,

  /// Every lined-up step's due date becomes its end day.
  setAll,

  /// Due dates stay as they are.
  keep,
}

/// One lined-up step: where it would start and end.
class LineUpSlot {
  const LineUpSlot(this.step, this.start, this.end, this.takes);

  final TaskStep step;
  final DateTime start;
  final DateTime end;
  final int takes;
}

/// Works out where [steps] go when lined up one after another from [from], in the order given.
/// Each takes its own days of work, or [defaultDays] when it has none, with [gap] free days in
/// between. Without [weekends] no step starts or ends on a Saturday or Sunday, and the gap
/// counts working days. Ticked steps are skipped.
List<LineUpSlot> planLineUp(
  List<TaskStep> steps, {
  required DateTime from,
  required bool weekends,
  int gap = 0,
  int defaultDays = 1,
}) {
  final slots = <LineUpSlot>[];
  var next = dayOf(from);
  for (final s in steps) {
    if (s.done) continue;
    final takes = s.takesDays ?? (defaultDays < 1 ? 1 : defaultDays);
    final start = workEnd(next, 1, weekends: weekends);
    final end = workEnd(start, takes, weekends: weekends);
    slots.add(LineUpSlot(s, start, end, takes));
    // The day after it ends, then [gap] free working days.
    next = addDays(end, 1);
    for (var i = 0; i < gap; i++) {
      next = addDays(workEnd(next, 1, weekends: weekends), 1);
    }
  }
  return slots;
}

/// Writes a plan from [planLineUp] into its steps. A due date it sets is at [dueHour] on the end
/// day. Steps without days of work get the number they were lined up with.
void applyLineUp(List<LineUpSlot> slots, {LineUpDue due = LineUpDue.fillMissing, int dueHour = 17}) {
  for (final p in slots) {
    final s = p.step;
    s.startAt = p.start;
    s.takesDays = p.takes;
    final end = DateTime(p.end.year, p.end.month, p.end.day, dueHour);
    switch (due) {
      case LineUpDue.fillMissing:
        s.dueAt ??= end;
      case LineUpDue.setAll:
        s.dueAt = end;
      case LineUpDue.keep:
        break;
    }
  }
}

/// The day after [s] ends on the chart (for "Start after this step"), or null when it has no
/// dates.
DateTime? dayAfterStep(Task t, TaskStep s, AppData data) {
  final bar = stepBar(t, s, data);
  return bar == null ? null : addDays(bar.end, 1);
}
