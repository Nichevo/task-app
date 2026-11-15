import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../day_plan.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/plan_time_sheet.dart';
import '../widgets/task_colors.dart';
import 'starred_page.dart' show pickTask;
import 'task_page.dart';

/// Item 101: the Day plan. One day as a timeline: tasks and steps with a planned time drawn as
/// blocks as tall as the time they take, the gaps kept after them, free time in working hours,
/// clashes side by side, and blocks that leave room as a band down the left with smaller things
/// on top. A week strip changes day; the "To plan" tray holds what hasn't got a time yet.
///
/// Also the Calendar page's Day mode: [onMode] then switches back to 'month' or 'week'.
class DayPlanPage extends StatefulWidget {
  const DayPlanPage({super.key, required this.store, this.initialDay, this.onMode});

  final AppStore store;
  final DateTime? initialDay;
  final ValueChanged<String>? onMode;

  @override
  State<DayPlanPage> createState() => _DayPlanPageState();
}

class _DayPlanPageState extends State<DayPlanPage> {
  late DateTime _day = dayStart(widget.initialDay ?? DateTime.now());
  final _scroll = ScrollController();
  final _timelineKey = GlobalKey();
  bool _trayOpen = false;

  // A block being moved (press and hold) or stretched (bottom edge), and by how far.
  PlanBlock? _moving;
  PlanBlock? _resizing;
  double _dy = 0;

  AppStore get store => widget.store;
  AppData get data => store.data;
  DayPlanSettings get s => data.dayPlan;

