import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../gantt.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/burn_down_chart.dart';
import 'task_page.dart';

/// Item 72: the Gantt chart. Only tasks put on it show, as bars from start to expected end with
/// the due date as a flag, grouped by category, with arrows for "comes after".
class GanttPage extends StatefulWidget {
  const GanttPage({super.key, required this.store, this.initialCategory, this.focusTaskId});

  final AppStore store;

  /// Opens on one category (null = all, '' = no category).
  final String? initialCategory;

  /// Item 84: opens zoomed in on this task and its steps (from the task page).
  final String? focusTaskId;

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
  _Row.group(this.label, this.colour, this.groupBar, this.members)
      : task = null,
        step = null,
        height = 30;
  _Row.task(Task this.task)
      : label = task.title,
        members = const [],
        colour = null,
        groupBar = null,
        step = null,
        height = 44;
  _Row.step(Task this.task, TaskStep this.step)
      : label = step.title,
        members = const [],
        colour = null,
        groupBar = null,
        height = 28;

  final String label;
  final Color? colour;
  final (DateTime, DateTime)? groupBar;
  final List<Task> members;
  final Task? task;
  final TaskStep? step;
  final double height;
}

class _GanttPageState extends State<GanttPage> {
  GanttZoom _zoom = GanttZoom.week;
  late String? _category = widget.initialCategory;
  bool _showTicked = false;
  bool _burnOpen = false;
  BurnUnit _burnUnit = BurnUnit.items;
  final _expanded = <String>{};

  // A bar being dragged (after a long press): its task, how far, and whether its end is moving.
  String? _dragId;
  double _dragDx = 0;
  bool _dragEnd = false;

  final _hScroll = ScrollController();
  bool _opened = false;

  // Item 84: a day width picked to fit some bars on screen (null = the zoom's own), how wide the
  // dates area is, and its first day.
  double? _fitW;
  String? _burnTaskId;
  double _viewW = 0;
  DateTime? _first;

  AppStore get store => widget.store;
  AppData get data => store.data;
  double get _dayW => _fitW ?? _zoom.dayWidth;

  @override
  void initState() {
    super.initState();
    final id = widget.focusTaskId;
    if (id != null) {
      _expanded.add(id);
      if (data.archived.any((t) => t.id == id)) _showTicked = true;
    }
  }

  /// The bars of [tasks], with the steps of the ones opened out (or all their steps).
  List<GanttBar> _barsOf(Iterable<Task> tasks, {bool steps = false}) => [
        for (final t in tasks) ...[
          ?barFor(t, data),
          if (steps || _expanded.contains(t.id))
            for (final s in t.steps) ?stepBar(t, s, data),
        ],
      ];

