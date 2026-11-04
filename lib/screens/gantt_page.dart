import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../gantt.dart';
import '../models.dart';
import '../store.dart';
import 'task_page.dart';

/// Item 72: the Gantt chart. Only tasks put on it show, as bars from start to expected end with
/// the due date as a flag, grouped by category, with arrows for "comes after".
class GanttPage extends StatefulWidget {
  const GanttPage({super.key, required this.store, this.initialCategory});

  final AppStore store;

  /// Opens on one category (null = all, '' = no category).
  final String? initialCategory;

  @override
  State<GanttPage> createState() => _GanttPageState();
}

/// How wide a day is at each zoom.
enum GanttZoom {
  day('Day', 56),
  week('Week', 32),
  month('Month', 12);

  const GanttZoom(this.label, this.dayWidth);
  final String label;
  final double dayWidth;
}

/// Colours for categories on the chart, by their place in the list.
const ganttPalette = [
  Color(0xFF2557D6),
  Color(0xFFC2500A),
  Color(0xFF1B7A3E),
  Color(0xFF7B3FC4),
  Color(0xFFB0185E),
  Color(0xFF0E7C86),
  Color(0xFF8A6D00),
];

Color ganttColour(AppData data, String? categoryId) {
  final i = data.categories.indexWhere((c) => c.id == categoryId);
  return i < 0 ? const Color(0xFF5F5F66) : ganttPalette[i % ganttPalette.length];
}

class _Row {
  _Row.group(this.label, this.colour, this.groupBar)
      : task = null,
        step = null,
        height = 30;
  _Row.task(Task this.task)
      : label = task.title,
        colour = null,
        groupBar = null,
        step = null,
        height = 44;
  _Row.step(Task this.task, TaskStep this.step)
      : label = step.title,
        colour = null,
        groupBar = null,
        height = 28;

  final String label;
  final Color? colour;
  final (DateTime, DateTime)? groupBar;
  final Task? task;
  final TaskStep? step;
  final double height;
}

class _GanttPageState extends State<GanttPage> {
  GanttZoom _zoom = GanttZoom.week;
  late String? _category = widget.initialCategory;
  bool _showTicked = false;
  final _expanded = <String>{};

  // A bar being dragged (after a long press): its task, how far, and whether its end is moving.
  String? _dragId;
  double _dragDx = 0;
  bool _dragEnd = false;

  final _hScroll = ScrollController();
  bool _scrolledToToday = false;

  AppStore get store => widget.store;
  AppData get data => store.data;
  double get _dayW => _zoom.dayWidth;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  bool _inCategory(Task t) {
    final c = _category;
    return c == null || (c.isEmpty ? data.category(t.categoryId) == null : t.categoryId == c);
  }

  List<Task> _tasks(DateTime now) => [
        for (final t in data.ganttTasks)
          if (_inCategory(t)) t,
        if (_showTicked)
          for (final t in data.archived)
            if (t.gantt && _inCategory(t) && now.difference(t.closedAt!).inDays <= 14) t,
      ];

