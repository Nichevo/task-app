import 'package:intl/intl.dart';

import 'gantt.dart';
import 'models.dart';
import 'native.dart' show CalendarEvent;
import 'places.dart';

/// Item 101: the Day plan. Everything here is plain logic (what goes where on one day), so it can
/// be tested without a screen; lib/screens/day_plan_page.dart draws it.

/// Something with a time on the timeline: a planned block or a phone calendar event. Both take
/// part in clashes and fill up the day.
abstract class Placed {
  DateTime get start;
  DateTime get end;

  /// Overlaps another ordinary block or event (not one that leaves room).
  bool clash = false;

  /// Side by side with what it clashes with: its column and how many there are.
  int column = 0;
  int columns = 1;

  /// Sits on top of a block that leaves room (drawn to the right of its band).
  bool inBand = false;

  bool overlaps(Placed o) => start.isBefore(o.end) && o.start.isBefore(end);
}

/// A timed event from the phone's calendar: read-only, drawn grey.
class EventBlock extends Placed {
  EventBlock(this.event);
  final CalendarEvent event;
  @override
  DateTime get start => event.start;
  @override
  DateTime get end => event.end.isAfter(event.start) ? event.end : event.start.add(const Duration(minutes: 15));
  int get minutes => end.difference(start).inMinutes;
}

/// One planned time on the day: a task's or a step's [slot].
class PlanBlock extends Placed {
  PlanBlock(this.task, this.slot, {this.step});

  final Task task;
  final TaskStep? step;
  final TimeSlot slot;

  @override
  DateTime get start => slot.start;
  @override
  DateTime get end => slot.end;
  bool get shared => slot.shared;

  /// Ticked here, or the step or task itself is done.
  bool get done => slot.doneAt != null || (step?.done ?? task.closedAt != null);

  String get title => step?.title ?? task.title;

  // Filled in by [layoutDay].

  /// Its category is hidden: drawn as a faint strip (or not at all).
  bool hidden = false;

  /// Planned to start before something it comes after is finished.
  bool tooEarly = false;

  /// Its task's block, when this is a step planned inside its task's time.
  PlanBlock? frame;

  /// Steps planned inside this task's time, drawn inside its block.
  final List<PlanBlock> inside = [];
}

/// A "comes after" link between two blocks on the day: [to] waits for [from].
class PlanLink {
  const PlanLink(this.from, this.to);
  final PlanBlock from, to;

  /// [to] starts before [from] ends.
  bool get tooEarly => to.start.isBefore(from.end) && !from.done;
}

/// A stretch of time on the day: a gap after a block, or free time.
class Span {
  const Span(this.start, this.end);
  final DateTime start;
  final DateTime end;
  int get minutes => end.difference(start).inMinutes;
}

/// 1.12.5: driving before or after a planned block whose task has a location.
class DriveSpan extends Span {
  const DriveSpan(super.start, super.end, this.block, {required this.before, this.from, this.estimate = false});
  final PlanBlock block;

  /// Driving there (true) or on afterwards.
  final bool before;

  /// Where the estimate starts or ends ("Home", the previous task's place).
  final String? from;

  /// Worked out from the distance, rather than set on the task.
  final bool estimate;
}

