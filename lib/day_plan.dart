import 'package:intl/intl.dart';

import 'gantt.dart';
import 'models.dart';

/// Item 101: the Day plan. Everything here is plain logic (what goes where on one day), so it can
/// be tested without a screen; lib/screens/day_plan_page.dart draws it.

/// One planned time on the day: a task's or a step's [slot].
class PlanBlock {
  PlanBlock(this.task, this.slot, {this.step});

  final Task task;
  final TaskStep? step;
  final TimeSlot slot;

  DateTime get start => slot.start;
  DateTime get end => slot.end;
  bool get shared => slot.shared;

  /// Ticked here, or the step or task itself is done.
  bool get done => slot.doneAt != null || (step?.done ?? task.closedAt != null);

  String get title => step?.title ?? task.title;

  // Filled in by [layoutDay].

  /// Its category is hidden: drawn as a faint strip (or not at all).
  bool hidden = false;

  /// Overlaps another ordinary block (not one that leaves room).
  bool clash = false;

  /// Side by side with what it clashes with: its column and how many there are.
  int column = 0;
  int columns = 1;

  /// Sits on top of a block that leaves room (drawn to the right of its band).
  bool inBand = false;

  /// Its task's block, when this is a step planned inside its task's time.
  PlanBlock? frame;

  /// Steps planned inside this task's time, drawn inside its block.
  final List<PlanBlock> inside = [];

  bool overlaps(PlanBlock o) => start.isBefore(o.end) && o.start.isBefore(end);
}

/// A stretch of time on the day: a gap after a block, or free time.
class Span {
  const Span(this.start, this.end);
  final DateTime start;
  final DateTime end;
  int get minutes => end.difference(start).inMinutes;
}

/// Everything on one day, laid out.
class DayLayout {
  DayLayout(this.day, this.blocks, this.gaps, this.free, {required this.workStart, required this.workEnd});

  final DateTime day;

  /// Blocks drawn on the timeline (steps inside a task's block are in its [PlanBlock.inside]).
  final List<PlanBlock> blocks;

  /// The gaps kept after blocks.
  final List<Span> gaps;

  /// Free time inside working hours.
  final List<Span> free;

  final DateTime workStart, workEnd;

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

  int get clashes => blocks.where((b) => b.clash).length;

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
DayLayout layoutDay(AppData data, DateTime day) {
  final s = data.dayPlan;
  var blocks = blocksOn(data, day);
  for (final b in blocks) {
    b.hidden = categoryHidden(data, b.task.categoryId);
  }
  if (!s.hiddenStrip) blocks = blocks.where((b) => !b.hidden).toList();

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
  final plain = shown.where((b) => !b.shared && !b.hidden).toList();
  for (final b in plain) {
    b.inBand = bands.any(b.overlaps);
  }
  // Clashes: ordinary blocks that overlap, put side by side in columns, cluster by cluster.
  var cluster = <PlanBlock>[];
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

  // Gaps after each ordinary block, cut short by whatever comes next.
  final gaps = <Span>[];
  final busy = <Span>[];
  for (final b in shown.where((b) => !b.shared)) {
    busy.add(Span(b.start, b.end));
    final g = b.slot.gapAfter ?? s.gapMinutes;
    if (g <= 0) continue;
    var gEnd = b.end.add(Duration(minutes: g));
    for (final o in shown) {
      if (!o.shared && o.start.isAfter(b.start) && !o.start.isBefore(b.end) && o.start.isBefore(gEnd)) gEnd = o.start;
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

  return DayLayout(day, shown, gaps, free, workStart: ws, workEnd: we);
}

/// How full [day] is: planned minutes inside working hours over the working minutes (above 1
/// when over-full). Bands that leave room don't count.
double dayLoad(AppData data, DateTime day) {
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
  return (_union(spans) + outside) / work;
}

/// Something waiting in the "To plan" tray, with why it's there.
class TrayItem {
  const TrayItem(this.task, this.why, {this.step});
  final Task task;
  final TaskStep? step;
  final String why;
  String get title => step?.title ?? task.title;

  /// Length to plan it for: its estimate, else the default.
  int minutes(AppData data) => step == null ? task.estimate ?? data.dayPlan.length : data.dayPlan.length;
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
  for (final t in data.active) {
    if (t.habit || categoryHidden(data, t.categoryId)) continue;
    final own = t.ownSlots.toList();
    if (own.any((x) => _sameDay(x.start, day))) {
      // Planned that day; only its due steps without a time can still be waiting.
    } else {
      final upcoming = own.any((x) => x.doneAt == null && !x.start.isBefore(DateTime(now.year, now.month, now.day)));
      final missed = own.where((x) => x.doneAt == null && x.end.isBefore(now)).toList()
        ..sort((a, b) => b.start.compareTo(a.start));
      String? why;
      final due = t.dueAt;
      final bar = s.trayGantt && t.gantt ? barFor(t, data) : null;
      if (s.trayDue && due != null && _sameDay(due, day)) {
        why = due.isBefore(now) ? 'Overdue' : 'Due ${DateFormat('HH:mm').format(due)}';
      } else if (!upcoming && missed.isNotEmpty) {
        why = 'Missed ${fmt.format(missed.first.start)}, ${DateFormat('HH:mm').format(missed.first.start)}';
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
      if (why != null) (why == 'Overdue' ? dueFirst : out).add(TrayItem(t, why));
    }
    if (s.trayDue && s.show != DayShow.tasks) {
      for (final st in t.steps) {
        final due = st.dueAt;
        if (st.done || due == null || !_sameDay(due, day) || t.slotsOf(st).any((x) => _sameDay(x.start, day))) continue;
        out.add(TrayItem(t, 'Step due ${DateFormat('HH:mm').format(due)}', step: st));
      }
    }
  }
  return [...dueFirst, ...out];
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
