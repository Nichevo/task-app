import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../critical_path.dart';
import '../gantt.dart';
import '../models.dart';
import '../store.dart';

/// Item 114 D: tap a bar on the Gantt chart: when should it happen (as soon as possible, as late
/// as possible, on a date, must finish by), a few quick moves, and the way to open it.
Future<void> showTimingSheet(
  BuildContext context,
  AppStore store,
  Task t, {
  TaskStep? step,
  CpNode? node,
  required VoidCallback onOpen,
  Future<void> Function(Map<Task, int> plan)? afterMove,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => _TimingSheet(store: store, task: t, step: step, node: node, onOpen: onOpen, afterMove: afterMove),
  );
}

class _TimingSheet extends StatefulWidget {
  const _TimingSheet({required this.store, required this.task, this.step, this.node, required this.onOpen, this.afterMove});

  final AppStore store;
  final Task task;
  final TaskStep? step;
  final CpNode? node;
  final VoidCallback onOpen;
  final Future<void> Function(Map<Task, int> plan)? afterMove;

  @override
  State<_TimingSheet> createState() => _TimingSheetState();
}

class _TimingSheetState extends State<_TimingSheet> {
  AppStore get store => widget.store;
  AppData get data => store.data;
  Task get t => widget.task;
  TaskStep? get s => widget.step;

  String get _title => s?.title ?? t.title;
  Timing? get _timing => Timing.byId(s?.timing ?? t.timing);

  /// What it comes after, and what comes after it.
  (List<String>, List<String>) _links() {
    final step = s;
    if (step != null) {
      return (
        [for (final b in stepsBefore(t, step)) b.title],
        [for (final f in t.steps) if (f.afterIds.contains(step.id)) f.title],
      );
    }
    return (
      [for (final id in t.afterIds) ?anyTask(data, id)?.title],
      [for (final f in data.active) if (f.afterIds.contains(t.id)) f.title],
    );
  }

  Future<void> _move(int days) async {
    final step = s;
    if (step != null) {
      final bar = stepBar(t, step, data);
      if (bar == null) return;
      store.setStepPlan(t, step,
          start: addDays(bar.start, days), takes: step.takesDays, minutes: step.takesMinutes,
          progress: step.progress);
      if (step.dueAt != null && step.startAt != null) {
        step.dueAt = addDays(step.dueAt!, days);
        store.changed(task: t);
      }
    } else {
      final plan = store.moveOnGantt(t, days);
      await widget.afterMove?.call(plan);
    }
    if (mounted) setState(() {});
  }

  void _takes(int delta) {
    final step = s;
    if (step != null) {
      final bar = stepBar(t, step, data);
      final now = step.takesDays ?? bar?.length ?? 1;
      store.setStepPlan(t, step, start: step.startAt, takes: (now + delta).clamp(1, 999), progress: step.progress);
    } else {
      final now = t.takesDays ?? barFor(t, data)?.length ?? 1;
      t.takesDays = (now + delta).clamp(1, 999);
      t.takesMinutes = null;
      store.ganttChanged(t);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final (before, after) = _links();
    final n = widget.node;
    final bar = s == null ? barFor(t, data) : stepBar(t, s!, data);
    final fmt = DateFormat('EEE d MMM');
    final days = s == null ? t.takesDays : s!.takesDays;
    final about = [
      if (n != null) n.slack < 0 ? '${-n.slack} days late' : n.critical ? 'critical: no spare time' : '${n.slack} days spare',
      if (bar != null) '${fmt.format(bar.start)} to ${fmt.format(bar.end)}',
      if (before.isNotEmpty) 'comes after ${before.join(', ')}',
      if (after.isNotEmpty) '${after.join(', ')} come${after.length == 1 ? 's' : ''} after it',
    ].join(' · ');
    final current = _timing;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(_title, style: theme.textTheme.titleLarge),
          if (about.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(about, style: hint)),
          const SizedBox(height: 14),
          Text('When should it happen?', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 6),
          for (final x in Timing.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: x == current ? theme.colorScheme.secondaryContainer : theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: x == current ? theme.colorScheme.primary : Colors.transparent, width: 1.5),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(switch (x) {
                    Timing.asap => Icons.fast_forward_outlined,
                    Timing.alap => Icons.fast_rewind_outlined,
                    Timing.fixed => Icons.push_pin_outlined,
                    Timing.finishBy => Icons.sports_score_outlined,
                  }),
                  title: Text(x.label),
                  subtitle: Text(x.hint),
                  selected: x == current,
                  onTap: () {
                    store.setTiming(t, s, x);
                    setState(() {});
                  },
                ),
              ),
            ),
          if (current == null)
            Text('Now: its own dates, moved later only when what it comes after runs late.', style: hint),
          const SizedBox(height: 10),
          Text('Quick moves', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton(onPressed: bar == null ? null : () => _move(-1), child: const Text('−1 day')),
            OutlinedButton(onPressed: bar == null ? null : () => _move(1), child: const Text('+1 day')),
            OutlinedButton(onPressed: (days ?? bar?.length ?? 1) <= 1 ? null : () => _takes(-1), child: const Text('Shorter')),
            OutlinedButton(onPressed: () => _takes(1), child: Text('Longer${days == null ? '' : ' (takes $days d)'}')),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onOpen();
              },
              child: Text(s == null ? 'Open task' : 'Edit step'),
            ),
          ]),
        ]),
      ),
    );
  }
}