/// Minutes of driving before (or [after]) [b], with where from and whether it is an estimate:
/// the task's own setting, else (when it has a pin) the distance from the previous pinned block
/// that day, or from Home. After a block the estimate is only the drive home, after the last
/// pinned block of the day; the next block's own "before" covers the trip between them.
({int minutes, String? from, bool estimate})? driveFor(Task t, Placed b, List<PlanBlock> day,
    {required bool after, List<Place>? places, bool suggest = false}) {
  final set = suggest ? null : (after ? t.driveAfter : t.driveBefore);
  if (set != null) return set > 0 ? (minutes: set, from: null, estimate: false) : null;
  final w = t.where;
  if (w == null || !w.pinned) return null;
  final pinned = day.where((o) => !identical(o, b) && !o.shared && o.task.where?.pinned == true);
  double? lat, lng;
  String? name;
  if (!after) {
    final prev = pinned.where((o) => !o.end.isAfter(b.start)).fold<PlanBlock?>(null, (a, o) => a == null || o.end.isAfter(a.end) ? o : a);
    if (prev != null) {
      lat = prev.task.where!.lat;
      lng = prev.task.where!.lng;
      name = prev.task.where!.name;
    }
  } else if (pinned.any((o) => !o.start.isBefore(b.end))) {
    return null;
  }
  if (lat == null) {
    final home = homePlace(places);
    if (home == null) return null;
    lat = home.lat;
    lng = home.lng;
    name = home.name;
  }
  final m = metresBetween(lat, lng!, w.lat!, w.lng!);
  if (m < 300) return null;
  return (minutes: estimateDriveMinutes(m), from: name, estimate: true);
}

/// Everything on one day, laid out.
class DayLayout {
  DayLayout(this.day, this.blocks, this.gaps, this.free,
      {required this.workStart,
      required this.workEnd,
      this.events = const [],
      this.allDay = const [],
      this.links = const [],
      this.drives = const []});

  /// 1.12.5: driving before and after blocks whose task has a location.
  final List<DriveSpan> drives;

  final DateTime day;

  /// Blocks drawn on the timeline (steps inside a task's block are in its [PlanBlock.inside]).
  final List<PlanBlock> blocks;

  /// The gaps kept after blocks.
  final List<Span> gaps;

  /// Free time inside working hours.
  final List<Span> free;

  final DateTime workStart, workEnd;

  /// The phone's timed events that day (empty when they are turned off).
  final List<EventBlock> events;

  /// The phone's all-day events that day, shown as chips above the timeline.
  final List<CalendarEvent> allDay;

  /// "Comes after" links between blocks shown that day.
  final List<PlanLink> links;

  int get eventMinutes => _union([for (final e in events) Span(e.start, e.end)]);

  int get tooEarly => all.where((b) => b.tooEarly).length;

  Iterable<PlanBlock> get all sync* {
    for (final b in blocks) {
      yield b;
      yield* b.inside;
    }
  }

  /// Minutes planned (overlaps counted once), hidden blocks included.
  int get plannedMinutes => _union([for (final b in blocks) Span(b.start, b.end)]);

  int get freeMinutes => free.fold(0, (a, s) => a + s.minutes);

  /// Time inside blocks that leave room, used by other blocks.
  int get sharedMinutes {
    var total = 0;
    for (final band in blocks.where((b) => b.shared)) {
      total += _union([
        for (final b in blocks)
          if (!identical(b, band) && b.overlaps(band))
            Span(b.start.isBefore(band.start) ? band.start : b.start, b.end.isAfter(band.end) ? band.end : b.end),
      ]);
    }
    return total;
  }

  int get clashes => blocks.where((b) => b.clash).length + events.where((e) => e.clash).length;

  int get hiddenMinutes => _union([for (final b in blocks.where((b) => b.hidden)) Span(b.start, b.end)]);

  /// The first free stretch of at least [minutes] from [from] (the start of working hours when
  /// null), or null.
  DateTime? firstFree(int minutes, {DateTime? from}) {
    for (final f in free) {
      final s = from != null && from.isAfter(f.start) ? from : f.start;
      if (f.end.difference(s).inMinutes >= minutes) return s;
    }
    return null;
  }
}

DateTime _at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));

