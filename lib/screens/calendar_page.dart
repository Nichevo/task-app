import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../stats.dart';
import '../store.dart';
import '../widgets/task_block.dart';
import '../widgets/task_colors.dart';
import 'task_page.dart';

/// Tasks by due date: a month grid (or a week strip) with coloured dots, and the chosen
/// day's tasks below it, or beside it on a wide screen. Drag a task onto a day to move it.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.store, this.initialDay});

  final AppStore store;
  final DateTime? initialDay;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _day = Stats.dayOf(widget.initialDay ?? DateTime.now());
  late DateTime _month = DateTime(_day.year, _day.month);
  bool _week = false;
  final _expanded = <String>{};

  AppStore get store => widget.store;
  AppData get data => store.data;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Open tasks due on each day in [from]..[to], plus faded future repeats.
  Map<DateTime, List<_Due>> _dueByDay(DateTime from, DateTime to) {
    final out = <DateTime, List<_Due>>{};
    void add(DateTime d, Task t, bool faded) =>
        out.putIfAbsent(_dayOf(d), () => []).add(_Due(t, faded));
    for (final t in data.active) {
      final due = t.dueAt;
      if (due == null) continue;
      if (!due.isBefore(from) && due.isBefore(to)) add(due, t, false);
      final r = t.repeat;
      if (r == null || r.fromCompletion) continue;
      var next = r.nextDue(due: due, completedAt: due);
      for (var i = 0; i < 60 && next.isBefore(to); i++) {
        if (!next.isBefore(from)) add(next, t, true);
        next = r.nextDue(due: next, completedAt: next);
      }
    }
    return out;
  }

  void _moveTo(Task t, DateTime day) {
    final old = t.dueAt ?? DateTime(day.year, day.month, day.day, 17);
    store.setDue(t, DateTime(day.year, day.month, day.day, old.hour, old.minute));
    setState(() => _day = day);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 700;
        final grid = _week ? _weekStrip() : _monthGrid();
        final dayList = _dayTasks();
        return Scaffold(
          appBar: AppBar(
            title: Text(_week ? 'Week of ${DateFormat('d MMM').format(_startOfWeek(_day))}' : DateFormat('MMMM yyyy').format(_month)),
            actions: [
              IconButton(tooltip: 'Previous', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
              IconButton(
                tooltip: 'Today',
                icon: const Icon(Icons.today),
                onPressed: () => setState(() {
                  _day = _dayOf(DateTime.now());
                  _month = DateTime(_day.year, _day.month);
                }),
              ),
              IconButton(tooltip: 'Next', icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
              IconButton(
                tooltip: _week ? 'Month view' : 'Week view',
                icon: Icon(_week ? Icons.calendar_view_month : Icons.calendar_view_week),
                onPressed: () => setState(() => _week = !_week),
              ),
            ],
          ),
          body: wide
              ? Row(children: [
                  Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(8), child: grid)),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 2, child: dayList),
                ])
              : Column(children: [
                  Padding(padding: const EdgeInsets.all(8), child: grid),
                  const Divider(height: 1),
                  Expanded(child: dayList),
                ]),
        );
      }),
    );
  }

  void _shift(int n) => setState(() {
        if (_week) {
          _day = _day.add(Duration(days: 7 * n));
          _month = DateTime(_day.year, _day.month);
        } else {
          _month = DateTime(_month.year, _month.month + n);
          _day = DateTime(_month.year, _month.month, 1);
        }
      });

  static DateTime _startOfWeek(DateTime d) => _dayOf(d).subtract(Duration(days: d.weekday - 1));

  Widget _monthGrid() {
    final first = _month;
    final start = _startOfWeek(first);
    final end = DateTime(first.year, first.month + 1, 1);
    final weeks = ((end.difference(start).inDays + 6) / 7).ceil();
    final due = _dueByDay(start, start.add(Duration(days: 7 * weeks)));
    return Column(children: [
      Row(children: [
        for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
          Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)))),
      ]),
      for (var w = 0; w < weeks; w++)
        Row(children: [
          for (var i = 0; i < 7; i++) Expanded(child: _cell(start.add(Duration(days: 7 * w + i)), due, 48, dim: true)),
        ]),
    ]);
  }

  Widget _weekStrip() {
    final start = _startOfWeek(_day);
    final due = _dueByDay(start, start.add(const Duration(days: 7)));
    return Row(children: [
      for (var i = 0; i < 7; i++) Expanded(child: _cell(start.add(Duration(days: i)), due, 72)),
    ]);
  }

  Widget _cell(DateTime day, Map<DateTime, List<_Due>> due, double height, {bool dim = false}) {
    final now = DateTime.now();
    final today = _dayOf(now);
    final items = due[day] ?? const [];
    final selected = day == _day;
    final outside = dim && day.month != _month.month;
    final overdue = items.any((d) => !d.faded && d.task.dueAt!.isBefore(now));
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => true,
      onAcceptWithDetails: (d) => _moveTo(d.data, day),
      builder: (context, candidates, _) => InkWell(
        onTap: () => setState(() {
          _day = day;
          _month = DateTime(day.year, day.month);
        }),
        child: Container(
          height: height,
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primaryContainer
                : selected
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
            border: day == today ? Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: day == today ? FontWeight.bold : null,
                color: outside ? Theme.of(context).disabledColor : (overdue ? const Color(0xFFC62828) : null),
              ),
            ),
            if (items.isNotEmpty)
              Wrap(spacing: 2, children: [
                for (final d in items.take(4))
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: d.faded
                          ? Theme.of(context).disabledColor.withValues(alpha: 0.4)
                          : ageColor(d.task, data.hoursToRed, byDue: data.colourByDue, now: now),
                    ),
                  ),
                if (items.length > 4) const Text('+', style: TextStyle(fontSize: 9)),
              ]),
          ]),
        ),
      ),
    );
  }

  Widget _dayTasks() {
    final now = DateTime.now();
    final items = _dueByDay(_day, _day.add(const Duration(days: 1)))[_day] ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(DateFormat('EEEE d MMMM').format(_day), style: Theme.of(context).textTheme.titleMedium),
      ),
      Expanded(
        child: items.isEmpty
            ? Center(child: Text('Nothing due. Drag a task onto a day to move it here.',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)))
            : ListView(children: [
                for (final d in items)
                  LongPressDraggable<Task>(
                    data: d.task,
                    feedback: Material(
                      elevation: 4,
                      child: SizedBox(width: 240, child: Padding(padding: const EdgeInsets.all(12), child: Text(d.task.title))),
                    ),
                    child: Opacity(
                      opacity: d.faded ? 0.5 : 1,
                      child: TaskBlock(
                        task: d.task,
                        color: ageColor(d.task, data.hoursToRed, byDue: data.colourByDue, now: now),
                        categoryName: data.category(d.task.categoryId)?.name,
                        expanded: _expanded.contains(d.task.id),
                        onTap: () => setState(() =>
                            _expanded.contains(d.task.id) ? _expanded.remove(d.task.id) : _expanded.add(d.task.id)),
                        onOpen: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: d.task))),
                        onCheck: d.faded ? null : () => store.complete(d.task),
                        onStep: (s) => store.toggleStep(d.task, s),
                        trailing: d.faded
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Tooltip(message: 'A later repeat', child: Icon(Icons.repeat, size: 18, color: Color(0x99000000))))
                            : const SizedBox(width: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: Text('Long-press a task and drop it on another day to move it.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                ),
              ]),
      ),
    ]);
  }
}

class _Due {
  const _Due(this.task, this.faded);
  final Task task;

  /// A future occurrence of a repeating task, not the task itself.
  final bool faded;
}
