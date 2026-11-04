import 'package:intl/intl.dart';

import 'gantt.dart';
import 'habits.dart';
import 'models.dart';

/// Item 76: what was achieved in a category over a period, for the Achievements page.

enum AchievePeriod {
  thisWeek('This week'),
  lastWeek('Last week'),
  fourWeeks('Last 4 weeks'),
  threeMonths('Last 3 months');

  const AchievePeriod(this.label);
  final String label;

  /// [from] (inclusive) to [to] (exclusive). Weeks run Monday to Sunday.
  (DateTime, DateTime) range(DateTime now) {
    final today = dayOf(now);
    final monday = addDays(today, -(today.weekday - 1));
    return switch (this) {
      thisWeek => (monday, addDays(today, 1)),
      lastWeek => (addDays(monday, -7), monday),
      fourWeeks => (addDays(monday, -28), monday),
      threeMonths => (DateTime(today.year, today.month - 3, today.day), addDays(today, 1)),
    };
  }
}

/// A task finished in the period, with its plan against what happened.
class FinishedTask {
  FinishedTask(this.task, this.stepsTicked, this.daysWorked);

  final Task task;
  final int stepsTicked;
  final int daysWorked;

  DateTime get done => task.closedAt!;

  /// When it was meant to start and be done: the first plan on the chart, else its dates.
  DateTime? get planStart => task.planStart ?? task.startAt;
  DateTime? get planDue => task.planDue ?? task.dueAt;

  /// When work really started: its start date or the first day ticked as worked, whichever is
  /// earlier.
  DateTime? get actualStart {
    final days = [for (final k in task.worked) ?DateTime.tryParse(k)]..sort();
    final first = days.firstOrNull;
    final s = task.startAt == null ? null : dayOf(task.startAt!);
    if (first == null) return s;
    if (s == null) return first;
    return first.isBefore(s) ? first : s;
  }

  /// Days after the planned due day it was ticked off (negative when early); null with no due.
  int? get daysLate => planDue == null ? null : daysBetween(planDue!, done);
}

/// A task worked on in the period but not finished.
class WorkedTask {
  WorkedTask(this.task, this.daysWorked, this.stepsTicked);

  final Task task;
  final int daysWorked;
  final int stepsTicked;
}

class Achievements {
  Achievements(this.data, this.period, this.now, {this.categoryId}) {
    final (f, t) = period.range(now);
    from = f;
    to = t;
  }

  final AppData data;
  final AchievePeriod period;
  final DateTime now;

  /// null = every category, '' = no category.
  final String? categoryId;
  late final DateTime from;
  late final DateTime to;

  bool _inCat(String? id) => categoryId == null ||
      (categoryId!.isEmpty ? data.category(id) == null : id == categoryId);

  bool _within(DateTime? d) => d != null && !d.isBefore(from) && d.isBefore(to);

  Iterable<Task> get _all => [...data.active, ...data.archived].where((t) => _inCat(t.categoryId));

  int _daysIn(Task t) => t.worked.where((k) {
        final d = DateTime.tryParse(k);
        return d != null && _within(d);
      }).length;

  int _stepsIn(Task t) => t.steps.where((s) => s.done && _within(s.doneAt)).length;

  /// Tasks ticked off in the period (from the done record, which outlives the archive).
  int get tasksDone => data.done.values.where((r) => _within(r.at) && _inCat(r.categoryId)).length;

  /// Steps ticked in the period (steps keep their tick time since 1.8.6).
  int get stepsTicked => _all.fold(0, (n, t) => n + _stepsIn(t));

  /// Different days with any task ticked as worked on (habits are counted apart).
  int get daysWorked => {
        for (final t in _all.where((t) => !t.habit))
          for (final k in t.worked)
            if (_within(DateTime.tryParse(k))) k,
      }.length;

  /// Task-days: each day ticked on each task.
  int get taskDays => _all.where((t) => !t.habit).fold(0, (n, t) => n + _daysIn(t));

  /// Item 78: each habit with the days ticked in the period and the days it was meant to happen
  /// (for times a week, its weekly number spread over the period).
  List<(Task, int, int)> get habits {
    final last = to.isAfter(addDays(dayOf(now), 1)) ? addDays(dayOf(now), 1) : to;
    return [
      for (final t in data.habits)
        if (_inCat(t.categoryId))
          () {
            var due = 0;
            for (var d = from; d.isBefore(last); d = addDays(d, 1)) {
              if (scheduledOn(t, d)) due++;
            }
            if (t.habitGoal == HabitGoal.perWeek) due = (due * t.habitTimes / 7).round();
            return (t, _daysIn(t), due);
          }(),
    ];
  }

  List<FinishedTask> get finished => [
        for (final t in data.archived)
          if (_inCat(t.categoryId) && _within(t.closedAt)) FinishedTask(t, _stepsIn(t), _daysIn(t)),
      ]..sort((a, b) => a.done.compareTo(b.done));

  List<WorkedTask> get unfinished => [
        for (final t in data.active)
          if (!t.habit && _inCat(t.categoryId) && (_daysIn(t) > 0 || _stepsIn(t) > 0))
            WorkedTask(t, _daysIn(t), _stepsIn(t)),
      ]..sort((a, b) => b.daysWorked.compareTo(a.daysWorked));

  String get categoryName => categoryId == null
      ? 'All categories'
      : categoryId!.isEmpty
          ? 'No category'
          : data.category(categoryId)?.name ?? 'Category';

  /// The page as plain text, to paste into a message or a report.
  String asText() {
    final day = DateFormat('EEE d MMM');
    String plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';
    final b = StringBuffer()
      ..writeln('$categoryName: ${period.label.toLowerCase()} (${day.format(from)} to ${day.format(addDays(to, -1))})')
      ..writeln('${plural(tasksDone, 'task')} done, ${plural(stepsTicked, 'step')} ticked, '
          '${plural(daysWorked, 'day')} worked');
    final f = finished;
    if (f.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Finished');
      for (final x in f) {
        b.writeln('- ${x.task.title}: done ${day.format(x.done)}${planLine(x).isEmpty ? '' : ', ${planLine(x)}'}');
      }
    }
    final u = unfinished;
    if (u.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Worked on, not finished');
      for (final x in u) {
        final steps = x.task.steps.isEmpty ? '' : ', ${x.task.stepsDone} of ${x.task.steps.length} steps';
        b.writeln('- ${x.task.title}: ${plural(x.daysWorked, 'day')}$steps');
      }
    }
    final h = habits;
    if (h.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Habits');
      for (final (t, done, due) in h) {
        b.writeln('- ${t.title}: $done of $due');
      }
    }
    return b.toString().trimRight();
  }
}

/// "due Fri 6 Nov, 1 day early", or '' with no plan.
String planLine(FinishedTask x) {
  final late = x.daysLate;
  if (late == null) return '';
  final when = late == 0
      ? 'on the day'
      : late > 0
          ? '$late day${late == 1 ? '' : 's'} late'
          : '${-late} day${late == -1 ? '' : 's'} early';
  return 'due ${DateFormat('EEE d MMM').format(x.planDue!)}, $when';
}
