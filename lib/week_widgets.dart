import 'dart:math';

import 'day_plan.dart' show planLength;
import 'gantt.dart' show workdayMinutes;
import 'models.dart';

/// Item 115: the week and month widgets (A, B, G, H, I, J) with a second city's clock.
///
/// The app shares each day's tasks, dated steps and work meetings, and how busy each day is; the
/// widgets add the phone's calendar events, hide what the widget's focus mode hides, and work out
/// both clocks themselves (time zones come from the phone).

/// A city the second clock can show: its time zone and the name to show.
class ClockCity {
  const ClockCity(this.zone, this.name, this.area);
  final String zone;
  final String name;

  /// Where else shares the zone, for the picker.
  final String area;
}

/// Time zones offered for the second clock (any other IANA name can be typed in).
const clockCities = [
  ClockCity('Asia/Shanghai', 'Jingzhou', 'China: Jingzhou, Wuhan, Shanghai, Beijing'),
  ClockCity('Asia/Hong_Kong', 'Hong Kong', 'Hong Kong'),
  ClockCity('Asia/Taipei', 'Taipei', 'Taiwan'),
  ClockCity('Asia/Singapore', 'Singapore', 'Singapore, Kuala Lumpur'),
  ClockCity('Asia/Tokyo', 'Tokyo', 'Japan'),
  ClockCity('Asia/Seoul', 'Seoul', 'South Korea'),
  ClockCity('Asia/Kolkata', 'Mumbai', 'India'),
  ClockCity('Asia/Bangkok', 'Bangkok', 'Thailand, Vietnam'),
  ClockCity('Australia/Sydney', 'Sydney', 'Sydney, Melbourne, Canberra'),
  ClockCity('Australia/Brisbane', 'Brisbane', 'Queensland'),
  ClockCity('Australia/Perth', 'Perth', 'Western Australia'),
  ClockCity('Pacific/Auckland', 'Auckland', 'New Zealand'),
  ClockCity('Europe/London', 'London', 'UK, Ireland'),
  ClockCity('Europe/Berlin', 'Berlin', 'Germany, France, Netherlands'),
  ClockCity('America/New_York', 'New York', 'US Eastern'),
  ClockCity('America/Chicago', 'Chicago', 'US Central'),
  ClockCity('America/Los_Angeles', 'Los Angeles', 'US Pacific'),
];

/// The clock and week options (synced, in [AppData.helperPrefs]).
extension WeekWidgetPrefs on AppData {
  /// Whether the week and month widgets show the two clocks.
  bool get clocksOn => helperPrefs['clocksOn'] as bool? ?? true;
  set clocksOn(bool v) => helperPrefs['clocksOn'] = v;

  /// The name for this phone's own time ('' = the phone's time zone city).
  String get clockHome => helperPrefs['clockHome'] as String? ?? '';
  set clockHome(String v) => helperPrefs['clockHome'] = v.trim();

  /// The second city's time zone (IANA name) and the name shown for it.
  String get clockZone => helperPrefs['clockZone'] as String? ?? 'Asia/Shanghai';
  set clockZone(String v) => helperPrefs['clockZone'] = v.trim();
  String get clockCity => helperPrefs['clockCity'] as String? ?? 'Jingzhou';
  set clockCity(String v) => helperPrefs['clockCity'] = v.trim();

  /// Which week: 'next7' (today and the 6 days after) or 'monday' (Monday to Sunday).
  String get weekShown => helperPrefs['weekShown'] as String? ?? 'next7';
  set weekShown(String v) => helperPrefs['weekShown'] = v;

