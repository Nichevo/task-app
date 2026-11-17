import 'dart:math';

import 'focus_timer.dart';
import 'models.dart';
import 'pace.dart';
import 'widgets/task_colors.dart';

/// Item 102: focus modes. A mode is a saved view of the whole app (Work, Weekend, Travel...) that
/// decides which categories and tools show. "Everything" ([everythingId]) is the app as it was
/// before modes, and is what shows whenever no mode is chosen or scheduled.
const everythingId = 'all';

/// How a category shows in a mode.
enum CatShow {
  show('Show'),
  quiet('Quiet'),
  hide('Hide');

  const CatShow(this.label);
  final String label;
}

/// The views and pages a mode can switch off. The main list is always there.
enum ModeTool {
  board('Kanban board'),
  gantt('Gantt chart'),
  matrix('Matrix'),
  calendar('Calendar'),
  dayPlan('Day plan'),
  habits('Habits'),
  starred('Starred emails'),
  events('Upcoming events'),
  stats('Statistics'),
  achievements('Achievements');

  const ModeTool(this.label);
  final String label;
}

/// How soon a hidden task's due time must be for it to break through.
enum DueWithin {
  off('Off'),
  twoHours('2 hours'),
  today('Today'),
  tomorrow('By the end of tomorrow'),
  threeDays('3 days'),
  week('7 days');

  const DueWithin(this.label);
  final String label;

  /// The latest due time that counts, from [now]; null when off.
  DateTime? limit(DateTime now) => switch (this) {
        off => null,
        twoHours => now.add(const Duration(hours: 2)),
        today => DateTime(now.year, now.month, now.day + 1),
        tomorrow => DateTime(now.year, now.month, now.day + 2),
        threeDays => now.add(const Duration(days: 3)),
        week => now.add(const Duration(days: 7)),
      };
}

/// The colours a mode can have (ARGB).
const modeColours = [0xFF3F6FB5, 0xFF8A5BB5, 0xFFD2793A, 0xFF2E8B57, 0xFFB5475B, 0xFF5B7A8A, 0xFF8A7A2E, 0xFF006A6A];

/// Icon names a mode can have; the screens map them to icons.
const modeIcons = ['work', 'home', 'travel', 'laptop', 'weekend', 'fitness', 'school', 'star'];

class FocusMode {
  FocusMode({
    required this.id,
    required this.name,
    this.colour = 0xFF3F6FB5,
    this.icon = 'work',
    Map<String, CatShow>? cats,
    this.otherCats = CatShow.show,
    Set<String>? toolsOff,
    this.panel,
    this.filter,
    this.newCategory,
    this.overdue = true,
    this.due = DueWithin.today,
    this.starred = true,
    this.red = false,
    this.planned = true,
    this.pauseHabits = true,
    List<String>? places,
    this.placeWhen,
    List<String>? events,
    this.timer,
    Map<String, dynamic>? extra,
  })  : cats = cats ?? {},
        toolsOff = toolsOff ?? {},
        places = places ?? [],
        events = events ?? [],
        extra = extra ?? {};

  final String id;
  String name;
  int colour;
  String icon;

  /// By category id ('' = tasks with no category). A category not listed (one added later) gets
  /// [otherCats].
  final Map<String, CatShow> cats;
  CatShow otherCats;

  /// [ModeTool] names switched off in this mode.
  final Set<String> toolsOff;

  /// Fold right-hand panel view to open on (PanelView name); null = as set on the device.
  String? panel;

  /// Quick filter chip to start with (QuickFilter name); null = leave it as it is.
  String? filter;

  /// Category new tasks go into ('' = none); null = as usual (typed words, auto category).
  String? newCategory;

  /// What still breaks through from hidden categories.
  bool overdue;
  DueWithin due;
  bool starred;

  /// Gone red (ageing colour) or Behind on pace.
  bool red;

  /// Has a planned time on the Day plan today.
  bool planned;