  /// Item 84: zoom and scroll so [bars] fill the width of the chart, with a day spare each side.
  /// Item 86: zoomed to one [task], the burn-down strip shows that task's; otherwise the filter's.
  void _focusOn(Iterable<GanttBar> bars, {String? task}) {
    _burnTaskId = task;
    if (bars.isEmpty || _viewW <= 0) return setState(() {});
    var a = bars.first.start, b = bars.first.end;
    for (final x in bars) {
      if (x.start.isBefore(a)) a = x.start;
      if (x.end.isAfter(b)) b = x.end;
      final due = x.due;
      if (due != null && due.isAfter(b)) b = due;
    }
    a = addDays(a, -1);
    b = addDays(b, 1);
    final span = daysBetween(a, b) + 1;
    setState(() => _fitW = (_viewW / span).clamp(3.0, 56.0));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final first = _first;
      if (first == null || !_hScroll.hasClients) return;
      // Centred when it is short enough to leave room either side.
      final x = daysBetween(first, a) * _dayW - max(0.0, (_viewW - span * _dayW) / 2);
      _hScroll.jumpTo(x.clamp(0.0, _hScroll.position.maxScrollExtent));
    });
  }

  /// Back to a set zoom, keeping the same day in the middle.
  void _setZoom(GanttZoom z) {
    final mid = _hScroll.hasClients ? (_hScroll.offset + _viewW / 2) / _dayW : null;
    setState(() {
      _zoom = z;
      _fitW = null;
    });
    if (mid == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hScroll.hasClients) return;
      _hScroll.jumpTo((mid * _dayW - _viewW / 2).clamp(0.0, _hScroll.position.maxScrollExtent));
    });
  }

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
      out.add(_Row.group(data.category(id)?.name ?? 'No category', ganttColour(data, id), span,
          [for (final t in list) if (barFor(t, data) != null) t]));
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
              IconButton(
                tooltip: 'Fit what is shown',
                icon: const Icon(Icons.fit_screen_outlined),
                isSelected: _fitW != null,
                onPressed: dated.isEmpty ? null : () => _focusOn(_barsOf(dated)),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SegmentedButton<GanttZoom>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  segments: [for (final z in GanttZoom.values) ButtonSegment(value: z, label: Text(z.label))],
                  selected: _fitW == null ? {_zoom} : {},
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) _setZoom(s.first);
                  },
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
            _burnStrip(now),
            if (undated.isNotEmpty) _needsDates(undated),
          ]),
        );
      },
    );
  }

  /// Item 77: the burn-down for what the filter shows, folded away until opened.
  Widget _burnStrip(DateTime now) {
    final id = _burnTaskId;
    final task = id == null ? null : anyTask(data, id);
    final own = task == null ? null : taskBurnDown(task, data, now, unit: _burnUnit);
    final burn = own ?? burnDown(burnTasks(data, _category), data, now, unit: _burnUnit);
    if (burn == null) return const SizedBox();
    final late = burn.daysLate;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Divider(height: 1),
        InkWell(
          onTap: () => setState(() => _burnOpen = !_burnOpen),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              const Icon(Icons.trending_down, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _burnOpen ? (own != null ? 'Burn-down · ${task!.title}' : 'Burn-down') : burnSummary(burn),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: late != null && late > 0 && burn.now > 0 ? Theme.of(context).colorScheme.error : null),
                ),
              ),
              if (own != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('All in category'),
                    onPressed: () => setState(() => _burnTaskId = null),
                  ),
                ),
              Icon(_burnOpen ? Icons.expand_more : Icons.expand_less),
            ]),
          ),
        ),
        if (_burnOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SegmentedButton<BurnUnit>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: BurnUnit.items, label: Text(own != null ? 'Steps' : 'Tasks and steps')),
                  const ButtonSegment(value: BurnUnit.days, label: Text('Days of work')),
                ],
                selected: {_burnUnit},
                onSelectionChanged: (v) => setState(() => _burnUnit = v.first),
              ),
              const SizedBox(height: 6),
              BurnDownChart(burn: burn, now: now, height: 110),
              const SizedBox(height: 4),
              Text(burnSummary(burn), style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
      ]),
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
          onChanged: (v) {
            setState(() => _category = v);
            // Item 84: zoom to the category picked.
            _focusOn(_barsOf([for (final t in _tasks(DateTime.now())) if (barFor(t, data) != null) t]));
          },
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
    final bars = [
      for (final t in tasks) ?barFor(t, data),
      for (final t in tasks)
        for (final s in t.steps) ?stepBar(t, s, data),
    ];
    final (first, last) = chartRange(bars, now);
    _first = first;
    final days = daysBetween(first, last) + 1;
    final width = days * _dayW;
    final rows = _rows(tasks);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final nameW = narrow ? 120.0 : 220.0;
    double xOf(DateTime d) => daysBetween(first, d) * _dayW;

    return LayoutBuilder(builder: (context, box) {
      _viewW = max(0.0, box.maxWidth - nameW - 1);
      if (!_opened && _viewW > 0) {
        _opened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _openAt(tasks, bars, now));
      }
      return _chartBody(tasks, rows, first, days, width, nameW, narrow, now, xOf);
    });
  }

  /// Item 84: where the chart opens. On the task it was opened for; else on today, unless nothing
  /// on the chart is near today, then zoomed to fit everything.
  void _openAt(List<Task> tasks, List<GanttBar> bars, DateTime now) {
    if (!mounted) return;
    final id = widget.focusTaskId;
    final focus = id == null ? null : tasks.where((t) => t.id == id).firstOrNull;
    if (focus != null) return _focusOn(_barsOf([focus], steps: true), task: focus.id);
    final from = addDays(dayOf(now), -2), to = addDays(from, (_viewW / _dayW).floor());
    final nearToday = bars.any((b) => !b.start.isAfter(to) && !b.end.isBefore(from));
    if (!nearToday && bars.isNotEmpty) return _focusOn(bars);
    final first = _first;
    if (first != null && _hScroll.hasClients) {
      _hScroll.jumpTo((daysBetween(first, from) * _dayW).clamp(0.0, _hScroll.position.maxScrollExtent));
    }
  }

  Widget _chartBody(List<Task> tasks, List<_Row> rows, DateTime first, int days, double width, double nameW,
      bool narrow, DateTime now, double Function(DateTime) xOf) {
    final scheme = Theme.of(context).colorScheme;

    // Where each task's bar sits, for the arrows.
    final rowTop = <String, double>{};
    // Item 85: arrows between steps that come after other steps, for opened-out tasks.
    final stepTop = <String, (Task, TaskStep, double)>{};
    var y = 0.0;
    for (final r in rows) {
      if (r.task != null && r.step == null) rowTop[r.task!.id] = y;
      if (r.step != null) stepTop[r.step!.id] = (r.task!, r.step!, y + r.height / 2);
      y += r.height;
    }
    final stepArrows = <(double, double, double, double, bool)>[];
    for (final (t, s, y2) in stepTop.values) {
      final b = stepBar(t, s, data);
      if (b == null) continue;
      final clash = stepClashes(t, s, data);
      for (final p in stepsBefore(t, s)) {
        final from = stepTop[p.id];
        final a = stepBar(t, p, data);
        if (from == null || a == null) continue;
        stepArrows.add((xOf(a.end) + _dayW, from.$3, xOf(b.start), y2, clash));
      }
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
                    if (stepArrows.isNotEmpty)
                      Positioned.fill(child: CustomPaint(painter: _StepLinkPainter(stepArrows, scheme))),
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
                    showDay ? '${DateFormat('E').format(d).substring(0, 1)} ${d.day}' : (d.day % 7 == 1 && _dayW >= 10 ? '${d.day}' : ''),
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
      // Item 84: tap a category to zoom to its tasks.
      return Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: r.members.isEmpty ? null : () => _focusOn(_barsOf(r.members)),
          child: Container(
            height: r.height,
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: r.colour, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              Icon(Icons.fit_screen_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
      );
    }
    final t = r.task!;
    if (r.step != null) {
      final s = r.step!;
      final sb = stepBar(t, s, data);
      return InkWell(
        onTap: t.closedAt != null ? null : () => editStepPlan(context, store, t, s),
        child: SizedBox(
          height: r.height,
          child: Padding(
            padding: EdgeInsets.only(left: narrow ? 24 : 40, right: 8),
            child: Row(children: [
              Icon(s.done ? Icons.check : Icons.radio_button_unchecked, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(s.title, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
              if (!s.done && s.progress != null) Text('${s.progress}% ', style: theme.textTheme.labelSmall),
              if (sb != null && !stepIsPoint(s) && !narrow)
                Text('${workDays(sb.start, sb.end, weekends: weekendsFor(t, data))}d', style: theme.textTheme.labelSmall),
            ]),
          ),
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
    void focus() {
      setState(() => _expanded.add(t.id));
      _focusOn(_barsOf([t], steps: true), task: t.id);
    }

    return InkWell(
      onTap: () => _open(t),
      onLongPress: focus,
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
          if (!narrow)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Zoom to this task',
              icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
              onPressed: focus,
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
      final sb = stepBar(t, s, data);
      final open = t.closedAt != null ? null : () => editStepPlan(context, store, t, s);
      if (sb == null) {
        return SizedBox(
          height: r.height,
          width: width,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: open),
        );
      }
      final stepColour = s.done ? scheme.outline : colour;
      final children = <Widget>[];
      if (stepIsPoint(s)) {
        // A date only: a diamond on its day.
        children.add(Positioned(
          left: xOf(sb.start) + _dayW / 2 - 6,
          top: r.height / 2 - 6,
          child: GestureDetector(
            onTap: open,
            child: Transform.rotate(
              angle: pi / 4,
              child: Container(width: 12, height: 12, color: stepColour),
            ),
          ),
        ));
      } else {
        final w = max(sb.length * _dayW, _dayW);
        children.add(Positioned(
          left: xOf(sb.start),
          top: r.height / 2 - 7,
          width: w,
          height: 14,
          child: GestureDetector(
            onTap: open,
            child: Tooltip(
              message: '${s.title}\n${DateFormat('EEE d MMM').format(sb.start)} to '
                  '${DateFormat('EEE d MMM').format(sb.end)}${s.done ? ', done' : s.progress != null ? ', ${s.progress}% done' : ''}',
              child: Container(
                decoration: BoxDecoration(
                  color: stepColour.withValues(alpha: s.done ? 0.5 : 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: sb.guessedStart ? null : Border.all(color: stepColour),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(children: [
                  if (!s.done && s.share > 0)
                    FractionallySizedBox(widthFactor: s.share, heightFactor: 1, child: ColoredBox(color: stepColour)),
                  if (sb.late && !s.done)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: min(w, sb.lateDays * _dayW),
                        color: scheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ));
        final due = sb.due;
        if (due != null && daysBetween(due, sb.end) != 0) {
          children.add(Positioned(
            left: xOf(due) + _dayW - 1,
            top: r.height / 2 - 9,
            child: Container(width: 2, height: 18, color: sb.late ? scheme.error : scheme.onSurfaceVariant),
          ));
        }
      }
      return SizedBox(height: r.height, width: width, child: Stack(clipBehavior: Clip.none, children: children));
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
    // Item 75: a small tick under the bar for each day worked on it.
    for (final key in t.worked) {
      final d = DateTime.tryParse(key);
      if (d == null) continue;
      final x = xOf(d);
      if (x < 0 || x > width) continue;
      children.add(Positioned(
        left: x + _dayW / 2 - 2,
        top: 36,
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        ),
      ));
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

/// Item 85: arrows from the end of one step's bar to the start of a step that comes after it,
/// red when that one starts too early.
class _StepLinkPainter extends CustomPainter {
  _StepLinkPainter(this.arrows, this.scheme);

  final List<(double, double, double, double, bool)> arrows;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (x1, y1, x2, y2, clash) in arrows) {
      final paint = Paint()
        ..color = clash ? scheme.error : scheme.outline
        ..strokeWidth = clash ? 1.6 : 1.2
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(x1, y1);
      if (x2 - 8 >= x1 + 4) {
        path
          ..lineTo(x1 + 5, y1)
          ..lineTo(x1 + 5, y2)
          ..lineTo(x2 - 2, y2);
      } else {
        final drop = y1 + (y2 > y1 ? 12 : -12);
        path
          ..lineTo(x1 + 6, y1)
          ..lineTo(x1 + 6, drop)
          ..lineTo(x2 - 8, drop)
          ..lineTo(x2 - 8, y2)
          ..lineTo(x2 - 2, y2);
      }
      canvas.drawPath(path, paint);
      canvas.drawPath(
          Path()
            ..moveTo(x2, y2)
            ..lineTo(x2 - 6, y2 - 3.5)
            ..lineTo(x2 - 6, y2 + 3.5)
            ..close(),
          Paint()..color = paint.color);
    }
  }

  @override
  bool shouldRepaint(_StepLinkPainter old) => true;
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

/// Item 72: a step's start day and days of work for the chart, asked in one small dialog. Also
/// used from the step menu on the task page.
Future<void> editStepPlan(BuildContext context, AppStore store, Task t, TaskStep s) async {
  final now = DateTime.now();
  final fmt = DateFormat('EEE d MMM');
  DateTime? start = s.startAt;
  int? takes = s.takesDays;
  var progress = s.done ? 100 : s.progress ?? 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final preview = stepBar(t, TaskStep(id: s.id, title: s.title, dueAt: s.dueAt, startAt: start, takesDays: takes), store.data);
        return AlertDialog(
          title: Text(s.title),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_arrow_outlined),
              title: const Text('Starts'),
              subtitle: Text(start == null ? 'Not set' : fmt.format(start!)),
              trailing: start == null
                  ? null
                  : IconButton(tooltip: 'Clear', icon: const Icon(Icons.clear), onPressed: () => set(() => start = null)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: c,
                  helpText: 'When does "${s.title}" start?',
                  initialDate: start ?? (t.startAt != null ? dayOf(t.startAt!) : dayOf(now)),
                  firstDate: DateTime(now.year - 3),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) set(() => start = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timelapse),
              title: Text(takes == null ? 'Takes: not set' : 'Takes $takes day${takes == 1 ? '' : 's'} of work'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Fewer days',
                  icon: const Icon(Icons.remove),
                  onPressed: takes == null ? null : () => set(() => takes = takes! <= 1 ? null : takes! - 1),
                ),
                IconButton(
                  tooltip: 'More days',
                  icon: const Icon(Icons.add),
                  onPressed: () => set(() => takes = (takes ?? 0) + 1),
                ),
              ]),
            ),
            if (!s.done) ...[
              Text('Progress: $progress%'),
              Slider(
                value: progress.toDouble(),
                max: 100,
                divisions: 20,
                label: '$progress%',
                onChanged: (v) => set(() => progress = v.round()),
              ),
            ],
            if (s.dueAt != null) Text('Due ${fmt.format(s.dueAt!)}'),
            if (preview != null && (start != null || takes != null))
              Text(
                'On the chart: ${fmt.format(preview.start)} to ${fmt.format(preview.end)}'
                '${preview.late ? ', ${preview.lateDays} day${preview.lateDays == 1 ? '' : 's'} after due' : ''}',
                style: Theme.of(c).textTheme.bodySmall,
              ),
            if (preview == null)
              Text('Give it a start date (or a due date) to show it on the chart.', style: Theme.of(c).textTheme.bodySmall),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        );
      },
    ),
  );
  if (ok == true) store.setStepPlan(t, s, start: start, takes: takes, progress: s.done ? s.progress : progress);
}