  /// Whether the week widgets leave Saturday and Sunday out.
  bool get weekNoWeekend => helperPrefs['weekNoWeekend'] as bool? ?? false;
  set weekNoWeekend(bool v) => helperPrefs['weekNoWeekend'] = v;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The days the week widgets show, from [now] and the week setting.
List<DateTime> weekDays(AppData data, DateTime now) {
  final today = _day(now);
  final first = data.weekShown == 'monday' ? today.subtract(Duration(days: today.weekday - 1)) : today;
  return [
    for (var i = 0; i < 7; i++)
      if (!(data.weekNoWeekend && DateTime(first.year, first.month, first.day + i).weekday > 5))
        DateTime(first.year, first.month, first.day + i),
  ];
}

/// What the week and month widgets are given (read by WeekWidgets.kt and WeekKinds.swift).
Map<String, dynamic> weekWidgetData(AppData data, DateTime now) {
  final today = _day(now);
  final days = weekDays(data, now);
  final from = days.isEmpty ? today : (days.first.isBefore(today) ? days.first : today);
  final to = days.isEmpty ? today.add(const Duration(days: 1)) : days.last.add(const Duration(days: 1));
  final items = <Map<String, dynamic>>[];

  void add(DateTime at, Map<String, dynamic> item) {
    final d = _day(at);
    if (d.isBefore(from) || !d.isBefore(to)) return;
    items.add({'day': dayKey(d), ...item});
  }

  for (final t in data.active) {
    if (t.habit) continue;
    final due = t.dueAt;
    if (due != null) {
      final over = due.isBefore(today);
      final timed = due.hour != 0 || due.minute != 0;
      add(over ? today : due, {
        'id': t.id,
        'title': t.title,
        if (timed && !over) 'at': due.millisecondsSinceEpoch,
        if (over) 'over': true,
        'kind': 'task',
        'min': planLength(data, t),
      });
    }
    for (final s in t.steps) {
      final sd = s.dueAt ?? s.startAt;
      if (s.done || sd == null) continue;
      final over = sd.isBefore(today);
      add(over ? today : sd, {
        'id': t.id,
        'step': s.id,
        'title': s.title,
        'task': t.title,
        if (over) 'over': true,
        'kind': 'step',
        'min': planLength(data, t, s),
      });
    }
  }
  for (final e in data.workEvents(from, to)) {
    if (data.linkedToMeeting(e.id) != null) continue;
    add(e.start, {
      'id': e.id,
      'title': e.title,
      if (!e.allDay) 'at': e.start.millisecondsSinceEpoch,
      if (!e.allDay) 'end': e.end.millisecondsSinceEpoch,
      'kind': 'meet',
      'min': e.allDay ? 0 : e.end.difference(e.start).inMinutes,
    });
  }
  items.sort((a, b) {
    final c = (a['day'] as String).compareTo(b['day'] as String);
    if (c != 0) return c;
    final ao = a['over'] == true ? 0 : 1, bo = b['over'] == true ? 0 : 1;
    if (ao != bo) return ao - bo;
    final at = a['at'] as int?, bt = b['at'] as int?;
    if (at != null && bt != null) return at.compareTo(bt);
    return at != null ? -1 : (bt != null ? 1 : 0);
  });
  return {
    'clocks': {
      'on': data.clocksOn,
      'home': data.clockHome,
      'zone': data.clockZone,
      'city': data.clockCity,
    },
    'days': [for (final d in days) dayKey(d)],
    'items': items,
    'busy': busyDays(data, now),
    'workday': workdayMinutes(data),
  };
}

/// Minutes booked per day (tasks and steps by their length, work meetings by theirs) from a week
/// before this month to six weeks on, for the coloured month and the week's shading. The widgets
/// add the phone's calendar events.
Map<String, int> busyDays(AppData data, DateTime now) {
  final from = DateTime(now.year, now.month, 1).subtract(const Duration(days: 7));
  final to = DateTime(now.year, now.month + 1, 1).add(const Duration(days: 42));
  final out = <String, int>{};
  void add(DateTime at, int m) {
    if (at.isBefore(from) || !at.isBefore(to) || m <= 0) return;
    final k = dayKey(at);
    out[k] = (out[k] ?? 0) + m;
  }

  for (final t in data.active) {
    if (t.habit) continue;
    if (t.dueAt case final d?) add(d, planLength(data, t));
    for (final s in t.steps) {
      if (!s.done && (s.dueAt ?? s.startAt) != null) add((s.dueAt ?? s.startAt)!, planLength(data, t, s));
    }
  }
  for (final e in data.workEvents(from, to)) {
    if (!e.allDay) add(e.start, max(0, e.end.difference(e.start).inMinutes));
  }
  return out;
}

/// How busy a day is, 0 (free) to 4 (full or more), for [minutes] against a [workday].
int busyLevel(int minutes, int workday) {
  if (minutes <= 0) return 0;
  final f = minutes / max(60, workday);
  return f < 0.25 ? 1 : f < 0.55 ? 2 : f < 0.85 ? 3 : 4;
}