/// Minutes covered by [spans], overlaps counted once.
int _union(List<Span> spans) {
  if (spans.isEmpty) return 0;
  spans.sort((a, b) => a.start.compareTo(b.start));
  var total = 0;
  var s = spans.first.start, e = spans.first.end;
  for (final x in spans.skip(1)) {
    if (x.start.isAfter(e)) {
      total += e.difference(s).inMinutes;
      s = x.start;
      e = x.end;
    } else if (x.end.isAfter(e)) {
      e = x.end;
    }
  }
  return total + e.difference(s).inMinutes;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Whether category [id] (null = none) is hidden on the Day plan.
bool categoryHidden(AppData data, String? id) {
  final known = id != null && data.category(id) != null;
  return data.dayPlan.hiddenCategories.contains(known ? id : '');
}

/// The planned times on [day] of open tasks, and of tasks ticked off since, as blocks.
List<PlanBlock> blocksOn(AppData data, DateTime day) {
  final out = <PlanBlock>[];
  for (final t in [...data.active, ...data.archived.where((t) => t.slots.isNotEmpty)]) {
    if (t.habit) continue;
    for (final sl in t.slots) {
      if (!_sameDay(sl.start, day)) continue;
      if (sl.stepId == null) {
        out.add(PlanBlock(t, sl));
      } else if (t.steps.where((s) => s.id == sl.stepId).firstOrNull case final st?) {
        out.add(PlanBlock(t, sl, step: st));
      }
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Lays out [day]: steps inside their task's block, bands that leave room, clashes side by side,
/// the gaps after blocks and the free time left in working hours.
///
/// [events] are the phone's calendar events (any days; only [day]'s are used, and none when
/// they are turned off).
DayLayout layoutDay(AppData data, DateTime day, {List<CalendarEvent> events = const []}) {
  final s = data.dayPlan;
  final (timed, allDay) = eventsOn(data, day, events);
  var blocks = blocksOn(data, day);
  for (final b in blocks) {
    b.hidden = categoryHidden(data, b.task.categoryId) || !data.inMode(b.task);
  }
  if (!s.hiddenStrip) blocks = blocks.where((b) => !b.hidden).toList();
  if (!s.showTicked) blocks = blocks.where((b) => !b.done).toList();

  // Steps inside their task's own planned time become part of its block.
  final top = <PlanBlock>[];
  for (final b in blocks) {
    if (b.step != null) {
      final frame = blocks
          .where((f) =>
              f.step == null &&
              identical(f.task, b.task) &&
              !f.start.isAfter(b.start) &&
              !f.end.isBefore(b.end))
          .firstOrNull;
      if (frame != null) {
        b.frame = frame;
        frame.inside.add(b);
        continue;
      }
    }
    top.add(b);
  }
  // Tasks only: a task's steps fold into it (only its own blocks show). Steps only: a task block
  // with steps planned inside stays as their frame, an empty one goes.
  final shown = switch (s.show) {
    DayShow.both => top,
    DayShow.tasks => top.where((b) => b.step == null).toList(),
    DayShow.steps => top.where((b) => b.step != null || b.inside.isNotEmpty).toList(),
  };

  // Ordinary blocks over a band that leaves room sit on top of it and aren't clashes.
  final bands = shown.where((b) => b.shared && !b.hidden).toList();
  final plain = <Placed>[...shown.where((b) => !b.shared && !b.hidden), ...timed]
    ..sort((a, b) => a.start.compareTo(b.start));
  for (final b in plain) {
    b.inBand = bands.any(b.overlaps);
  }
  // Clashes: ordinary blocks and events that overlap, put side by side in columns, cluster by
  // cluster.
  var cluster = <Placed>[];
  DateTime? clusterEnd;
  void close() {
    final cols = <DateTime>[];
    for (final b in cluster) {
      var c = cols.indexWhere((end) => !end.isAfter(b.start));
      if (c < 0) {
        c = cols.length;
        cols.add(b.end);
      } else {
        cols[c] = b.end;
      }
      b.column = c;
    }
    // Side by side means sharing one left edge: if one of them sits on a band, all do.
    final onBand = cluster.any((b) => b.inBand);
    for (final b in cluster) {
      b.columns = cols.length;
      b.clash = cols.length > 1;
      b.inBand = onBand;
    }
    cluster = [];
    clusterEnd = null;
  }

  for (final b in plain) {
    if (clusterEnd != null && !b.start.isBefore(clusterEnd!)) close();
    cluster.add(b);
    if (clusterEnd == null || b.end.isAfter(clusterEnd!)) clusterEnd = b.end;
  }
  close();

  // 1.12.5: driving there and back, which takes time too.
  final drives = <DriveSpan>[];
  final road = shown.where((b) => !b.shared && !b.hidden && !b.done).toList();
  for (final b in road) {
    final t = b.task;
    if (t.where == null && t.driveBefore == null && t.driveAfter == null) continue;
    if (driveFor(t, b, road, after: false) case final d?) {
      drives.add(DriveSpan(b.start.subtract(Duration(minutes: d.minutes)), b.start, b,
          before: true, from: d.from, estimate: d.estimate));
    }
    if (driveFor(t, b, road, after: true) case final d?) {
      drives.add(DriveSpan(b.end, b.end.add(Duration(minutes: d.minutes)), b,
          before: false, from: d.from, estimate: d.estimate));
    }
  }

  // Gaps after each ordinary block, cut short by whatever comes next.
  final gaps = <Span>[];
  final busy = <Span>[for (final e in timed) Span(e.start, e.end), ...drives];
  final solid = <Placed>[...shown.where((b) => !b.shared), ...timed];
  for (final b in shown.where((b) => !b.shared)) {
    busy.add(Span(b.start, b.end));
    final g = b.slot.gapAfter ?? s.gapMinutes;
    if (g <= 0) continue;
    var gEnd = b.end.add(Duration(minutes: g));
    for (final o in solid) {
      if (o.start.isAfter(b.start) && !o.start.isBefore(b.end) && o.start.isBefore(gEnd)) gEnd = o.start;
    }
    if (gEnd.isAfter(b.end)) {
      gaps.add(Span(b.end, gEnd));
      busy.add(Span(b.end, gEnd));
    }
  }

  // Free time: working hours less the blocks (not bands) and their gaps.
  final ws = _at(day, s.workStart), we = _at(day, s.workEnd);
  busy.sort((a, b) => a.start.compareTo(b.start));
  final free = <Span>[];
  var cursor = ws;
  for (final x in busy) {
    if (!x.end.isAfter(cursor)) continue;
    if (x.start.isAfter(cursor)) {
      final end = x.start.isAfter(we) ? we : x.start;
      if (end.difference(cursor).inMinutes >= 5) free.add(Span(cursor, end));
    }
    if (x.end.isAfter(cursor)) cursor = x.end;
    if (!cursor.isBefore(we)) break;
  }
  if (we.difference(cursor).inMinutes >= 5) free.add(Span(cursor, we));

  return DayLayout(day, shown, gaps, free,
      workStart: ws, workEnd: we, events: timed, allDay: allDay, links: _links(data, shown), drives: drives);
}

/// [day]'s events from [events]: the timed ones as blocks, and the all-day ones. None when
/// Settings turn events off.
(List<EventBlock>, List<CalendarEvent>) eventsOn(AppData data, DateTime day, List<CalendarEvent> events) {
  if (!data.dayPlan.showEvents) return (const [], const []);
  final d0 = DateTime(day.year, day.month, day.day), d1 = d0.add(const Duration(days: 1));
  final timed = <EventBlock>[], allDay = <CalendarEvent>[];
  for (final e in events) {
    if (e.allDay) {
      // All-day events end at midnight after their last day.
      final end = e.end.isAfter(e.start) ? e.end : e.start.add(const Duration(days: 1));
      if (e.start.isBefore(d1) && end.isAfter(d0)) allDay.add(e);
    } else if (_sameDay(e.start, day)) {
      timed.add(EventBlock(e));
    }
  }
  timed.sort((a, b) => a.start.compareTo(b.start));
  return (timed, allDay);
}

/// Links between blocks shown: a task's first block after the last block of each task it comes
/// after, and a step's block after the blocks of the steps it comes after. Marks blocks planned
/// before what they wait for is finished (on any day) as [PlanBlock.tooEarly].
List<PlanLink> _links(AppData data, List<PlanBlock> shown) {
  final all = [for (final b in shown) ...[b, ...b.inside]];
  final links = <PlanLink>[];
  for (final b in all) {
    if (b.done) continue;
    if (b.step == null) {
      final preds = b.task.afterIds;
      if (preds.isEmpty) continue;
      // Only the task's first block that day gets the line.
      if (all.any((o) => o.step == null && identical(o.task, b.task) && o.start.isBefore(b.start))) continue;
      for (final id in preds) {
        final from = all.where((a) => a.task.id == id).fold<PlanBlock?>(null, (m, a) => m == null || a.end.isAfter(m.end) ? a : m);
        if (from != null) links.add(PlanLink(from, b));
        final pt = data.task(id);
        if (pt != null && pt.closedAt == null && pt.slots.any((x) => x.doneAt == null && x.end.isAfter(b.start))) {
          b.tooEarly = true;
        }
      }
    } else {
      for (final id in b.step!.afterIds) {
        for (final a in all.where((a) => identical(a.task, b.task) && a.step?.id == id)) {
          links.add(PlanLink(a, b));
        }
        final ps = b.task.steps.where((x) => x.id == id).firstOrNull;
        if (ps != null && !ps.done && b.task.slotsOf(ps).any((x) => x.doneAt == null && x.end.isAfter(b.start))) {
          b.tooEarly = true;
        }
      }
    }
  }
  return links;
}

/// What is planned inside [band] (a block that leaves room) on its day: open blocks starting
/// within its time, moved by [shift] when the band moves.
List<PlanMove> insideBand(AppData data, PlanBlock band, Duration shift) => [
      for (final x in blocksOn(data, band.start))
        if (!identical(x.slot, band.slot) &&
            !x.shared &&
            x.slot.doneAt == null &&
            !x.start.isBefore(band.start) &&
            x.start.isBefore(band.end))
          PlanMove(x.task, x.slot, x.start, x.start.add(shift)),
    ];

/// What a time starting at [start] for [task] (or its [step]) would be too early for: each task
/// or step it comes after that still has an open planned time ending after [start], with when
/// that time ends (the latest one). Shown in the Plan a time sheet as you choose.
List<(String, DateTime)> tooEarlyFor(AppData data, Task task, TaskStep? step, DateTime start) {
  DateTime? lastEnd(Iterable<TimeSlot> slots) {
    DateTime? e;
    for (final x in slots) {
      if (x.doneAt == null && x.end.isAfter(start) && (e == null || x.end.isAfter(e))) e = x.end;
    }
    return e;
  }

  final out = <(String, DateTime)>[];
  if (step == null) {
    for (final id in task.afterIds) {
      final p = data.task(id);
      if (p == null || p.closedAt != null) continue;
      if (lastEnd(p.slots) case final e?) out.add((p.title, e));
    }
  } else {
    for (final id in step.afterIds) {
      final p = task.steps.where((x) => x.id == id).firstOrNull;
      if (p == null || p.done) continue;
      if (lastEnd(task.slotsOf(p)) case final e?) out.add((p.title, e));
    }
  }
  return out;
}

/// A planned time to move: what [pushAfter] wants changed.
class PlanMove {
  const PlanMove(this.task, this.slot, this.from, this.to);
  final Task task;
  final TimeSlot slot;
  final DateTime from, to;
}

/// What comes after [b] on its day, moved later so nothing overlaps once [b] runs from
/// [newStart] for [newMinutes]: each block that would now start before the end of the one in
/// front (plus its gap) moves to just after it, in a chain, until a free stretch takes up the
/// slack. Blocks that leave room, ticked blocks and steps inside [b] stay put; steps inside a
/// moved task move with it. Earlier blocks never move.
List<PlanMove> pushAfter(AppData data, PlanBlock b, DateTime newStart, int newMinutes) {
  final s = data.dayPlan;
  final day = b.start;
  final blocks = blocksOn(data, day).where((x) => !x.shared).toList();
  // Steps inside a task's time move with the task, so only outer blocks are pushed.
  final outer = <PlanBlock>[];
  final insideOf = <PlanBlock, List<PlanBlock>>{};
  for (final x in blocks) {
    final frame = x.step == null
        ? null
        : blocks
            .where((f) => f.step == null && identical(f.task, x.task) && !f.start.isAfter(x.start) && !f.end.isBefore(x.end))
            .firstOrNull;
    if (frame != null) {
      (insideOf[frame] ??= []).add(x);
    } else {
      outer.add(x);
    }
  }
  bool isB(PlanBlock x) => identical(x.slot, b.slot);
  final mine = insideOf.entries.where((e) => isB(e.key)).expand((e) => e.value).map((e) => e.slot).toSet();
  // A step stretched inside its task's time pushes only within that task's other steps.
  final frame = insideOf.entries.where((e) => e.value.any(isB)).map((e) => e.key).firstOrNull;
  final pool = frame == null ? outer : insideOf[frame]!;
  final candidates = pool
      .where((x) => !isB(x) && !mine.contains(x.slot) && x.slot.doneAt == null && !x.start.isBefore(b.start))
      .toList()
    ..sort((a, c) => a.start.compareTo(c.start));
  var frontier = newStart.add(Duration(minutes: newMinutes + (b.slot.gapAfter ?? s.gapMinutes)));
  final moves = <PlanMove>[];
  for (final x in candidates) {
    if (!x.start.isBefore(frontier)) break;
    final shift = frontier.difference(x.start);
    moves.add(PlanMove(x.task, x.slot, x.start, frontier));
    for (final st in insideOf[x] ?? const <PlanBlock>[]) {
      moves.add(PlanMove(st.task, st.slot, st.start, st.start.add(shift)));
    }
    frontier = frontier.add(Duration(minutes: x.slot.minutes + (x.slot.gapAfter ?? s.gapMinutes)));
  }
  return moves;
}

/// How full [day] is: planned minutes inside working hours over the working minutes (above 1
/// when over-full). Bands that leave room don't count.
double dayLoad(AppData data, DateTime day, {List<CalendarEvent> events = const []}) {
  final s = data.dayPlan;
  final ws = _at(day, s.workStart), we = _at(day, s.workEnd);
  final work = we.difference(ws).inMinutes;
  if (work <= 0) return 0;
  final spans = <Span>[];
  var outside = 0;
  for (final b in blocksOn(data, day)) {
    if (b.shared || b.hidden) continue;
    final st = b.start.isBefore(ws) ? ws : b.start, en = b.end.isAfter(we) ? we : b.end;
    if (en.isAfter(st)) spans.add(Span(st, en));
    outside += b.end.difference(b.start).inMinutes - (en.isAfter(st) ? en.difference(st).inMinutes : 0);
  }
  for (final e in eventsOn(data, day, events).$1) {
    final st = e.start.isBefore(ws) ? ws : e.start, en = e.end.isAfter(we) ? we : e.end;
    if (en.isAfter(st)) spans.add(Span(st, en));
  }
  // Driving counts too.
  final road = blocksOn(data, day).where((b) => !b.shared && !b.done).toList();
  for (final b in road) {
    for (final after in [false, true]) {
      final d = b.task.where == null && b.task.driveBefore == null && b.task.driveAfter == null
          ? null
          : driveFor(b.task, b, road, after: after);
      if (d == null) continue;
      final from = after ? b.end : b.start.subtract(Duration(minutes: d.minutes));
      final to = from.add(Duration(minutes: d.minutes));
      final st = from.isBefore(ws) ? ws : from, en = to.isAfter(we) ? we : to;
      if (en.isAfter(st)) spans.add(Span(st, en));
    }
  }
  return (_union(spans) + outside) / work;
}

/// Something waiting in the "To plan" tray, with why it's there.
class TrayItem {
  const TrayItem(this.task, this.why, {this.step, this.missed, this.other = false});
  final Task task;

  /// In "Other open tasks": not for this day, but open and not planned yet.
  final bool other;
  final TaskStep? step;
  final String why;

  /// A planned time that went by without being ticked: planning it again moves this one.
  final TimeSlot? missed;
  String get title => step?.title ?? task.title;

  /// Length to plan it for: its estimate, else the default.
  int minutes(AppData data) => missed?.minutes ?? (step == null ? task.estimate ?? data.dayPlan.length : data.dayPlan.length);
}

/// The "To plan" tray for [day]: tasks on the Day plan with no time coming up, plus (as Settings
/// say) tasks and steps due that day, Gantt bars covering it and In progress cards. Hidden
/// categories are left out.
List<TrayItem> trayFor(AppData data, DateTime day, {DateTime? at}) {
  final now = at ?? DateTime.now();
  final s = data.dayPlan;
  final d0 = DateTime(day.year, day.month, day.day);
  final fmt = DateFormat('EEE d MMM');
  final out = <TrayItem>[];
  final dueFirst = <TrayItem>[];
  final others = <TrayItem>[];
  for (final t in data.active) {
    if (t.habit || categoryHidden(data, t.categoryId) || !data.inMode(t)) continue;
    final own = t.ownSlots.toList();
    if (own.any((x) => _sameDay(x.start, day))) {
      // Planned that day; only its due steps without a time can still be waiting.
    } else {
      final upcoming = own.any((x) => x.doneAt == null && !x.start.isBefore(DateTime(now.year, now.month, now.day)));
      final missed = own.where((x) => x.doneAt == null && x.end.isBefore(now)).toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      String? why;
      TimeSlot? missedSlot;
      final due = t.dueAt;
      final bar = s.trayGantt && t.gantt ? barFor(t, data) : null;
      if (s.trayDue && due != null && _sameDay(due, day)) {
        why = due.isBefore(now) ? 'Overdue' : 'Due ${DateFormat('HH:mm').format(due)}';
      } else if (!upcoming && missed.isNotEmpty) {
        why = 'Missed ${fmt.format(missed.first.start)}, ${DateFormat('HH:mm').format(missed.first.start)}';
        missedSlot = missed.first;
      } else if (bar != null && !bar.start.isAfter(d0) && !bar.end.isBefore(d0)) {
        why = bar.start == bar.end ? 'Gantt: this day' : 'Gantt: ${fmt.format(bar.start)} to ${fmt.format(bar.end)}';
      } else if (s.trayInProgress &&
          t.kanban &&
          (t.stageId == 'doing' || data.stage(t.stageId)?.name.trim().toLowerCase() == 'in progress')) {
        why = 'In progress';
      } else if (data.onDayPlan(t) && !upcoming) {
        why = due == null
            ? 'No date'
            : due.isBefore(now)
                ? 'Overdue'
                : 'Due ${fmt.format(due)}';
      }
      if (why != null) {
        (why == 'Overdue' ? dueFirst : out).add(TrayItem(t, why, missed: missedSlot));
      } else if (s.trayAll && !upcoming && !data.isLocked(t)) {
        others.add(TrayItem(
          t,
          due == null
              ? 'No date'
              : due.isBefore(now)
                  ? 'Overdue'
                  : 'Due ${fmt.format(due)}',
          other: true,
        ));
      }
    }
    if (s.trayDue && s.show != DayShow.tasks) {
      for (final st in t.steps) {
        final due = st.dueAt;
        if (st.done || due == null || !_sameDay(due, day) || t.slotsOf(st).any((x) => _sameDay(x.start, day))) continue;
        out.add(TrayItem(t, 'Step due ${DateFormat('HH:mm').format(due)}', step: st));
      }
    }
  }
  // Soonest due first, then starred, then the rest by title.
  final far = DateTime(9999);
  others.sort((a, b) {
    final c = (a.task.dueAt ?? far).compareTo(b.task.dueAt ?? far);
    if (c != 0) return c;
    if (a.task.starred != b.task.starred) return a.task.starred ? -1 : 1;
    return a.task.title.toLowerCase().compareTo(b.task.title.toLowerCase());
  });
  return [...dueFirst, ...out, ...others];
}

/// The open steps of [i]'s task that have no time on [day], to drag onto the Day plan one by one
/// (the tray's "steps" drill-down). Steps already in [shown] are left out.
List<TrayItem> trayStepsOf(AppData data, TrayItem i, DateTime day, {Iterable<TrayItem> shown = const []}) {
  final t = i.task;
  final have = {for (final x in shown) if (x.task.id == t.id && x.step != null) x.step!.id};
  final fmt = DateFormat('EEE d MMM');
  return [
    for (final st in t.steps)
      if (!st.done && !have.contains(st.id) && !t.slotsOf(st).any((x) => _sameDay(x.start, day)))
        TrayItem(t, st.dueAt == null ? 'Step' : 'Step due ${fmt.format(st.dueAt!)}', step: st, other: i.other),
  ];
}

/// The day the Day plan's week arrows go to: the Monday [by] weeks from [day]'s week, or [today]
/// when it falls in that week.
DateTime weekStartFrom(DateTime day, int by, {required DateTime today}) {
  final d = DateTime(day.year, day.month, day.day);
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1) + 7 * by);
  final t = DateTime(today.year, today.month, today.day);
  return !t.isBefore(monday) && t.isBefore(DateTime(monday.year, monday.month, monday.day + 7)) ? t : monday;
}

/// Rounds [t] to the nearest [snap] minutes.
DateTime snapTime(DateTime t, int snap) {
  final m = t.hour * 60 + t.minute + (t.second >= 30 ? 1 : 0);
  final r = ((m / snap).round() * snap).clamp(0, 24 * 60 - snap);
  return DateTime(t.year, t.month, t.day).add(Duration(minutes: r));
}

/// Rounds [t] up to the next [snap] minutes.
DateTime snapUp(DateTime t, int snap) {
  final m = t.hour * 60 + t.minute + (t.second > 0 ? 1 : 0);
  final r = ((m + snap - 1) ~/ snap) * snap;
  return DateTime(t.year, t.month, t.day).add(Duration(minutes: r));
}

/// "1 h 30", "45 min".
String describeLength(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m';
}

/// 1.12.5: the suggested driving before (or [after]) [t]'s next planned time, or, with none,
/// from and back to Home. Null without a pin or a saved Home.
({int minutes, String? from, bool estimate})? suggestDrive(AppData data, Task t, {required bool after, DateTime? at}) {
  final now = at ?? DateTime.now();
  final next = t.slots.where((x) => x.doneAt == null && x.end.isAfter(now)).fold<TimeSlot?>(
      null, (a, x) => a == null || x.start.isBefore(a.start) ? x : a);
  if (next != null) {
    final day = blocksOn(data, next.start).where((b) => !b.shared && !b.done).toList();
    final b = day.where((b) => identical(b.slot, next)).firstOrNull;
    if (b != null) return driveFor(t, b, day, after: after, suggest: true);
  }
  return driveFor(t, PlanBlock(t, TimeSlot.create(now, 30)), const [], after: after, suggest: true);
}
