import 'dart:math';

import 'gantt.dart';
import 'models.dart';

/// Item 78: the habit tracker's arithmetic. A habit's ticks are its worked days (item 75).

/// Whether [t] was paused on [day].
bool pausedOn(Task t, DateTime day) {
  final k = dayKey(day);
  for (final p in t.habitPauses) {
    final i = p.indexOf('/');
    if (i < 0) continue;
    final from = p.substring(0, i), to = p.substring(i + 1);
    if (k.compareTo(from) >= 0 && (to.isEmpty || k.compareTo(to) <= 0)) return true;
  }
  return false;
}

/// Whether [day] is one the habit is meant to happen on (any day, for times a week).
bool scheduledOn(Task t, DateTime day) {
  if (pausedOn(t, day)) return false;
  return t.habitGoal != HabitGoal.weekdays || t.habitDays.contains(day.weekday);
}

DateTime mondayOf(DateTime d) => addDays(dayOf(d), -(d.weekday - 1));

/// Ticks in the week (Monday to Sunday) holding [day].
int ticksInWeek(Task t, DateTime day) {
  final m = mondayOf(day);
  return [for (var i = 0; i < 7; i++) addDays(m, i)].where(t.workedOn).length;
}

/// Whether it still wants doing today: scheduled and not ticked, or for times a week, not yet
/// enough this week. Ticked today counts as due (and done).
bool dueToday(Task t, DateTime now) {
  final today = dayOf(now);
  if (pausedOn(t, today)) return false;
  if (t.workedOn(today)) return true;
  return switch (t.habitGoal) {
    HabitGoal.perWeek => ticksInWeek(t, today) < t.habitTimes,
    _ => scheduledOn(t, today),
  };
}

/// "Habits today: 2 of 5": (ticked today, due today).
(int, int) habitsToday(AppData data, DateTime now) {
  final due = data.habits.where((t) => dueToday(t, now)).toList();
  return (due.where((t) => t.workedOn(now)).length, due.length);
}

/// The current streak: days in a row (weeks in a row for times a week). Today doesn't break it
/// before it is ticked. Paused days are skipped. With [Task.habitFreeMiss], one missed day each
/// week (Monday to Sunday) is forgiven on every-day habits.
int streak(Task t, DateTime now) {
  final today = dayOf(now);
  if (t.habitGoal == HabitGoal.perWeek) {
    var n = 0;
    var week = mondayOf(today);
    if (ticksInWeek(t, week) >= t.habitTimes) n++;
    for (var i = 0; i < 260; i++) {
      week = addDays(week, -7);
      // A week paused throughout is skipped.
      if ([for (var d = 0; d < 7; d++) addDays(week, d)].every((d) => pausedOn(t, d))) continue;
      if (ticksInWeek(t, week) < t.habitTimes) break;
      n++;
    }
    return n;
  }
  var n = 0;
  final forgiven = <DateTime>{};
  var day = today;
  if (!t.workedOn(today)) day = addDays(today, -1);
  final earliest = _firstTick(t);
  if (earliest == null) return 0;
  for (var i = 0; i < 1100 && !day.isBefore(earliest); i++, day = addDays(day, -1)) {
    if (t.workedOn(day)) {
      n++;
      continue;
    }
    if (!scheduledOn(t, day)) continue;
    final week = mondayOf(day);
    if (t.habitGoal == HabitGoal.daily && t.habitFreeMiss && !forgiven.contains(week)) {
      forgiven.add(week);
      continue;
    }
    break;
  }
  return n;
}

DateTime? _firstTick(Task t) {
  DateTime? first;
  for (final k in t.worked) {
    final d = DateTime.tryParse(k);
    if (d != null && (first == null || d.isBefore(first))) first = d;
  }
  return first;
}

/// The longest streak in days (every day or chosen days) or weeks (times a week), for the
/// month view. Worked out the same way as [streak], across all its history.
int bestStreak(Task t, DateTime now) {
  final first = _firstTick(t);
  if (first == null) return 0;
  var best = 0;
  // Ending the streak on each ticked day and taking the longest is simple and quick enough for
  // a few years of ticks.
  for (final k in t.worked) {
    final d = DateTime.tryParse(k);
    if (d == null) continue;
    best = max(best, streak(t, d));
  }
  return best;
}

/// How much of the month holding [month] it was done: 0 to 1, up to today. Null when nothing was
/// due yet.
double? monthScore(Task t, DateTime month, DateTime now) {
  final today = dayOf(now);
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1, 0);
  final end = last.isAfter(today) ? today : last;
  if (end.isBefore(first)) return null;
  var due = 0, done = 0;
  for (var d = first; !d.isAfter(end); d = addDays(d, 1)) {
    if (t.workedOn(d)) done++;
    if (scheduledOn(t, d)) due++;
  }
  if (t.habitGoal == HabitGoal.perWeek) {
    final target = due * t.habitTimes / 7;
    return target <= 0 ? null : min(done / target, 1.0);
  }
  return due == 0 ? null : min(done / due, 1.0);
}

/// "Every day", "3 times a week", "Mon, Wed, Fri".
String goalText(Task t) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return switch (t.habitGoal) {
    HabitGoal.daily => 'Every day',
    HabitGoal.perWeek => '${t.habitTimes} time${t.habitTimes == 1 ? '' : 's'} a week',
    HabitGoal.weekdays => t.habitDays.length == 7
        ? 'Every day'
        : ([...t.habitDays]..sort()).map((d) => names[d - 1]).join(', '),
  };
}

/// "5 days", "3 weeks".
String streakText(Task t, int n) {
  final unit = t.habitGoal == HabitGoal.perWeek ? 'week' : 'day';
  return '$n $unit${n == 1 ? '' : 's'}';
}

/// When the habit's reminder should next go off: today at its time if it is due and not ticked
/// yet, else the next day it is scheduled. Null with no reminder or while paused.
DateTime? nextHabitReminder(Task t, DateTime now) {
  final at = t.habitRemind;
  if (at == null || t.habitPaused) return null;
  for (var i = 0; i < 8; i++) {
    final day = addDays(dayOf(now), i);
    final when = DateTime(day.year, day.month, day.day, at ~/ 60, at % 60);
    if (!when.isAfter(now) || t.workedOn(day)) continue;
    final wanted = t.habitGoal == HabitGoal.perWeek ? ticksInWeek(t, day) < t.habitTimes : scheduledOn(t, day);
    if (wanted) return when;
  }
  return null;
}