  /// Habits in hidden categories pause: no reminders, and the days don't break their streaks.
  bool pauseHabits;

  /// Saved place names (Settings, Places) where this mode comes on by itself.
  final List<String> places;

  /// A place only switches to this mode while the weekly schedule says this mode id (Home office:
  /// at Home while the schedule says Work); null = any time.
  String? placeWhen;

  /// Words in a calendar event's title that switch to this mode while it lasts ("Flight", "WFH").
  final List<String> events;

  /// Item 108: the focus timer's own round lengths in this mode (Work 50/10, Home 25/5); null =
  /// the lengths set for every mode. Its Do not disturb choice isn't used (that one is shared).
  FocusSettings? timer;

  final Map<String, dynamic> extra;

  static const _known = {
    'id', 'name', 'colour', 'icon', 'cats', 'other', 'off', 'panel', 'filter', 'newCat', 'overdue', 'due',
    'starred', 'red', 'planned', 'habits', 'places', 'placeWhen', 'events', 'timer',
  };

  bool toolOn(ModeTool t) => !toolsOff.contains(t.name);

  CatShow showFor(AppData data, String? categoryId) {
    final known = categoryId != null && data.category(categoryId) != null;
    return cats[known ? categoryId : ''] ?? otherCats;
  }

  factory FocusMode.create(String name, {int? colour, String icon = 'star'}) => FocusMode(
      id: 'm${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}',
      name: name,
      colour: colour ?? modeColours.first,
      icon: icon);

  FocusMode copy() => FocusMode.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'name': name,
        'colour': colour,
        'icon': icon,
        if (cats.isNotEmpty) 'cats': {for (final e in cats.entries) e.key: e.value.name},
        if (otherCats != CatShow.show) 'other': otherCats.name,
        if (toolsOff.isNotEmpty) 'off': toolsOff.toList(),
        if (panel != null) 'panel': panel,
        if (filter != null) 'filter': filter,
        if (newCategory != null) 'newCat': newCategory,
        if (!overdue) 'overdue': false,
        if (due != DueWithin.today) 'due': due.name,
        if (!starred) 'starred': false,
        if (red) 'red': true,
        if (!planned) 'planned': false,
        if (!pauseHabits) 'habits': false,
        if (places.isNotEmpty) 'places': places,
        if (placeWhen != null) 'placeWhen': placeWhen,
        if (events.isNotEmpty) 'events': events,
        if (timer != null) 'timer': timer!.toJson()..remove('dnd'),
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;

  factory FocusMode.fromJson(Map<String, dynamic> j) => FocusMode(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        colour: (j['colour'] as num?)?.toInt() ?? modeColours.first,
        icon: j['icon'] as String? ?? 'star',
        cats: {
          for (final e in (j['cats'] as Map? ?? {}).entries)
            e.key as String: _enum(CatShow.values, e.value, CatShow.show),
        },
        otherCats: _enum(CatShow.values, j['other'], CatShow.show),
        toolsOff: {for (final t in j['off'] as List? ?? []) t as String},
        panel: j['panel'] as String?,
        filter: j['filter'] as String?,
        newCategory: j['newCat'] as String?,
        overdue: j['overdue'] as bool? ?? true,
        due: _enum(DueWithin.values, j['due'], DueWithin.today),
        starred: j['starred'] as bool? ?? true,
        red: j['red'] as bool? ?? false,
        planned: j['planned'] as bool? ?? true,
        pauseHabits: j['habits'] as bool? ?? true,
        places: [for (final p in j['places'] as List? ?? []) if (p is String) p],
        placeWhen: j['placeWhen'] as String?,
        events: [for (final e in j['events'] as List? ?? []) if (e is String) e],
        timer: j['timer'] is Map ? FocusSettings.parse(j['timer']) : null,
        extra: unknownFields(j, _known),
      );
}