  void _open(Task t) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: t)));

  /// After a move: the tasks after it that would now start too early, moved as Settings says.
  Future<void> _afterMove(Task t, Map<Task, int> plan) async {
    if (plan.isEmpty || !mounted) return;
    var push = data.ganttPush;
    if (push == GanttPush.ask) {
      final n = plan.length;
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Move the $n task${n == 1 ? '' : 's'} after it too?'),
          content: Text([
            for (final e in plan.entries) '${e.key.title}: ${e.value} day${e.value == 1 ? '' : 's'} later',
          ].join('\n')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Just this one')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move them too')),
          ],
        ),
      );
      push = yes == true ? GanttPush.always : GanttPush.never;
    }
    if (push == GanttPush.always) store.pushLater(plan);
  }

  Future<void> _giveDates(Task t) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: 'When does "${t.title}" start?',
      initialDate: dayOf(now),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    t.startAt = picked;
    store.ganttChanged(t);
  }

  List<_Row> _rows(List<Task> tasks) {
    final out = <_Row>[];
    final groups = <String?, List<Task>>{};
    for (final t in tasks) {
      groups.putIfAbsent(t.categoryId != null && data.category(t.categoryId) != null ? t.categoryId : null, () => []).add(t);
    }
    final order = [
      for (final c in data.categories)
        if (groups.containsKey(c.id)) c.id,
      if (groups.containsKey(null)) null,
    ];
    for (final id in order) {
      final list = groups[id]!
        ..sort((a, b) {
          final x = barFor(a, data)?.start, y = barFor(b, data)?.start;
          if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
          return x.compareTo(y);
        });
      final bars = [for (final t in list) ?barFor(t, data)];
      final span = bars.isEmpty
          ? null
          : (bars.map((b) => b.start).reduce((a, b) => a.isBefore(b) ? a : b),
              bars.map((b) => b.end).reduce((a, b) => a.isAfter(b) ? a : b));
      out.add(_Row.group(data.category(id)?.name ?? 'No category', ganttColour(data, id), span));
      for (final t in list) {
        if (barFor(t, data) == null) continue;
        out.add(_Row.task(t));
        if (_expanded.contains(t.id)) {
          for (final s in t.steps) {
            out.add(_Row.step(t, s));
          }
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        final tasks = _tasks(now);
        final dated = [for (final t in tasks) if (barFor(t, data) != null) t];
        final undated = [for (final t in tasks) if (barFor(t, data) == null && t.closedAt == null) t];
        final clashCount = dated.where((t) => clashes(t, data)).length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Gantt chart'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SegmentedButton<GanttZoom>(
                  showSelectedIcon: false,
                  segments: [for (final z in GanttZoom.values) ButtonSegment(value: z, label: Text(z.label))],
                  selected: {_zoom},
                  onSelectionChanged: (s) => setState(() => _zoom = s.first),
                ),
              ),
            ],
          ),
          body: Column(children: [
            _filters(dated.length, clashCount),
            Expanded(
              child: data.ganttTasks.isEmpty && !_showTicked
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nothing on the Gantt chart yet.\n\nOpen a task and turn on "On the Gantt chart", '
                          'or add one with !gantt in the add box.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _chart(dated, now),
            ),
            if (undated.isNotEmpty) _needsDates(undated),
          ]),
        );
      },
    );
  }

  Widget _filters(int count, int clashCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<String?>(
          value: _category,
          underline: const SizedBox(),
          items: [
            const DropdownMenuItem(value: null, child: Text('All categories')),
            for (final c in data.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
            const DropdownMenuItem(value: '', child: Text('No category')),
          ],
          onChanged: (v) => setState(() => _category = v),
        ),
        FilterChip(
          label: const Text('Show ticked'),
          selected: _showTicked,
          onSelected: (v) => setState(() => _showTicked = v),
        ),
        Text(
          '$count on the chart${clashCount == 0 ? '' : ' · $clashCount clash${clashCount == 1 ? '' : 'es'}'}',
          style: TextStyle(color: clashCount == 0 ? null : Theme.of(context).colorScheme.error),
        ),
      ]),
    );
  }

  Widget _chart(List<Task> tasks, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final bars = [for (final t in tasks) ?barFor(t, data)];
    final (first, last) = chartRange(bars, now);
    final days = daysBetween(first, last) + 1;
    final width = days * _dayW;
    final rows = _rows(tasks);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final nameW = narrow ? 120.0 : 220.0;
    double xOf(DateTime d) => daysBetween(first, d) * _dayW;

    if (!_scrolledToToday) {
      _scrolledToToday = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hScroll.hasClients) {
          _hScroll.jumpTo(max(0, min(xOf(addDays(now, -2)), _hScroll.position.maxScrollExtent)));
        }
      });
    }

    // Where each task's bar sits, for the arrows.
    final rowTop = <String, double>{};
    var y = 0.0;
    for (final r in rows) {
      if (r.task != null && r.step == null) rowTop[r.task!.id] = y;
      y += r.height;
    }
    final bodyHeight = y;
    final links = linksAmong(tasks, data);

    return SingleChildScrollView(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Names, fixed on the left.
        SizedBox(
          width: nameW,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
                  child: Text('Task', style: Theme.of(context).textTheme.labelMedium),
                ),
              ),
            ),
            for (final r in rows) _nameCell(r, narrow),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _header(first, days, now),
                SizedBox(
                  height: bodyHeight,
                  child: Stack(children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _GridPainter(first, days, _dayW, now, scheme)),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LinkPainter(links, rowTop, (t) => barFor(t, data), xOf, _dayW, scheme,
                            dragId: _dragId, dragDays: (_dragDx / _dayW).round(), dragEnd: _dragEnd),
                      ),
                    ),
                    Column(children: [for (final r in rows) _barCell(r, xOf, width, now)]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _header(DateTime first, int days, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall;
    final showDay = _dayW >= 24;
    return SizedBox(
      height: 48,
      child: Column(children: [
        SizedBox(
          height: 22,
          child: Stack(children: [
            for (var i = 0; i < days; i++)
              if (addDays(first, i).weekday == DateTime.monday || i == 0)
                Positioned(
                  left: i * _dayW + 4,
                  top: 4,
                  child: Text(
                    _dayW >= 24
                        ? DateFormat('d MMM').format(addDays(first, i))
                        : addDays(first, i).day <= 7
                            ? DateFormat('MMM').format(addDays(first, i))
                            : '',
                    style: small?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
          ]),
        ),
        SizedBox(
          height: 26,
          child: Row(children: [
            for (var i = 0; i < days; i++)
              Builder(builder: (context) {
                final d = addDays(first, i);
                final today = daysBetween(d, now) == 0;
                return Container(
                  width: _dayW,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: today ? scheme.primary : (isWeekend(d) ? scheme.surfaceContainerHighest : null),
                    borderRadius: today ? BorderRadius.circular(6) : null,
                  ),
                  child: Text(
                    showDay ? '${DateFormat('E').format(d).substring(0, 1)} ${d.day}' : (d.day % 7 == 1 ? '${d.day}' : ''),
                    style: small?.copyWith(color: today ? scheme.onPrimary : null),
                    overflow: TextOverflow.clip,
                    maxLines: 1,
                  ),
                );
              }),
          ]),
        ),
      ]),
    );
  }

  Widget _nameCell(_Row r, bool narrow) {
    final theme = Theme.of(context);
    if (r.task == null) {
      return Container(
        height: r.height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: theme.colorScheme.surfaceContainerLow,
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: r.colour, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        ]),
      );
    }
    final t = r.task!;
    if (r.step != null) {
      final s = r.step!;
      return SizedBox(
        height: r.height,
        child: Padding(
          padding: EdgeInsets.only(left: narrow ? 24 : 40, right: 8),
          child: Row(children: [
            Icon(s.done ? Icons.check : Icons.radio_button_unchecked, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(s.title, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );
    }
    final bar = barFor(t, data)!;
    final clash = clashes(t, data);
    final fmt = DateFormat('d MMM');
    final sub = t.closedAt != null
        ? 'Ticked off ${fmt.format(t.closedAt!)}'
        : clash
            ? 'Starts before what it comes after ends'
            : bar.late
                ? 'Ends ${bar.lateDays} day${bar.lateDays == 1 ? '' : 's'} after due'
                : t.milestone
                    ? 'Milestone · ${fmt.format(bar.start)}'
                    : '${fmt.format(bar.start)} to ${fmt.format(bar.end)}';
    return InkWell(
      onTap: () => _open(t),
      child: Container(
        height: r.height,
        color: clash ? theme.colorScheme.errorContainer.withValues(alpha: 0.35) : null,
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    decoration: t.closedAt != null ? TextDecoration.lineThrough : null,
                    fontSize: narrow ? 13 : 14,
                  )),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: clash || bar.late ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          if (t.steps.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _expanded.contains(t.id) ? 'Hide steps' : 'Show steps',
              icon: Icon(_expanded.contains(t.id) ? Icons.expand_less : Icons.expand_more, size: 20),
              onPressed: () => setState(() => _expanded.contains(t.id) ? _expanded.remove(t.id) : _expanded.add(t.id)),
            ),
        ]),
      ),
    );
  }

  Widget _barCell(_Row r, double Function(DateTime) xOf, double width, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    if (r.task == null) {
      final span = r.groupBar;
      return Container(
        height: r.height,
        width: width,
        color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
        child: span == null
            ? null
            : Stack(children: [
                Positioned(
                  left: xOf(span.$1),
                  top: 12,
                  width: (daysBetween(span.$1, span.$2) + 1) * _dayW,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: r.colour!.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ]),
      );
    }
    final t = r.task!;
    final colour = ganttColour(data, t.categoryId);
    if (r.step != null) {
      final s = r.step!;
      final due = s.dueAt;
      return SizedBox(
        height: r.height,
        width: width,
        child: due == null
            ? null
            : Stack(children: [
                Positioned(
                  left: xOf(due) + _dayW / 2 - 6,
                  top: r.height / 2 - 6,
                  child: Transform.rotate(
                    angle: pi / 4,
                    child: Container(width: 12, height: 12, color: s.done ? scheme.outline : colour),
                  ),
                ),
              ]),
      );
    }
    final bar = barFor(t, data)!;
    final dragging = _dragId == t.id;
    final dragDays = dragging ? (_dragDx / _dayW).round() : 0;
    var left = xOf(bar.start) + (dragging && !_dragEnd ? dragDays * _dayW : 0);
    var w = bar.length * _dayW + (dragging && _dragEnd ? dragDays * _dayW : 0);
    w = max(w, _dayW);
    final done = t.closedAt != null;
    final barColour = done ? scheme.outlineVariant : colour;
    final children = <Widget>[];

    // Where it was first planned, faint behind a slipped bar.
    final ps = t.planStart, pd = t.planDue;
    if (!done && ps != null && pd != null && (daysBetween(ps, bar.start) != 0 || daysBetween(pd, bar.end) != 0)) {
      children.add(Positioned(
        left: xOf(ps),
        top: 10,
        width: (daysBetween(ps, pd) + 1) * _dayW,
        height: 24,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colour.withValues(alpha: 0.45), width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ));
    }

    if (t.milestone) {
      children.add(Positioned(
        left: left + _dayW / 2 - 10,
        top: 12,
        child: GestureDetector(
          onTap: () => _open(t),
          onLongPressStart: (_) => setState(() {
            _dragId = t.id;
            _dragDx = 0;
            _dragEnd = false;
          }),
          onLongPressMoveUpdate: (d) => setState(() => _dragDx = d.offsetFromOrigin.dx),
          onLongPressEnd: (_) => _endDrag(t),
          child: Transform.rotate(
            angle: pi / 4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: barColour, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
      ));
    } else {
      final share = t.progressShare;
      children.add(Positioned(
        left: left,
        top: 10,
        width: w,
        height: 24,
        child: GestureDetector(
          onTap: () => _open(t),
          onLongPressStart: (_) => setState(() {
            _dragId = t.id;
            _dragDx = 0;
            _dragEnd = false;
          }),
          onLongPressMoveUpdate: (d) => setState(() => _dragDx = d.offsetFromOrigin.dx),
          onLongPressEnd: (_) => _endDrag(t),
          child: Tooltip(
            message: [
              t.title,
              if (t.takesDays != null) 'Takes ${t.takesDays} day${t.takesDays == 1 ? '' : 's'}',
              if (t.estimate != null) 'About ${t.estimate} min of work',
              if (bar.guessedStart) 'No start date: counted back from the due date',
            ].join('\n'),
            child: Container(
              decoration: BoxDecoration(
                color: barColour.withValues(alpha: done ? 1 : 0.25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: dragging ? scheme.primary : barColour,
                  width: dragging ? 2 : 1,
                  style: bar.guessedStart ? BorderStyle.none : BorderStyle.solid,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                if (share > 0 && !done) FractionallySizedBox(widthFactor: share, heightFactor: 1, child: ColoredBox(color: barColour)),
                if (bar.late && !done)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: min(w, bar.lateDays * _dayW),
                    child: ColoredBox(color: scheme.error.withValues(alpha: 0.35)),
                  ),
                if (done) const Center(child: Icon(Icons.check, size: 16)),
                if (share > 0 && !done && w > 44)
                  Positioned(
                    left: 6,
                    top: 4,
                    child: Text('${(share * 100).round()}%',
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ),
        ),
      ));
      // The handle on the right end changes the length.
      if (!done) {
        children.add(Positioned(
          left: left + w - 14,
          top: 6,
          width: 22,
          height: 32,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => setState(() {
              _dragId = t.id;
              _dragDx = 0;
              _dragEnd = true;
            }),
            onLongPressMoveUpdate: (d) => setState(() => _dragDx = d.offsetFromOrigin.dx),
            onLongPressEnd: (_) => _endDrag(t),
            child: Center(
              child: Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(color: barColour, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ));
      }
    }
    // The due date's flag, when it isn't the bar's end.
    final due = bar.due;
    if (due != null && !t.milestone && daysBetween(due, bar.end) != 0) {
      final x = xOf(due) + _dayW - 1;
      children.add(Positioned(
        left: x,
        top: 4,
        child: Tooltip(
          message: 'Due ${DateFormat('EEE d MMM').format(due)}',
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 2, height: 36, color: bar.late ? scheme.error : scheme.onSurfaceVariant),
            Icon(Icons.flag, size: 12, color: bar.late ? scheme.error : scheme.onSurfaceVariant),
          ]),
        ),
      ));
    }
    if (t.steps.isNotEmpty && !_expanded.contains(t.id) && _dayW >= 24) {
      children.add(Positioned(
        left: left + w + 8,
        top: 13,
        child: Text('${t.stepsDone} of ${t.steps.length} steps', style: Theme.of(context).textTheme.labelSmall),
      ));
    }
    return SizedBox(height: r.height, width: width, child: Stack(clipBehavior: Clip.none, children: children));
  }

  Future<void> _endDrag(Task t) async {
    final days = (_dragDx / _dayW).round();
    final end = _dragEnd;
    setState(() {
      _dragId = null;
      _dragDx = 0;
    });
    if (days == 0) return;
    final bar = barFor(t, data);
    if (bar == null) return;
    final plan = end ? store.resizeOnGantt(t, addDays(bar.end, days)) : store.moveOnGantt(t, days);
    await _afterMove(t, plan);
  }

  Widget _needsDates(List<Task> tasks) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Needs dates (${tasks.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final t in tasks)
            ActionChip(
              label: Text(t.title),
              avatar: CircleAvatar(backgroundColor: ganttColour(data, t.categoryId), radius: 5),
              onPressed: () => _giveDates(t),
            ),
          Text('Tap one to give it a start date', style: theme.textTheme.labelSmall),
        ]),
      ),
    );
  }
}

/// Weekend shading, week lines and today's line.
class _GridPainter extends CustomPainter {
  _GridPainter(this.first, this.days, this.dayW, this.now, this.scheme);

  final DateTime first;
  final int days;
  final double dayW;
  final DateTime now;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final weekend = Paint()..color = scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final line = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 1;
    for (var i = 0; i < days; i++) {
      final d = addDays(first, i);
      if (isWeekend(d)) canvas.drawRect(Rect.fromLTWH(i * dayW, 0, dayW, size.height), weekend);
      if (d.weekday == DateTime.monday) canvas.drawLine(Offset(i * dayW, 0), Offset(i * dayW, size.height), line);
    }
    final t = daysBetween(first, now);
    if (t >= 0 && t < days) {
      final x = t * dayW + dayW / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
        ..color = scheme.primary
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.first != first || old.days != days || old.dayW != dayW || old.scheme != scheme;
}

/// The "comes after" arrows: from the end of one bar to the start of the next, red on a clash.
class _LinkPainter extends CustomPainter {
  _LinkPainter(this.links, this.rowTop, this.barOf, this.xOf, this.dayW, this.scheme,
      {this.dragId, this.dragDays = 0, this.dragEnd = false});

  final List<GanttLink> links;
  final Map<String, double> rowTop;
  final GanttBar? Function(Task) barOf;
  final double Function(DateTime) xOf;
  final double dayW;
  final ColorScheme scheme;
  final String? dragId;
  final int dragDays;
  final bool dragEnd;

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in links) {
      final fromTop = rowTop[l.from.id], toTop = rowTop[l.to.id];
      final a = barOf(l.from), b = barOf(l.to);
      if (fromTop == null || toTop == null || a == null || b == null) continue;
      var x1 = xOf(a.end) + dayW;
      var x2 = xOf(b.start);
      if (l.from.id == dragId) x1 += dragDays * dayW;
      if (l.to.id == dragId && !dragEnd) x2 += dragDays * dayW;
      final y1 = fromTop + 22, y2 = toTop + 22;
      final colour = l.clash ? scheme.error : scheme.onSurfaceVariant;
      final paint = Paint()
        ..color = colour
        ..strokeWidth = l.clash ? 1.8 : 1.4
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(x1, y1);
      if (x2 - 8 >= x1 + 4) {
        final mid = x1 + 6;
        path
          ..lineTo(mid, y1)
          ..lineTo(mid, y2)
          ..lineTo(x2 - 2, y2);
      } else {
        // The next one starts before this ends: go round.
        final drop = y1 + (y2 > y1 ? 18 : -18);
        path
          ..lineTo(x1 + 8, y1)
          ..lineTo(x1 + 8, drop)
          ..lineTo(x2 - 10, drop)
          ..lineTo(x2 - 10, y2)
          ..lineTo(x2 - 2, y2);
      }
      canvas.drawPath(path, paint);
      final head = Path()
        ..moveTo(x2, y2)
        ..lineTo(x2 - 7, y2 - 4)
        ..lineTo(x2 - 7, y2 + 4)
        ..close();
      canvas.drawPath(head, Paint()..color = colour);
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => true;
}

/// Item 72: the right-hand panel's Timeline view: the next 14 days of the Gantt chart, narrow.
class GanttTimeline extends StatelessWidget {
  const GanttTimeline({super.key, required this.store, required this.onOpen});

  final AppStore store;
  final void Function(Task) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final data = store.data;
        final theme = Theme.of(context);
        final today = dayOf(DateTime.now());
        const days = 14;
        final last = addDays(today, days - 1);
        final items = [
          for (final t in data.ganttTasks)
            if (barFor(t, data) case final b? when !b.end.isBefore(today) && !b.start.isAfter(last)) b,
        ]..sort((a, b) => a.start.compareTo(b.start));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
            child: Row(children: [
              Expanded(child: Text('Next 14 days', style: theme.textTheme.titleSmall)),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GanttPage(store: store))),
                child: const Text('Open chart'),
              ),
            ]),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nothing on the Gantt chart in the next 14 days.', textAlign: TextAlign.center),
                    ),
                  )
                : LayoutBuilder(builder: (context, box) {
                    final dayW = (box.maxWidth - 24) / days;
                    return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                      for (final b in items)
                        InkWell(
                          onTap: () => onOpen(b.task),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b.task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 12,
                                child: Stack(children: [
                                  Positioned.fill(child: ColoredBox(color: theme.colorScheme.surfaceContainerHighest)),
                                  Positioned(
                                    left: max(0, daysBetween(today, b.start)) * dayW,
                                    width: (daysBetween(b.start.isBefore(today) ? today : b.start,
                                                    b.end.isAfter(last) ? last : b.end) +
                                                1) *
                                        dayW,
                                    top: 0,
                                    bottom: 0,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: b.late || clashes(b.task, data)
                                            ? theme.colorScheme.error
                                            : ganttColour(data, b.task.categoryId),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                    ]);
                  }),
          ),
        ]);
      },
    );
  }
}
