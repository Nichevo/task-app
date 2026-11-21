import 'package:intl/intl.dart';

import 'models.dart';
import 'modes.dart' show everythingId;

/// Item 114 B: the morning brief and the end-of-day wrap up.

DateTime _startOf(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);
bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _hm(DateTime d) => DateFormat('HH:mm').format(d);
String _n(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// When a daily helper comes on [day], or null when not that day. With [DailyAt.follow] and a
/// mode schedule, only days with a scheduled mode count; [end] then puts it at the end of that
/// day's last scheduled mode (the wrap up), unless the set time is later.
DateTime? dailyTime(AppData data, DailyAt set, DateTime day, {bool end = false}) {
  final at = DateTime(day.year, day.month, day.day, set.at ~/ 60, set.at % 60);
  final slots = [
    for (final s in data.modeSchedule)
      if (s.day == day.weekday && s.mode != everythingId) s,
  ];
  if (set.follow && data.modeSchedule.isNotEmpty) {
    if (slots.isEmpty) return null;
    if (!end) return at;
    final last = slots.map((s) => s.end).reduce((a, b) => a > b ? a : b);
    final fromSchedule = DateTime(day.year, day.month, day.day, last ~/ 60, last % 60);
    return fromSchedule.isAfter(at) ? fromSchedule : at;
  }
  return set.days.contains(day.weekday) ? at : null;
}

/// A thing on a day: a work meeting or a planned time.
typedef DayItem = ({DateTime start, String title, bool meeting});

/// The work meetings (not all-day) and open planned times on [day], in order.
List<DayItem> dayItems(AppData data, DateTime day) {
  final out = <DayItem>[
    for (final m in data.workMeetings)
      if (!m.allDay && _sameDay(m.start, day)) (start: m.start, title: m.title, meeting: true),
    for (final t in data.active)
      for (final s in t.slots)
        if (s.doneAt == null && _sameDay(s.start, day))
          (
            start: s.start,
            title: s.stepId == null
                ? t.title
                : t.steps.where((x) => x.id == s.stepId).firstOrNull?.title ?? t.title,
            meeting: false,
          ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Open tasks (not habits) due on [day].
List<Task> dueOn(AppData data, DateTime day) => [
      for (final t in data.active)
        if (!t.habit && t.dueAt != null && _sameDay(t.dueAt!, day)) t,
    ];

/// Open tasks (not habits) due before [day] started.
List<Task> overdueBefore(AppData data, DateTime day) => [
      for (final t in data.active)
        if (!t.habit && t.dueAt != null && t.dueAt!.isBefore(_startOf(day)) && !t.isSnoozed(day)) t,
    ];

/// The morning brief for [at]: (title, body).
(String, String) briefText(AppData data, DateTime at) {
  final items = dayItems(data, at);
  final meetings = items.where((i) => i.meeting).length;
  final planned = items.where((i) => !i.meeting).length;
  final due = dueOn(data, at);
  final overdue = overdueBefore(data, at);
  final first = items.where((i) => !i.start.isBefore(at)).firstOrNull;
  final day = DateFormat('EEEE').format(at);
  final title = meetings + planned == 0
      ? '$day: nothing planned yet'
      : '$day: ${[if (meetings > 0) _n(meetings, 'meeting'), if (planned > 0) '$planned planned'].join(', ')}';
  String names(List<Task> ts) => ts.take(3).map((t) => t.title).join(', ') + (ts.length > 3 ? '…' : '');
  final body = [
    if (first != null) 'First up: ${first.title} at ${_hm(first.start)}.',
    if (due.isNotEmpty) 'Due today: ${names(due)}.',
    if (overdue.isNotEmpty) '${_n(overdue.length, 'task')} overdue.',
    if (first == null && due.isEmpty && overdue.isEmpty) 'Nothing due today.',
  ].join(' ');
  return (title, body);
}

/// What is still open at the end of [day]: tasks due that day or earlier, and tasks with a
/// planned time that day that isn't ticked, nearest first.
List<Task> leftOpen(AppData data, DateTime day) {
  final end = _nextDay(_startOf(day));
  final out = <Task>[];
  for (final t in data.active) {
    if (t.habit || t.isSnoozed(day)) continue;
    final due = t.dueAt != null && t.dueAt!.isBefore(end);
    final planned = t.slots.any((s) => s.doneAt == null && _sameDay(s.start, day));
    if (due || planned) out.add(t);
  }
  out.sort((a, b) => (a.dueAt ?? end).compareTo(b.dueAt ?? end));
  return out;
}

/// Tasks ticked off on [day].
int doneOn(AppData data, DateTime day) => data.done.values.where((r) => _sameDay(r.at, day)).length;

/// The wrap up notification for [at]: (title, body).
(String, String) wrapText(AppData data, DateTime at) {
  final open = leftOpen(data, at);
  final done = doneOn(data, at);
  final title = open.isEmpty
      ? (done == 0 ? 'Wrap up: nothing left for today' : '${_n(done, 'task')} done today, nothing left')
      : '${done > 0 ? '$done done today, ' : ''}${open.length} still open';
  final body = open.isEmpty
      ? 'See what tomorrow holds.'
      : '${open.take(3).map((t) => t.title).join(', ')}${open.length > 3 ? '…' : ''}. Tap to move them on.';
  return (title, body);
}

/// Where a task left open on one day goes on [to]: its due date (kept time, only when due by
/// the end of [from]) and its unticked planned times on [from] (same time of day).
({DateTime? due, Map<TimeSlot, DateTime> slots}) rollPlan(Task t, DateTime from, DateTime to) {
  DateTime onTo(DateTime d) => DateTime(to.year, to.month, to.day, d.hour, d.minute);
  final end = _nextDay(_startOf(from));
  final due = t.dueAt != null && t.dueAt!.isBefore(end) ? onTo(t.dueAt!) : null;
  return (
    due: due,
    slots: {
      for (final s in t.slots)
        if (s.doneAt == null && _sameDay(s.start, from)) s: onTo(s.start),
    },
  );
}