/// One painted stretch of the weekly schedule: [day] (DateTime.monday..sunday), minutes after
/// midnight [start] to [end] (end up to 24 * 60), in [mode].
class ModeSlot {
  ModeSlot({required this.day, required this.start, required this.end, required this.mode});

  final int day;
  final int start;
  final int end;
  final String mode;

  Map<String, dynamic> toJson() => {'day': day, 'start': start, 'end': end, 'mode': mode};

  static ModeSlot? tryParse(Object? v) {
    if (v is! Map) return null;
    final day = (v['day'] as num?)?.toInt(), s = (v['start'] as num?)?.toInt(), e = (v['end'] as num?)?.toInt();
    final m = v['mode'] as String?;
    if (day == null || s == null || e == null || m == null || day < 1 || day > 7 || e <= s) return null;
    return ModeSlot(day: day, start: s.clamp(0, 24 * 60), end: e.clamp(0, 24 * 60), mode: m);
  }
}

/// A stretch of time spent in a mode, for the statistics. [end] null = still going.
class ModeLog {
  ModeLog({
    required this.id,
    required this.mode,
    required this.start,
    this.end,
    this.how = 'schedule',
    this.peeks = 0,
    this.device,
  });

  final String id;
  final String mode;
  final DateTime start;
  DateTime? end;

  /// 'hand' (picked by hand), 'schedule' or 'none' (nothing scheduled: Everything).
  final String how;
  int peeks;

  /// Review fix: the device that logged it (each device has its own mode); null in logs from
  /// before 1.12.12.
  final String? device;

  factory ModeLog.open(String mode, DateTime start, String how, {String? device}) => ModeLog(
    id: 'l${start.microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}',
    mode: mode,
    start: start,
    how: how,
    device: device,
  );

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode,
        'start': start.toUtc().toIso8601String(),
        if (end != null) 'end': end!.toUtc().toIso8601String(),
        if (how != 'schedule') 'how': how,
        if (peeks > 0) 'peeks': peeks,
    if (device != null) 'dev': device,
      };

  static ModeLog? tryParse(Object? v) {
    if (v is! Map) return null;
    final start = DateTime.tryParse(v['start'] as String? ?? '');
    final id = v['id'] as String?, mode = v['mode'] as String?;
    if (start == null || id == null || mode == null) return null;
    return ModeLog(
      id: id,
      mode: mode,
      start: start.toLocal(),
      end: DateTime.tryParse(v['end'] as String? ?? '')?.toLocal(),
      how: v['how'] as String? ?? 'schedule',
      peeks: (v['peeks'] as num?)?.toInt() ?? 0,
      device: v['dev'] as String?,
    );
  }
}

/// Logs from both sides by id; a closed copy beats an open one, and more peeks win. Older than a
/// year are dropped.
List<ModeLog> mergeModeLogs(List<ModeLog> a, List<ModeLog> b) {
  final byId = <String, ModeLog>{for (final l in a) l.id: l};
  for (final l in b) {
    final mine = byId[l.id];
    if (mine == null) {
      byId[l.id] = l;
    } else {
      if (mine.end == null || (l.end != null && l.end!.isAfter(mine.end!))) mine.end = l.end ?? mine.end;
      mine.peeks = max(mine.peeks, l.peeks);
    }
  }
  final cutoff = DateTime.now().subtract(const Duration(days: 366));
  return byId.values.where((l) => (l.end ?? DateTime.now()).isAfter(cutoff)).toList()
    ..sort((x, y) => x.start.compareTo(y.start));
}

/// A mode chosen by hand: until [until] (null = until changed again).
class ModeChoice {
  ModeChoice(this.mode, this.until, {DateTime? at}) : at = at ?? DateTime.now();

  final String mode;
  final DateTime? until;

  /// When it was chosen; the newer of this device's and the synced choice wins.
  final DateTime at;

  bool activeAt(DateTime now) => until == null || until!.isAfter(now);

  Map<String, dynamic> toJson() => {
        'mode': mode,
        if (until != null) 'until': until!.toUtc().toIso8601String(),
        'at': at.toUtc().toIso8601String(),
      };

