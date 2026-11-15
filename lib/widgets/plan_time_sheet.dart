import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../day_plan.dart';
import '../models.dart';
import '../store.dart';
import '../task_list.dart' show parseEstimate;
import '../screens/settings_page.dart' show askText;

/// Item 101: "Plan a time": the day, start, length (in time steps), the gap after it and whether
/// it leaves room for other tasks. Gives [task] (or its [step]) a new planned time, or changes
/// [slot]. [day] and [start] preset a new one (a drop on the timeline, say). Returns true when
/// something changed.
Future<bool> showPlanTimeSheet(
  BuildContext context,
  AppStore store,
  Task task, {
  TaskStep? step,
  TimeSlot? slot,
  DateTime? day,
  DateTime? start,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _PlanSheet(store: store, task: task, step: step, slot: slot, day: day, start: start),
  );
  return changed ?? false;
}

class _PlanSheet extends StatefulWidget {
  const _PlanSheet({required this.store, required this.task, this.step, this.slot, this.day, this.start});

  final AppStore store;
  final Task task;
  final TaskStep? step;
  final TimeSlot? slot;
  final DateTime? day;
  final DateTime? start;

  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  AppData get data => widget.store.data;
  DayPlanSettings get s => data.dayPlan;

  late DateTime _start;
  late int _minutes;
  int? _gap;
  bool _shared = false;

  static const _lengths = [15, 30, 45, 60, 90, 120, 180, 240];

  TaskStep? get _step =>
      widget.step ?? (widget.slot?.stepId == null ? null : widget.task.steps.where((x) => x.id == widget.slot!.stepId).firstOrNull);

  @override
  void initState() {
    super.initState();
    final sl = widget.slot;
    if (sl != null) {
      _start = sl.start;
      _minutes = sl.minutes;
      _gap = sl.gapAfter;
      _shared = sl.shared;
      return;
    }
    _minutes = widget.step == null ? widget.task.estimate ?? s.length : s.length;
    final now = DateTime.now();
    final day = widget.day ?? widget.start ?? now;
    if (widget.start != null) {
      _start = snapTime(widget.start!, s.snap);
    } else {
      final today = DateUtils.isSameDay(day, now);
      final from = today ? snapUp(now, s.snap) : null;
      _start = layoutDay(data, day).firstFree(_minutes, from: from) ??
          (from ?? DateTime(day.year, day.month, day.day).add(Duration(minutes: s.workStart)));
    }
  }

  DateTime get _day => DateTime(_start.year, _start.month, _start.day);
  DateTime get _end => _start.add(Duration(minutes: _minutes));

  void _setDay(DateTime d) => setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));

  /// What this time clashes with on that day (bands that leave room don't count, nor this one).
  List<PlanBlock> _clashes() => [
        for (final b in blocksOn(data, _day))
          if (!identical(b.slot, widget.slot) &&
              !b.shared &&
              !_shared &&
              !b.done &&
              b.start.isBefore(_end) &&
              _start.isBefore(b.end) &&
              !(identical(b.task, widget.task) && (b.step == null) != (_step == null)))
            b,
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hm = DateFormat('HH:mm');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 0; i < 6; i++) today.add(Duration(days: i))];
    if (!days.contains(_day)) days.insert(0, _day);
    final clashes = _clashes();
    final gapDefault = s.gapMinutes;
    final step = _step;
    // Free time on that day without this one, for the "first free gap" button.
    final layout = layoutDay(data, _day);
    final firstFree = layout.firstFree(_minutes, from: DateUtils.isSameDay(_day, now) ? snapUp(now, s.snap) : null);

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t, style: theme.textTheme.labelLarge?.copyWith(color: theme.hintColor)),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.slot == null ? 'Plan a time' : 'Change the time', style: theme.textTheme.titleLarge),
          Text(step == null ? widget.task.title : '${step.title} · step of ${widget.task.title}',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.hintColor)),
          label('Day'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in days)
              ChoiceChip(
                label: Text(d == today
                    ? 'Today'
                    : d == today.add(const Duration(days: 1))
                        ? 'Tomorrow'
                        : DateFormat('EEE d').format(d)),
                selected: d == _day,
                onSelected: (_) => _setDay(d),
              ),
            ActionChip(
              avatar: const Icon(Icons.event, size: 18),
              label: const Text('Pick…'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _day,
                  firstDate: today.subtract(const Duration(days: 365)),
                  lastDate: today.add(const Duration(days: 3650)),
                );
                if (d != null) _setDay(d);
              },
            ),
          ]),
          label('Starts'),
          Row(children: [
            IconButton.outlined(
              tooltip: '${s.snap} min earlier',
              icon: const Icon(Icons.remove),
              onPressed: () => setState(() => _start = _start.subtract(Duration(minutes: s.snap))),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
                if (t != null) setState(() => _start = DateTime(_day.year, _day.month, _day.day, t.hour, t.minute));
              },
              child: Text(hm.format(_start), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400)),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: '${s.snap} min later',
              icon: const Icon(Icons.add),
              onPressed: () => setState(() => _start = _start.add(Duration(minutes: s.snap))),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text('ends ${hm.format(_end)}', style: TextStyle(color: theme.hintColor))),
          ]),
          label('Takes'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in {..._lengths, _minutes}.toList()..sort())
              ChoiceChip(label: Text(describeLength(m)), selected: m == _minutes, onSelected: (_) => setState(() => _minutes = m)),
            ActionChip(
              label: const Text('Other…'),
              onPressed: () async {
                final typed = await askText(context, 'Minutes (or e.g. 1.5h)', initial: '$_minutes');
                final m = parseEstimate(typed ?? '');
                if (m != null && m > 0) setState(() => _minutes = m);
              },
            ),
          ]),
          label('Gap after it'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(label: Text('Default ($gapDefault min)'), selected: _gap == null, onSelected: (_) => setState(() => _gap = null)),
            for (final g in [0, 5, 10, 15, 30])
              ChoiceChip(label: Text(g == 0 ? 'None' : '$g min'), selected: _gap == g, onSelected: (_) => setState(() => _gap = g)),
          ]),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Leave room for other tasks'),
            subtitle: const Text('For waiting time: things planned inside it aren\'t clashes, and its time still counts as free'),
            value: _shared,
            onChanged: (v) => setState(() => _shared = v),
          ),
          if (clashes.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(10)),
              child: Text(
                'Clashes with ${clashes.map((b) => '${b.title} (${hm.format(b.start)}–${hm.format(b.end)})').join(', ')}',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            )
          else
            Text('No clashes', style: TextStyle(color: theme.hintColor)),
          if (firstFree != null && firstFree != _start)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text('Use the first free gap (${hm.format(firstFree)})'),
                onPressed: () => setState(() => _start = firstFree),
              ),
            ),
          const SizedBox(height: 10),
          Row(children: [
            if (widget.slot != null)
              TextButton(
                onPressed: () {
                  widget.store.removeSlot(widget.task, widget.slot!);
                  Navigator.pop(context, true);
                },
                child: const Text('Remove time'),
              ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final sl = widget.slot;
                if (sl == null) {
                  widget.store.planTime(widget.task, _start, _minutes, step: widget.step, gap: _gap, shared: _shared);
                } else {
                  widget.store.updateSlot(widget.task, sl, start: _start, minutes: _minutes, gap: _gap ?? -1, shared: _shared);
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ]),
        ]),
      ),
    );
  }
}