  static const _top = 12.0;
  static const _gutter = 52.0;
  static const _bandBar = 58.0;
  static const _frameBar = 34.0;

  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStart());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _ppm(BuildContext context) => MediaQuery.of(context).size.width >= 700 ? 1.3 : 1.5;

  /// The hours drawn: Settings' day, stretched to fit anything planned outside it.
  (int, int) _range(DayLayout l) {
    var a = s.dayStart, b = s.dayEnd;
    for (final x in l.all) {
      final st = x.start.hour * 60 + x.start.minute;
      final en = st + x.slot.minutes;
      a = min(a, st ~/ 60 * 60);
      b = max(b, min(24 * 60, (en + 59) ~/ 60 * 60));
    }
    return (a, max(b, a + 60));
  }

  void _scrollToStart() {
    if (!_scroll.hasClients || !mounted) return;
    final l = layoutDay(data, _day);
    final (from, _) = _range(l);
    final now = DateTime.now();
    final target = DateUtils.isSameDay(now, _day)
        ? now.hour * 60 + now.minute - 45
        : l.blocks.isNotEmpty
            ? l.blocks.first.start.hour * 60 + l.blocks.first.start.minute - 20
            : s.workStart - 20;
    _scroll.jumpTo(((target - from) * _ppm(context)).clamp(0.0, _scroll.position.maxScrollExtent));
  }

  void _goTo(DateTime d) {
    setState(() => _day = dayStart(d));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStart());
  }

  Color _colour(Task t) => ageColor(t, data.hoursToRed, byDue: data.colourByDue);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 840;
        final layout = layoutDay(data, _day);
        final tray = trayFor(data, _day);
        return Scaffold(
          appBar: AppBar(
            title: Text('Day plan · ${DateFormat(wide ? 'EEEE d MMMM' : 'EEE d MMM').format(_day)}'),
            actions: [
              IconButton(tooltip: 'Today', icon: const Icon(Icons.today), onPressed: () => _goTo(DateTime.now())),
              IconButton(tooltip: 'Plan a task', icon: const Icon(Icons.add), onPressed: _planAny),
              if (widget.onMode != null) ...[
                IconButton(
                  tooltip: 'Week view',
                  icon: const Icon(Icons.calendar_view_week),
                  onPressed: () => widget.onMode!('week'),
                ),
                IconButton(
                  tooltip: 'Month view',
                  icon: const Icon(Icons.calendar_view_month),
                  onPressed: () => widget.onMode!('month'),
                ),
              ],
              PopupMenuButton<DayShow>(
                tooltip: 'Show',
                icon: const Icon(Icons.filter_list),
                initialValue: s.show,
                onSelected: (v) {
                  s.show = v;
                  store.dayPlanChanged();
                },
                itemBuilder: (_) => [
                  for (final v in DayShow.values)
                    CheckedPopupMenuItem(
                      value: v,
                      checked: s.show == v,
                      child: Text(switch (v) {
                        DayShow.both => 'Tasks and steps',
                        DayShow.tasks => 'Tasks only',
                        DayShow.steps => 'Steps only',
                      }),
                    ),
                ],
              ),
            ],
          ),
          body: Column(children: [
            _weekStrip(context),
            _summary(context, layout),
            _categoryChips(context),
            Expanded(
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: 300, child: _trayPanel(context, tray)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _timeline(context, layout)),
                    ])
                  : _timeline(context, layout),
            ),
            if (!wide) _trayBar(context, tray),
          ]),
        );
      }),
    );
  }

  // --- Week strip and summary ---

  Widget _weekStrip(BuildContext context) {
    final theme = Theme.of(context);
    final monday = _day.subtract(Duration(days: _day.weekday - 1));
    final today = dayStart(DateTime.now());
    final workHours = (s.workEnd - s.workStart) / 60;
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 200) _goTo(_day.add(Duration(days: v < 0 ? 7 : -7)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Week before',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goTo(_day.subtract(const Duration(days: 7))),
          ),
          for (var i = 0; i < 7; i++)
            Expanded(child: Builder(builder: (context) {
              final d = monday.add(Duration(days: i));
              final selected = d == _day;
              final load = dayLoad(data, d);
              final fg = selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
              final over = load > 1;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _goTo(d),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: selected ? theme.colorScheme.primary : null,
                    border: d == today && !selected ? Border.all(color: theme.colorScheme.primary) : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(children: [
                    Text(DateFormat('EEE').format(d), style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.75))),
                    Text('${d.day}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: fg)),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: load.clamp(0, 1).toDouble(),
                          minHeight: 4,
                          backgroundColor: fg.withValues(alpha: 0.15),
                          color: over ? const Color(0xFFD32F2F) : (selected ? theme.colorScheme.onPrimary : theme.colorScheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(load == 0 ? '–' : '${(load * workHours * 2).round() / 2} h'.replaceAll('.0 h', ' h'),
                        style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.75))),
                  ]),
                ),
              );
            })),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Week after',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goTo(_day.add(const Duration(days: 7))),
          ),
        ]),
      ),
    );
  }

  Widget _summary(BuildContext context, DayLayout l) {
    final theme = Theme.of(context);
    Widget chip(String t, {bool strong = false, bool bad = false}) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: strong ? theme.colorScheme.secondaryContainer : null,
            border: Border.all(color: bad ? theme.colorScheme.error : theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(t, style: TextStyle(fontSize: 12.5, color: bad ? theme.colorScheme.error : null)),
        );
    return SizedBox(
      height: 32,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
        chip('Planned ${describeLength(l.plannedMinutes)}', strong: true),
        chip('Free ${describeLength(l.freeMinutes)}'),
        if (l.sharedMinutes > 0) chip('Shared time ${describeLength(l.sharedMinutes)}'),
        if (l.clashes > 0) chip('${l.clashes} clashing', bad: true),
        if (l.hiddenMinutes > 0) chip('Hidden ${describeLength(l.hiddenMinutes)}'),
      ]),
    );
  }

  /// Item 101: categories to show, more than one at a time; remembered.
  Widget _categoryChips(BuildContext context) {
    if (data.categories.isEmpty) return const SizedBox(height: 6);
    final hidden = s.hiddenCategories;
    void toggle(String id) {
      hidden.contains(id) ? hidden.remove(id) : hidden.add(id);
      store.dayPlanChanged();
    }

    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), children: [
        for (final c in data.categories)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(c.name),
              selected: !hidden.contains(c.id),
              onSelected: (_) => toggle(c.id),
            ),
          ),
        FilterChip(
          visualDensity: VisualDensity.compact,
          label: const Text('No category'),
          selected: !hidden.contains(''),
          onSelected: (_) => toggle(''),
        ),
      ]),
    );
  }

  // --- The timeline ---

  Widget _timeline(BuildContext context, DayLayout l) {
    final theme = Theme.of(context);
    final ppm = _ppm(context);
    final (from, to) = _range(l);
    final height = (to - from) * ppm + _top * 2;
    double y(DateTime t) => (t.hour * 60 + t.minute - from + (DateUtils.isSameDay(t, _day) ? 0 : 24 * 60)) * ppm + _top;
    double h(int minutes) => minutes * ppm;
    final now = DateTime.now();
    return DragTarget<TrayItem>(
      onAcceptWithDetails: (d) {
        final box = _timelineKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(d.offset);
        final minutes = (local.dy - _top) / ppm + from;
        final start = snapTime(_day.add(Duration(minutes: minutes.round().clamp(0, 24 * 60 - s.snap))), s.snap);
        _planDropped(d.data, start);
      },
      builder: (context, candidates, _) => Container(
        color: candidates.isNotEmpty ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25) : null,
        child: SingleChildScrollView(
          controller: _scroll,
          child: LayoutBuilder(builder: (context, box) {
            final x0 = _gutter, x1 = box.maxWidth - 10;
            final children = <Widget>[];
            // Hour lines.
            for (var m = (from + 59) ~/ 60 * 60; m <= to; m += 60) {
              final top = (m - from) * ppm + _top;
              children.add(Positioned(
                left: 0,
                right: 0,
                top: top,
                child: Container(height: 1, color: theme.dividerColor.withValues(alpha: 0.35)),
              ));
              children.add(Positioned(
                left: 8,
                top: top - 8,
                child: Text('${(m ~/ 60).toString().padLeft(2, '0')}:00',
                    style: TextStyle(fontSize: 11, color: theme.hintColor)),
              ));
            }
            // Working hours shading at the edges.
            final ws = (s.workStart - from) * ppm + _top, we = (s.workEnd - from) * ppm + _top;
            if (ws > _top) {
              children.add(Positioned(left: x0, right: 10, top: 0, height: ws, child: ColoredBox(color: theme.hintColor.withValues(alpha: 0.05))));
            }
            if (we < height) {
              children.add(Positioned(left: x0, right: 10, top: we, bottom: 0, child: ColoredBox(color: theme.hintColor.withValues(alpha: 0.05))));
            }
            // Free time.
            for (final f in l.free) {
              final hh = h(f.minutes);
              final inBand = l.blocks.any((b) => b.shared && !b.hidden && b.start.isBefore(f.end) && f.start.isBefore(b.end));
              children.add(Positioned(
                left: inBand ? x0 + _bandBar + 6 : x0,
                width: x1 - x0 - (inBand ? _bandBar + 6 : 0),
                top: y(f.start) + 1,
                height: max(hh - 2, 4),
                child: CustomPaint(
                  painter: _DashedBox(theme.hintColor.withValues(alpha: 0.5)),
                  child: hh < 18
                      ? null
                      : Center(
                          child: Text(
                            f.minutes >= 30 ? 'Free ${describeLength(f.minutes)}' : describeLength(f.minutes),
                            style: TextStyle(fontSize: 12, color: theme.hintColor),
                          ),
                        ),
                ),
              ));
            }
            // Gaps after blocks.
            for (final g in l.gaps) {
              children.add(Positioned(
                left: x0,
                width: x1 - x0,
                top: y(g.start) + 1,
                height: max(h(g.minutes) - 2, 3),
                child: CustomPaint(painter: _Hatch(theme.hintColor.withValues(alpha: 0.22))),
              ));
            }
            // Bands first, so what sits on them is drawn on top.
            for (final b in l.blocks.where((b) => b.shared && !b.hidden)) {
              children.add(_positioned(b, x0, x1, y, h, (w, hh) => _band(context, b, hh)));
            }
            for (final b in l.blocks.where((b) => !b.shared || b.hidden)) {
              if (b.hidden) {
                children.add(_positioned(b, x0, x1, y, h, (w, hh) => _hiddenStrip(context, b, hh)));
                continue;
              }
              final left = b.inBand ? x0 + _bandBar + 6 : x0;
              final colW = (x1 - left) / b.columns;
              children.add(_positioned(b, left + colW * b.column, left + colW * (b.column + 1) - (b.column + 1 < b.columns ? 4 : 0), y, h,
                  (w, hh) => b.inside.isEmpty ? _block(context, b, hh) : _frame(context, b, hh)));
              for (final st in b.inside) {
                children.add(_positioned(st, left + colW * b.column + _frameBar + 4, left + colW * (b.column + 1) - 6, y, h,
                    (w, hh) => _block(context, st, hh)));
              }
            }
            if (DateUtils.isSameDay(now, _day)) {
              final ny = y(now);
              children.add(Positioned(
                left: x0 - 6,
                right: 0,
                top: ny - 5,
                height: 10,
                child: IgnorePointer(
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFD32F2F), shape: BoxShape.circle)),
                    Expanded(child: Container(height: 2, color: const Color(0xFFD32F2F))),
                  ]),
                ),
              ));
            }
            if (l.blocks.isEmpty) {
              children.add(Positioned(
                left: x0,
                right: 10,
                top: y(DateTime(_day.year, _day.month, _day.day).add(Duration(minutes: s.workStart))) + 40,
                child: Text(
                  'Nothing planned. Drag a task from the "To plan" tray onto a time, or use + to plan one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.hintColor),
                ),
              ));
            }
            return SizedBox(key: _timelineKey, height: height, child: Stack(clipBehavior: Clip.none, children: children));
          }),
        ),
      ),
    );
  }

  /// Places [b] between [left] and [right], moved or stretched while it is being dragged.
  Widget _positioned(PlanBlock b, double left, double right, double Function(DateTime) y, double Function(int) h,
      Widget Function(double w, double h) child) {
    var top = y(b.start);
    var hh = h(b.slot.minutes);
    final moving = identical(_moving, b) || (b.frame != null && identical(_moving, b.frame));
    if (moving) top += _dy;
    if (identical(_resizing, b)) hh = max(h(s.snap), hh + _dy);
    final w = max(right - left, 20.0);
    final widget = SizedBox(width: w, height: max(hh - 2, 14), child: child(w, max(hh - 2, 14)));
    return Positioned(
      left: left,
      top: top + 1,
      child: moving || identical(_resizing, b)
          ? Material(elevation: 6, borderRadius: BorderRadius.circular(12), color: Colors.transparent, child: widget)
          : widget,
    );
  }

  /// Taps, press-and-hold to move and the bottom edge to stretch.
  Widget _gestures(PlanBlock b, double hh, Widget child) {
    final ppm = _ppm(context);
    return GestureDetector(
      onTap: () => _blockMenu(b),
      onLongPressStart: (_) => setState(() {
        _moving = b;
        _dy = 0;
      }),
      onLongPressMoveUpdate: (d) => setState(() => _dy = d.offsetFromOrigin.dy),
      onLongPressEnd: (_) {
        final minutes = (_dy / ppm / s.snap).round() * s.snap;
        setState(() => _moving = null);
        if (minutes != 0) _shift(b, minutes);
      },
      onLongPressCancel: () => setState(() => _moving = null),
      child: Stack(children: [
        Positioned.fill(child: child),
        if (!b.done && hh >= 30)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 14,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => setState(() {
                _resizing = b;
                _dy = 0;
              }),
              onVerticalDragUpdate: (d) => setState(() => _dy += d.delta.dy),
              onVerticalDragEnd: (_) {
                final minutes = (_dy / ppm / s.snap).round() * s.snap;
                setState(() => _resizing = null);
                if (minutes != 0) _stretch(b, minutes);
              },
              child: Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  String _times(PlanBlock b) {
    final hm = DateFormat('HH:mm');
    return '${hm.format(b.start)} – ${hm.format(b.end)} · ${describeLength(b.slot.minutes)}';
  }

  Widget _tick(PlanBlock b) => SizedBox(
        width: 32,
        height: 32,
        child: Checkbox(
          value: b.done,
          side: const BorderSide(color: Colors.black54, width: 2),
          activeColor: Colors.black54,
          onChanged: (_) => _toggle(b),
        ),
      );

  Widget _block(BuildContext context, PlanBlock b, double hh) {
    final c = _colour(b.task);
    final step = b.step;
    final compact = hh < 52;
    const ink = Color(0xDD000000);
    final meta = [
      _times(b),
      if (step == null && b.task.steps.isNotEmpty && b.inside.isEmpty) '${b.task.stepsDone} of ${b.task.steps.length} steps',
      if (b.task.dueAt != null && b.task.dueAt!.isBefore(DateTime.now()) && b.task.closedAt == null) 'overdue',
    ].join(' · ');
    // A planned task shows its steps that have no time as a short checklist, room permitting.
    final unplanned = step != null || b.inside.isNotEmpty
        ? const <TaskStep>[]
        : b.task.steps.where((x) => !x.done && b.task.slotsOf(x).isEmpty).toList();
    final listRoom = ((hh - 64) / 26).floor();
    return _gestures(
      b,
      hh,
      Opacity(
        opacity: b.done ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: step != null ? BorderSide(color: Color.lerp(c, Colors.black, 0.35)!, width: 5) : BorderSide.none,
            ),
          ),
          foregroundDecoration: b.clash
              ? BoxDecoration(border: Border.all(color: const Color(0xFFD32F2F), width: 2.5), borderRadius: BorderRadius.circular(12))
              : null,
          padding: EdgeInsets.fromLTRB(10, compact ? 0 : 6, 2, 0),
          child: compact
              ? Row(children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: b.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        TextSpan(
                          text: '  ${DateFormat('HH:mm').format(b.start)}–${DateFormat('HH:mm').format(b.end)}'
                              '${step != null && b.frame == null ? ' · ${b.task.title}' : ''}',
                          style: const TextStyle(fontSize: 12, color: Color(0xAA000000)),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ink, decoration: TextDecoration.none),
                    ),
                  ),
                  if (b.clash) const _Tag('Clash'),
                  _tick(b),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (step != null && b.frame == null)
                        Text(b.task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                      Text(b.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: ink)),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                      if (b.clash && hh >= 80) const Padding(padding: EdgeInsets.only(top: 3), child: _Tag('Clash')),
                      if (listRoom > 0 && unplanned.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (final x in unplanned.take(unplanned.length > listRoom ? max(listRoom - 1, 1) : listRoom))
                              InkWell(
                                onTap: () => store.toggleStep(b.task, x),
                                child: SizedBox(
                                  height: 26,
                                  child: Row(children: [
                                    const Icon(Icons.check_box_outline_blank, size: 18, color: Colors.black54),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(x.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                                  ]),
                                ),
                              ),
                            if (unplanned.length > listRoom)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text('+ ${unplanned.length - max(listRoom - 1, 1)} more · no times',
                                    style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                              ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                  _tick(b),
                ]),
        ),
      ),
    );
  }

  /// A task whose steps are planned inside its time: a frame with its name up a strip on the
  /// left, and the steps drawn inside it.
  Widget _frame(BuildContext context, PlanBlock b, double hh) {
    final c = _colour(b.task);
    final noTime = b.task.steps.where((x) => !x.done && b.task.slotsOf(x).isEmpty).length;
    return _gestures(
      b,
      hh,
      Opacity(
        opacity: b.done ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.3),
            border: Border.all(color: c, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          foregroundDecoration: b.clash
              ? BoxDecoration(border: Border.all(color: const Color(0xFFD32F2F), width: 2.5), borderRadius: BorderRadius.circular(14))
              : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: _frameBar - 2,
              decoration: BoxDecoration(
                color: c,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
              child: Column(children: [
                _tick(b),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Center(
                      child: Text(
                        '${b.title} · ${b.task.stepsDone} of ${b.task.steps.length} steps',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: noTime == 0 || hh < 60
                  ? const SizedBox()
                  : Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 8, 16),
                        child: Text('$noTime step${noTime == 1 ? '' : 's'} without a time',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xAA000000))),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  /// A block that leaves room: a coloured band down the left with its name running up it.
  Widget _band(BuildContext context, PlanBlock b, double hh) {
    final c = _colour(b.task);
    return _gestures(
      b,
      hh,
      Opacity(
        opacity: b.done ? 0.5 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.16),
            border: Border.all(color: c, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: _bandBar - 2,
              color: c,
              child: Column(children: [
                _tick(b),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Center(
                      child: Text(
                        '${b.title} · ${_times(b)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            const Expanded(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(padding: EdgeInsets.all(6), child: _Tag('Leaves room')),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _hiddenStrip(BuildContext context, PlanBlock b, double hh) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _blockMenu(b),
      child: Container(
        decoration: BoxDecoration(
          color: theme.hintColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: hh < 16
            ? null
            : Text('Hidden · ${describeLength(b.slot.minutes)}',
                style: TextStyle(fontSize: 12, color: theme.hintColor), maxLines: 1),
      ),
    );
  }

  // --- The tray ---

  Widget _trayChip(BuildContext context, TrayItem i, {bool card = false}) {
    final theme = Theme.of(context);
    final c = _colour(i.task);
    final content = card
        ? Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: c, width: 6)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    [if (i.step != null) 'Step of ${i.task.title}', i.why, describeLength(i.minutes(data))].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ]),
              ),
              Icon(Icons.drag_indicator, color: theme.hintColor),
            ]),
          )
        : Container(
            margin: const EdgeInsets.only(right: 6, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: i.title),
              TextSpan(text: '  ${describeLength(i.minutes(data))}', style: const TextStyle(fontSize: 11, color: Color(0xAA000000))),
            ]), style: const TextStyle(fontSize: 13, color: Color(0xDD000000))),
          );
    return LongPressDraggable<TrayItem>(
      data: i,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 220,
          height: max(i.minutes(data) * _ppm(context), 30),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
          child: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: content),
      child: InkWell(onTap: () => _planTray(i), child: content),
    );
  }

  Widget _trayBar(BuildContext context, List<TrayItem> tray) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: tray.isEmpty ? null : () => setState(() => _trayOpen = !_trayOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
              child: Row(children: [
                Expanded(
                  child: Text(
                    tray.isEmpty ? 'Nothing waiting to be planned' : 'To plan for ${DateFormat('EEE d').format(_day)} (${tray.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (tray.isNotEmpty) Icon(_trayOpen ? Icons.expand_more : Icons.expand_less),
              ]),
            ),
          ),
          if (tray.isNotEmpty)
            _trayOpen
                ? ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Wrap(children: [for (final i in tray) _trayChip(context, i)]),
                    ),
                  )
                : SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                      children: [for (final i in tray) _trayChip(context, i)],
                    ),
                  ),
        ]),
      ),
    );
  }

  Widget _trayPanel(BuildContext context, List<TrayItem> tray) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainer,
      child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 16), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Text('To plan · drag onto a time', style: theme.textTheme.titleSmall),
        ),
        if (tray.isEmpty)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('Nothing waiting. Switch "On the Day plan" on a task, or plan one with +.',
                style: TextStyle(color: theme.hintColor)),
          ),
        for (final i in tray) _trayChip(context, i, card: true),
      ]),
    );
  }

  // --- Actions ---

  Future<void> _planAny() async {
    final t = await pickTask(context, data, title: 'Plan a time for');
    if (t == null || !mounted) return;
    await showPlanTimeSheet(context, store, t, day: _day);
  }

  Future<void> _planTray(TrayItem i) => showPlanTimeSheet(context, store, i.task, step: i.step, day: _day);

  void _planDropped(TrayItem i, DateTime start) {
    final slot = store.planTime(i.task, start, i.minutes(data), step: i.step);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Planned "${i.title}" at ${DateFormat('HH:mm').format(start)}'),
        action: SnackBarAction(label: 'Change', onPressed: () => showPlanTimeSheet(context, store, i.task, slot: slot)),
      ));
  }

  void _shift(PlanBlock b, int minutes) {
    final d = Duration(minutes: minutes);
    store.updateSlot(b.task, b.slot, start: b.start.add(d));
    // A task's steps planned inside it move with it.
    for (final st in b.inside) {
      store.updateSlot(st.task, st.slot, start: st.start.add(d));
    }
  }

  void _stretch(PlanBlock b, int minutes) {
    final to = max(s.snap, b.slot.minutes + minutes);
    store.updateSlot(b.task, b.slot, minutes: to);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('"${b.title}" now ends ${DateFormat('HH:mm').format(b.start.add(Duration(minutes: to)))}')));
  }

  Future<void> _toggle(PlanBlock b) async {
    final t = b.task;
    final messenger = ScaffoldMessenger.of(context);
    if (b.done) {
      if (b.step == null && t.closedAt != null) store.restore(t);
      store.untickSlot(t, b.slot);
      return;
    }
    int? index;
    Task? spawned;
    final r = store.tickSlot(t, b.slot, onComplete: (i, next) {
      index = i;
      spawned = next;
    });
    messenger.clearSnackBars();
    switch (r) {
      case SlotTick.step:
        break;
      case SlotTick.lastStep:
        if (!mounted) return;
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('All steps ticked'),
            content: Text('Tick off "${t.title}" too?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tick it off')),
            ],
          ),
        );
        if (yes == true && t.closedAt == null) {
          final i = data.active.indexOf(t);
          final next = store.complete(t);
          messenger.showSnackBar(SnackBar(
            content: Text('Ticked off "${t.title}"'),
            action: SnackBarAction(label: 'Undo', onPressed: () => store.uncomplete(t, i, next)),
          ));
        }
      case SlotTick.worked:
        messenger.showSnackBar(SnackBar(
          content: const Text('Counted as worked on today. More time is planned for it later.'),
          action: SnackBarAction(label: 'Undo', onPressed: () => store.untickSlot(t, b.slot)),
        ));
      case SlotTick.done:
        messenger.showSnackBar(SnackBar(
          content: Text('Ticked off "${t.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (index != null) store.uncomplete(t, index!, spawned);
              store.untickSlot(t, b.slot);
            },
          ),
        ));
    }
  }

  Future<void> _blockMenu(PlanBlock b) async {
    final theme = Theme.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(b.title, style: theme.textTheme.titleMedium),
            subtitle: Text([if (b.step != null) 'Step of ${b.task.title}', _times(b)].join(' · ')),
          ),
          ListTile(leading: const Icon(Icons.open_in_new), title: const Text('Open the task'), onTap: () => Navigator.pop(c, 'open')),
          ListTile(leading: const Icon(Icons.schedule), title: const Text('Change the time…'), onTap: () => Navigator.pop(c, 'time')),
          ListTile(
            leading: Icon(b.shared ? Icons.check_box : Icons.check_box_outline_blank),
            title: const Text('Leave room for other tasks'),
            subtitle: const Text('Things planned inside it aren\'t clashes'),
            onTap: () => Navigator.pop(c, 'shared'),
          ),
          ListTile(
            leading: Icon(b.done ? Icons.undo : Icons.check),
            title: Text(b.done ? 'Untick' : 'Tick'),
            onTap: () => Navigator.pop(c, 'tick'),
          ),
          ListTile(
            leading: const Icon(Icons.event_busy),
            title: const Text('Remove this time'),
            onTap: () => Navigator.pop(c, 'remove'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'open':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: b.task)));
      case 'time':
        await showPlanTimeSheet(context, store, b.task, slot: b.slot);
      case 'shared':
        store.updateSlot(b.task, b.slot, shared: !b.shared);
      case 'tick':
        await _toggle(b);
      case 'remove':
        store.removeSlot(b.task, b.slot);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('Removed "${b.title}" from ${DateFormat('HH:mm').format(b.start)}'),
            action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreSlot(b.task, b.slot)),
          ));
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: const Color(0xD01A1C1C), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
      );
}

/// Diagonal stripes: the gap kept after a block.
class _Hatch extends CustomPainter {
  _Hatch(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = colour
      ..strokeWidth = 3;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)));
    for (var x = -size.height; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Hatch old) => old.colour != colour;
}

/// A dashed rounded box: free time.
class _DashedBox extends CustomPainter {
  _DashedBox(this.colour);
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, min(d + 5, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.colour != colour;
}