  static ModeChoice? tryParse(Object? v) {
    if (v is! Map || v['mode'] is! String) return null;
    return ModeChoice(v['mode'] as String, DateTime.tryParse(v['until'] as String? ?? '')?.toLocal(),
        at: DateTime.tryParse(v['at'] as String? ?? '')?.toLocal() ?? DateTime(2000));
  }
}

/// The schedule's mode at [t] (Everything when nothing is painted there).
String scheduledAt(List<ModeSlot> slots, DateTime t) {
  final m = t.hour * 60 + t.minute;
  for (final s in slots) {
    if (s.day == t.weekday && s.start <= m && m < s.end) return s.mode;
  }
  return everythingId;
}

/// When the schedule next changes mode after [t], looking up to 8 days ahead; null if never.
DateTime? nextScheduleChange(List<ModeSlot> slots, DateTime t) {
  if (slots.isEmpty) return null;
  final now = scheduledAt(slots, t);
  final day0 = DateTime(t.year, t.month, t.day);
  final edges = <DateTime>[];
  for (var d = 0; d <= 8; d++) {
    final day = DateTime(day0.year, day0.month, day0.day + d);
    for (final s in slots.where((s) => s.day == day.weekday)) {
      for (final m in [s.start, s.end]) {
        final at = DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
        if (at.isAfter(t)) edges.add(at);
      }
    }
  }
  edges.sort();
  for (final e in edges) {
    if (scheduledAt(slots, e) != now) return e;
  }
  return null;
}

/// The stretches from [from] to [to], each in the schedule's mode.
List<(String, DateTime, DateTime)> scheduleSegments(List<ModeSlot> slots, DateTime from, DateTime to) {
  final out = <(String, DateTime, DateTime)>[];
  var at = from;
  // Bounded: a schedule changes at most a few hundred times in a year.
  for (var i = 0; i < 5000 && at.isBefore(to); i++) {
    final mode = scheduledAt(slots, at);
    var next = nextScheduleChange(slots, at);
    if (next == null || next.isAfter(to)) next = to;
    out.add((mode, at, next));
    at = next;
  }
  return out;
}

/// Puts [mode] on [day] from [start] to [end] (minutes), cutting into what was there.
/// [mode] = [everythingId] clears that stretch.
List<ModeSlot> paintSchedule(List<ModeSlot> slots, int day, int start, int end, String mode) {
  final out = <ModeSlot>[];
  for (final s in slots) {
    if (s.day != day || s.end <= start || s.start >= end) {
      out.add(s);
      continue;
    }
    if (s.start < start) out.add(ModeSlot(day: day, start: s.start, end: start, mode: s.mode));
    if (s.end > end) out.add(ModeSlot(day: day, start: end, end: s.end, mode: s.mode));
  }
  if (mode != everythingId && end > start) out.add(ModeSlot(day: day, start: start, end: end, mode: mode));
  // Join neighbours in the same mode.
  out.sort((a, b) => a.day != b.day ? a.day.compareTo(b.day) : a.start.compareTo(b.start));
  final joined = <ModeSlot>[];
  for (final s in out) {
    final last = joined.lastOrNull;
    if (last != null && last.day == s.day && last.mode == s.mode && last.end == s.start) {
      joined[joined.length - 1] = ModeSlot(day: s.day, start: last.start, end: s.end, mode: s.mode);
    } else {
      joined.add(s);
    }
  }
  return joined;
}

/// The mode in force and why, worked out by [AppStore]; read by the screens and filters.
/// One per app (the screens and the plain functions such as the Day plan's layout all ask it).
/// Item 108: the focus timer's lengths now: the mode in force's own, else the ones for every
/// mode. Do not disturb always comes from the shared settings.
FocusSettings focusLengthsNow(AppData data) {
  final own = modeNow.mode?.timer;
  if (own == null) return data.focusSettings;
  return FocusSettings(
      focus: own.focus, shortBreak: own.shortBreak, longBreak: own.longBreak, every: own.every, dnd: data.focusSettings.dnd);
}

