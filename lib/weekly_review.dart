import 'day_plan.dart' show layoutDay;
import 'daily_helpers.dart' show dueOn;
import 'models.dart';
import 'stats.dart';
import 'widgets/task_colors.dart' show ageProgress;

/// Item 114 E: the weekly review screen, one pile at a time: last week, what slipped, what is
/// ageing, what has stalled, and next week.

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _counts(Task t) => !t.habit;

/// How last week went.
class LastWeek {
  LastWeek({required this.done, required this.added, required this.focusMinutes, required this.doneTitles});
  final int done;
  final int added;
  final int focusMinutes;

  /// A few of the things done, newest first.
  final List<String> doneTitles;
}

LastWeek lastWeek(AppData data, DateTime now) {
  final r = Stats(data, now).weekReview(now);
  final from = _day(now).subtract(const Duration(days: 7));
  var focus = 0;
  for (final t in [...data.active, ...data.archived]) {
    t.focus.forEach((k, v) {
      final d = DateTime.tryParse(k);
      if (d != null && !d.isBefore(from) && d.isBefore(now)) focus += v;
    });
  }
  final recent = [
    for (final e in data.done.entries)
      if (!e.value.at.isBefore(from) && e.value.at.isBefore(now)) e.value,
  ]..sort((a, b) => b.at.compareTo(a.at));
  return LastWeek(
    done: r.done,
    added: r.added,
    focusMinutes: focus,
    doneTitles: [for (final d in recent.take(5)) ?d.title],
  );
}

/// Open tasks whose due date has passed, oldest first.
List<Task> slipped(AppData data, DateTime now) => [
      for (final t in data.active)
        if (_counts(t) && t.dueAt != null && t.dueAt!.isBefore(_day(now))) t,
    ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

/// Open tasks with no due date that are turning orange or red, oldest first.
List<Task> ageing(AppData data, DateTime now) {
  final out = [
    for (final t in data.active)
      if (_counts(t) && t.dueAt == null && !t.isSnoozed(now) && ageProgress(t, data.hoursToRed, now: now) >= 0.66) t,
  ];
  out.sort((a, b) => ageProgress(b, data.hoursToRed, now: now).compareTo(ageProgress(a, data.hoursToRed, now: now)));
  return out;
}

/// Open tasks with open steps where no step has been ticked for [days] days (and the task is
/// at least that old).
List<Task> stalled(AppData data, DateTime now, {int days = 14}) {
  final since = now.subtract(Duration(days: days));
  return [
    for (final t in data.active)
      if (_counts(t) &&
          t.steps.any((s) => !s.done) &&
          t.createdAt.isBefore(since) &&
          !t.steps.any((s) => s.doneAt != null && s.doneAt!.isAfter(since)))
        t,
  ];
}

/// One day of next week.
class WeekDay {
  WeekDay(this.day, {required this.due, required this.dueMinutes, required this.meetings, required this.freeMinutes});
  final DateTime day;
  final int due;

  /// The estimates of what is due that day.
  final int dueMinutes;
  final int meetings;
  final int freeMinutes;
  bool get tooFull => dueMinutes > freeMinutes;
}

/// The first day of "next week": Monday when the review is on Friday to Sunday, otherwise
/// tomorrow.
DateTime nextWeekStart(DateTime now) {
  final d = _day(now);
  if (d.weekday >= DateTime.friday) return DateTime(d.year, d.month, d.day + 8 - d.weekday);
  return DateTime(d.year, d.month, d.day + 1);
}

/// The next seven days from [nextWeekStart], leaving out weekend days with nothing on them.
List<WeekDay> nextWeek(AppData data, DateTime now) {
  final start = nextWeekStart(now);
  final out = <WeekDay>[];
  for (var i = 0; i < 7; i++) {
    final day = DateTime(start.year, start.month, start.day + i);
    final due = dueOn(data, day);
    final meetings = data.workMeetings.where((m) => !m.allDay && _day(m.start) == day).length;
    final weekend = day.weekday >= DateTime.saturday;
    if (weekend && due.isEmpty && meetings == 0) continue;
    final layout = layoutDay(data, day);
    out.add(WeekDay(
      day,
      due: due.length,
      dueMinutes: due.fold(0, (a, t) => a + (t.estimate ?? 0)),
      meetings: meetings,
      freeMinutes: weekend ? 0 : layout.free.fold(0, (a, f) => a + f.end.difference(f.start).inMinutes),
    ));
  }
  return out;
}

/// The next working day after [now] (for "Mon" on a slipped task).
DateTime nextWorkday(DateTime now) {
  var d = DateTime(now.year, now.month, now.day + 1);
  while (d.weekday >= DateTime.saturday) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}
