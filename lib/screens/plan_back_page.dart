import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../critical_path.dart';
import '../gantt.dart';
import '../models.dart';
import '../store.dart';

/// Item 114 D: Plan back from the due date. From the task's finish date, works out each open
/// step's latest start (or, switched, its earliest start from today) using the step links,
/// lengths and the weekend setting, and sets them all in one go.
class PlanBackPage extends StatefulWidget {
  const PlanBackPage({super.key, required this.store, required this.task, this.today});

  final AppStore store;
  final Task task;

  /// For tests.
  final DateTime? today;

  @override
  State<PlanBackPage> createState() => _PlanBackPageState();
}

class _PlanBackPageState extends State<PlanBackPage> {
  AppStore get store => widget.store;
  Task get t => widget.task;
  late DateTime _finish = _defaultFinish();
  bool _latest = true;

  DateTime get _today => dayOf(widget.today ?? DateTime.now());

  DateTime _defaultFinish() {
    final due = t.dueAt;
    if (due != null) return due;
    final d = addDays(_today, 14);
    return DateTime(d.year, d.month, d.day, 17);
  }

  CpResult _plan() {
    final items = stepItems(t, store.data, undated: true);
    final weekends = weekendsFor(t, store.data);
    return criticalPath(items, weekends: weekends, from: _today, anchor: _finish);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('EEE d MMM');
    final r = _plan();
    final open = [for (final n in r.order) if (!n.item.done) n];
    final startBy = r.startBy;
    final spare = startBy == null ? 0 : workGap(_today, startBy, weekends: r.weekends);
    final late = spare < 0;
    final work = open.fold(0, (a, n) => a + n.item.days);
    final setting = open.where((n) => n.critical).length;
    final links = t.steps.any((s) => s.afterIds.isNotEmpty);
    DateTime startOf(CpNode n) => _latest ? n.ls : n.es;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan back from the due date')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: late ? theme.colorScheme.errorContainer : const Color(0xFF16323F),
            borderRadius: BorderRadius.circular(16),
          ),
          child: DefaultTextStyle(
            style: TextStyle(color: late ? theme.colorScheme.onErrorContainer : Colors.white),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('START NO LATER THAN', style: TextStyle(fontSize: 11, letterSpacing: 1)),
                  Text(startBy == null ? '–' : DateFormat('EEE d').format(startBy),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
                  Text(
                    startBy == null
                        ? 'no open steps'
                        : late
                            ? '${-spare} working day${spare == -1 ? '' : 's'} too late already'
                            : spare == 0
                                ? 'that\'s today · no days spare'
                                : '$spare working day${spare == 1 ? '' : 's'} spare',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ]),
              ),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    helpText: 'When must it be finished?',
                    initialDate: dayOf(_finish),
                    firstDate: DateTime(_today.year - 1),
                    lastDate: DateTime(_today.year + 5),
                  );
                  if (d != null) setState(() => _finish = DateTime(d.year, d.month, d.day, _finish.hour, _finish.minute));
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('FINISH BY', style: TextStyle(fontSize: 11, letterSpacing: 1, color: Color(0xFFFFA45C))),
                  Text(fmt.format(_finish), style: const TextStyle(fontSize: 20)),
                  Text('${t.dueAt == null ? 'pick a date' : 'due date'} · tap to change', style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${open.length} step${open.length == 1 ? '' : 's'} · $work day${work == 1 ? '' : 's'} of work · '
          '$setting set${setting == 1 ? 's' : ''} the start (red). The rest can move inside their spare time.'
          '${links ? '' : ' Link steps (After…) to chain them; unlinked steps can all run side by side.'}',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        for (final n in open)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(n.item.title),
            subtitle: Text(
              n.critical ? 'sets the start' : '${n.slack} d flexible',
              style: TextStyle(color: n.critical ? theme.colorScheme.error : null),
            ),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmt.format(startOf(n)), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${n.item.days} d', style: theme.textTheme.bodySmall),
            ]),
          ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Latest starts')),
            ButtonSegment(value: false, label: Text('Earliest starts')),
          ],
          selected: {_latest},
          onSelectionChanged: (v) => setState(() => _latest = v.first),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          FilledButton(
            onPressed: open.isEmpty
                ? null
                : () {
                    if (t.dueAt == null || dayOf(t.dueAt!) != dayOf(_finish)) t.dueAt = _finish;
                    store.setStepDates(t, {for (final n in open) n.item.id: startOf(n)}, {for (final n in open) n.item.id: n.item.days});
                    Navigator.pop(context, true);
                  },
            child: const Text('Set these dates'),
          ),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ]),
      ]),
    );
  }
}