class ModeNow {
  /// Null = Everything.
  FocusMode? mode;

  /// "Peek": everything shows for a moment without changing mode.
  bool peek = false;

  /// When the mode changes next on its own (schedule or the end of a hand choice).
  DateTime? until;

  /// Whether the mode was chosen by hand.
  bool byHand = false;

  /// Why it came on by itself, when a place or calendar event did it ("At Office", "Flight to
  /// Rome"); null otherwise.
  String? reason;

  /// Until when the mode in force can be counted on for reminders set ahead: [until], or for a
  /// place, the next change on the schedule. Null = for as long as can be told.
  DateTime? reach;

  /// The mode in force at noon on each past day (by [dayKey]), from the mode log, for pausing
  /// habits on days their category was hidden.
  Map<String, FocusMode> noonModes = {};

  /// The app's data, for the habit pause check (which only gets a task).
  AppData? data;

  bool get filtering => mode != null && !peek;

  /// How [t]'s category shows now (always shown for a task set to Always show).
  CatShow showOf(AppData data, Task t) =>
      filtering && !t.alwaysShow ? mode!.showFor(data, t.categoryId) : CatShow.show;

  /// Whether category [id] is hidden in the mode (not Quiet).
  bool hidesCategory(AppData data, String? id) => filtering && mode!.showFor(data, id) == CatShow.hide;

  /// Whether a tool is on now (always in Everything, and while peeking).
  bool toolOn(ModeTool t) => mode == null || peek || mode!.toolOn(t);

  /// Why a task the mode hides still shows ("Overdue", "Due today"...); null when it doesn't.
  String? breakThrough(AppData data, Task t, DateTime now) {
    final m = mode;
    if (m == null) return null;
    if (t.alwaysShow) return 'Always shows';
    final due = t.dueAt;
    if (m.overdue && due != null && due.isBefore(now)) return 'Overdue';
    final limit = m.due.limit(now);
    if (limit != null && due != null && due.isBefore(limit)) {
      final today = DateTime(now.year, now.month, now.day + 1);
      return due.isBefore(today) ? 'Due today' : 'Due soon';
    }
    if (m.starred && t.starred) return 'Starred';
    if (m.planned &&
        t.slots.any((s) => s.doneAt == null && s.start.year == now.year && s.start.month == now.month && s.start.day == now.day)) {
      return 'Planned today';
    }
    if (m.red &&
        (ageProgress(t, data.hoursToRed, byDue: data.colourByDue, now: now) >= 1 ||
            taskPace(t, now).verdict == Pace.behind)) {
      return 'Gone red';
    }
    return null;
  }

  /// Whether [t] shows anywhere (lists, board, charts): its category isn't hidden, or it breaks
  /// through.
  bool shows(AppData data, Task t, DateTime now) =>
      !filtering || mode!.showFor(data, t.categoryId) != CatShow.hide || breakThrough(data, t, now) != null;
}

/// The app's one [ModeNow].
final modeNow = ModeNow();

/// Review fix: this device's key in the mode log (set by the store when it loads; null = count
/// every device's log, as in tests).
String? modeDevice;

/// Whether [l] is this device's (or from before logs said which device).
bool modeLogMine(ModeLog l, [String? device]) {
  final d = device ?? modeDevice;
  return d == null || l.device == null || l.device == d;
}

/// The mode at noon on each day the [logs] cover (the last device's log wins where they overlap).
Map<String, FocusMode> noonModesFrom(AppData data, DateTime now) {
  final out = <String, FocusMode>{};
  final logs = [...data.modeLog.where(modeLogMine)]..sort((a, b) => a.start.compareTo(b.start));
  for (final l in logs) {
    final end = l.end ?? now;
    final m = data.mode(l.mode);
    var day = DateTime(l.start.year, l.start.month, l.start.day);
    for (var i = 0; i < 400 && day.isBefore(end); i++) {
      final noon = DateTime(day.year, day.month, day.day, 12);
      if (!noon.isBefore(l.start) && noon.isBefore(end)) {
        final k = dayKey(day);
        if (m == null) {
          out.remove(k);
        } else {
          out[k] = m;
        }
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }
  return out;
}

/// Whether habit [t] is paused on [day] (key yyyy-mm-dd) because the mode then hid its category:
/// today by the mode in force, earlier days by the mode at noon.
bool habitModePaused(Task t, String day, String today) {
  if (t.alwaysShow) return false;
  final data = modeNow.data;
  if (data == null) return false;
  final m = day == today ? modeNow.mode : modeNow.noonModes[day];
  return m != null && m.pauseHabits && m.showFor(data, t.categoryId) == CatShow.hide;
}

/// The mode that will be in force at [t], as far as can be told at [now]: the current one until
/// [ModeNow.reach], then the weekly schedule.
FocusMode? forecastMode(AppData data, DateTime t, DateTime now) {
  final reach = modeNow.reach;
  if (!t.isAfter(now) || reach == null || t.isBefore(reach)) return modeNow.mode;
  return data.mode(scheduledAt(data.modeSchedule, t));
}

/// When the forecast mode at [t] ends: [ModeNow.reach] for the current one, else the next change
/// on the schedule. Null when it can't be told.
DateTime? forecastEnd(AppData data, DateTime t, DateTime now) {
  final reach = modeNow.reach;
  if (!t.isAfter(now) || reach == null || t.isBefore(reach)) return reach;
  return nextScheduleChange(data.modeSchedule, t);
}

/// Whether a reminder for [t] at [when] is held back: the mode then hides its category and it
/// doesn't break through. Returns that mode, or null when the reminder goes off as usual.
FocusMode? heldBy(AppData data, Task t, DateTime when, DateTime now) {
  final m = forecastMode(data, when, now);
  if (m == null || m.showFor(data, t.categoryId) != CatShow.hide) return null;
  final probe = ModeNow()..mode = m;
  return probe.breakThrough(data, t, when) == null ? m : null;
}

/// A mode that comes on by itself: which, why ("At Office"), until when (null = until it no
/// longer applies) and a key that tells one occasion from another (for "Ask before switching").
typedef AutoMode = ({String mode, String reason, DateTime? until, String key});

/// Whether an event title has one of [words] in it, as a whole word ("WFH", "work from home").
bool eventMatches(String title, List<String> words) {
  for (final w in words) {
    final t = w.trim();
    if (t.isEmpty) continue;
    if (RegExp('(^|[^a-z0-9])${RegExp.escape(t.toLowerCase())}(\$|[^a-z0-9])').hasMatch(title.toLowerCase())) return true;
  }
  return false;
}

/// The mode a calendar event or place calls for at [now]; events come before places, and modes
/// higher in the list first. [events] are (id, title, start, end) of events happening now.
AutoMode? autoModeAt(AppData data, DateTime now,
    {String? place, List<(String, String, DateTime, DateTime)> events = const []}) {
  for (final m in data.modes) {
    if (m.events.isEmpty) continue;
    for (final (id, title, start, end) in events) {
      if (start.isAfter(now) || !end.isAfter(now) || !eventMatches(title, m.events)) continue;
      return (mode: m.id, reason: title, until: end, key: 'event:$id:${m.id}');
    }
  }
  if (place == null) return null;
  final scheduled = scheduledAt(data.modeSchedule, now);
  for (final m in data.modes) {
    if (!m.places.any((p) => p.toLowerCase() == place.toLowerCase())) continue;
    if (m.placeWhen != null && m.placeWhen != scheduled) continue;
    // A place that only counts while the schedule says some mode lasts until the schedule moves on.
    final until = m.placeWhen == null ? null : nextScheduleChange(data.modeSchedule, now);
    return (mode: m.id, reason: 'At $place', until: until, key: 'place:$place:${m.id}:$scheduled');
  }
  return null;
}

/// Starter modes made from the categories' names: Work, Home office, Weekend, Travel. Every
/// category is guessed as work, home or travel by its name; the rest show quietly.
List<FocusMode> starterModes(AppData data, {List<String> places = const []}) {
  String? place(RegExp r) => places.where(r.hasMatch).firstOrNull;
  final office = place(RegExp(r'office|work', caseSensitive: false));
  final homePlace = place(RegExp(r'home|house', caseSensitive: false));
  final work = RegExp(r'work|job|office|admin|client|business|project|meeting', caseSensitive: false);
  final travel = RegExp(r'travel|trip|holiday|flight|vacation|pack', caseSensitive: false);
  final home = RegExp(r'home|house|chore|garden|car|family|kids|shop|clean|diy|personal|health', caseSensitive: false);
  String kind(TaskCategory c) => work.hasMatch(c.name)
      ? 'work'
      : travel.hasMatch(c.name)
          ? 'travel'
          : home.hasMatch(c.name)
              ? 'home'
              : 'other';
  Map<String, CatShow> cats(Map<String, CatShow> byKind) =>
      {for (final c in data.categories) c.id: byKind[kind(c)]!, '': byKind['other']!};
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return [
    FocusMode(
      id: 'm$stamp-work',
      name: 'Work',
      colour: 0xFF3F6FB5,
      icon: 'work',
      cats: cats({'work': CatShow.show, 'home': CatShow.hide, 'travel': CatShow.hide, 'other': CatShow.quiet}),
      toolsOff: {ModeTool.habits.name, ModeTool.achievements.name, ModeTool.stats.name},
      newCategory: data.categories.where((c) => kind(c) == 'work').firstOrNull?.id,
      places: [?office],
    ),
    FocusMode(
      id: 'm$stamp-homeoffice',
      name: 'Home office',
      colour: 0xFF2E8B57,
      icon: 'laptop',
      cats: cats({'work': CatShow.show, 'home': CatShow.quiet, 'travel': CatShow.hide, 'other': CatShow.quiet}),
      toolsOff: {ModeTool.achievements.name, ModeTool.stats.name},
      newCategory: data.categories.where((c) => kind(c) == 'work').firstOrNull?.id,
      places: [?homePlace],
      placeWhen: homePlace == null ? null : 'm$stamp-work',
      events: ['WFH', 'work from home', 'working from home'],
    ),
    FocusMode(
      id: 'm$stamp-weekend',
      name: 'Weekend',
      colour: 0xFF8A5BB5,
      icon: 'home',
      cats: cats({'work': CatShow.hide, 'home': CatShow.show, 'travel': CatShow.quiet, 'other': CatShow.show}),
      toolsOff: {ModeTool.gantt.name, ModeTool.board.name, ModeTool.dayPlan.name},
      due: DueWithin.off,
      newCategory: data.categories.where((c) => kind(c) == 'home').firstOrNull?.id,
    ),
    FocusMode(
      id: 'm$stamp-travel',
      name: 'Travel',
      colour: 0xFFD2793A,
      icon: 'travel',
      cats: cats({'work': CatShow.hide, 'home': CatShow.hide, 'travel': CatShow.show, 'other': CatShow.quiet}),
      toolsOff: {ModeTool.gantt.name, ModeTool.board.name, ModeTool.matrix.name, ModeTool.stats.name, ModeTool.achievements.name},
      newCategory: data.categories.where((c) => kind(c) == 'travel').firstOrNull?.id,
      events: ['flight', 'trip', 'holiday', 'vacation', 'travel'],
    ),
  ];
}

/// The starting schedule offered with the starter modes: Work weekdays in the Day plan's working
/// hours, Weekend from Friday evening to Sunday evening.
List<ModeSlot> starterSchedule(AppData data, List<FocusMode> modes) {
  final work = modes.where((m) => m.name == 'Work').firstOrNull?.id;
  final weekend = modes.where((m) => m.name == 'Weekend').firstOrNull?.id;
  final s = data.dayPlan.workStart, e = data.dayPlan.workEnd;
  return [
    if (work != null)
      for (var d = DateTime.monday; d <= DateTime.friday; d++) ModeSlot(day: d, start: s, end: e, mode: work),
    if (weekend != null) ...[
      ModeSlot(day: DateTime.friday, start: 18 * 60, end: 24 * 60, mode: weekend),
      ModeSlot(day: DateTime.saturday, start: 0, end: 24 * 60, mode: weekend),
      ModeSlot(day: DateTime.sunday, start: 0, end: 20 * 60, mode: weekend),
    ],
  ];
}

/// Minutes in each mode between [from] and [to], from [logs] (stretches from several devices
/// that overlap count once per mode).
Map<String, int> minutesPerMode(List<ModeLog> logs, DateTime from, DateTime to, {DateTime? now}) {
  final end0 = now ?? DateTime.now();
  final spans = <String, List<(DateTime, DateTime)>>{};
  for (final l in logs) {
    var s = l.start, e = l.end ?? end0;
    if (s.isBefore(from)) s = from;
    if (e.isAfter(to)) e = to;
    if (!e.isAfter(s)) continue;
    (spans[l.mode] ??= []).add((s, e));
  }
  final out = <String, int>{};
  spans.forEach((mode, list) {
    list.sort((a, b) => a.$1.compareTo(b.$1));
    var total = 0;
    var (cs, ce) = list.first;
    for (final (s, e) in list.skip(1)) {
      if (s.isAfter(ce)) {
        total += ce.difference(cs).inMinutes;
        (cs, ce) = (s, e);
      } else if (e.isAfter(ce)) {
        ce = e;
      }
    }
    out[mode] = total + ce.difference(cs).inMinutes;
  });
  return out;
}

/// Facts about the modes for the statistics page, over the last [days] days.
class ModeStats {
  ModeStats({required this.minutes, required this.done, required this.outside, required this.byHand, required this.switches, required this.peeks});

  /// Minutes in each mode (by id, [everythingId] too).
  final Map<String, int> minutes;

  /// Tasks ticked off in each mode.
  final Map<String, int> done;

  /// Tasks ticked off from a category the mode hid (they broke through).
  final int outside;

  /// Times a mode was picked by hand, and every change of mode.
  final int byHand;
  final int switches;
  final int peeks;

  int get totalMinutes => minutes.values.fold(0, (a, b) => a + b);

  /// Tasks done per hour in [mode]; null with under an hour in it.
  double? perHour(String mode) {
    final m = minutes[mode] ?? 0;
    return m < 60 ? null : (done[mode] ?? 0) / (m / 60);
  }
}

/// Mode facts since [since] (null = as far back as the log goes, a year at most).
ModeStats modeStats(AppData data, DateTime now, {DateTime? since}) {
  final from = since ?? now.subtract(const Duration(days: 366));
  // Review fix: this device's stretches only, so two devices' time isn't counted twice.
  final logs = data.modeLog.where((l) => modeLogMine(l) && (l.end ?? now).isAfter(from)).toList();
  final done = <String, int>{};
  var outside = 0;
  for (final r in data.done.values) {
    if (r.at.isBefore(from)) continue;
    final m = r.mode;
    if (m == null) continue;
    done[m] = (done[m] ?? 0) + 1;
    if (r.outside) outside++;
  }
  return ModeStats(
    minutes: minutesPerMode(logs, from, now, now: now),
    done: done,
    outside: outside,
    byHand: logs.where((l) => l.how == 'hand' && !l.start.isBefore(from)).length,
    switches: logs.where((l) => !l.start.isBefore(from)).length,
    peeks: logs.fold(0, (a, l) => a + l.peeks),
  );
}
