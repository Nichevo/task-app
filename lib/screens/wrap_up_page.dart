import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../daily_helpers.dart';
import '../models.dart';
import '../store.dart';
import '../task_list.dart' show describeMinutes;
import '../widgets/task_colors.dart';

/// Item 114 B: wrap up the day. What was done, what is still open from today (each moved on in
/// one tap) and a look at tomorrow.
class WrapUpPage extends StatefulWidget {
  const WrapUpPage({super.key, required this.store, this.onOpenDay});

  final AppStore store;

  /// Opens the Day plan on a day (tomorrow).
  final void Function(DateTime day)? onOpenDay;

  @override
  State<WrapUpPage> createState() => _WrapUpPageState();
}

class _WrapUpPageState extends State<WrapUpPage> {
  AppStore get store => widget.store;

  /// What happened to each task here, by id, shown greyed until the page is left.
  final _handled = <String, String>{};

  /// The tasks listed when the page opened, so one moved on stays listed (greyed).
  late final List<Task> _open;
  late final DateTime _today;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _open = leftOpen(store.data, _today);
  }

  DateTime get _tomorrow => DateTime(_today.year, _today.month, _today.day + 1);

  void _did(Task t, String what, VoidCallback undo) {
    setState(() => _handled[t.id] = what);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('${t.title}: $what'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            undo();
            setState(() => _handled.remove(t.id));
          },
        ),
      ));
  }

  Future<void> _pickDay(Task t) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _tomorrow,
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 365 * 2)),
    );
    if (d == null || !mounted) return;
    _did(t, 'moved to ${DateFormat('EEE d MMM').format(d)}', store.rollTask(t, _today, d));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final data = store.data;
        final done = doneOn(data, _today);
        final worked = [...data.active, ...data.archived]
            .fold(0, (a, t) => a + (t.focus[dayKey(_today)] ?? 0));
        final tItems = dayItems(data, _tomorrow);
        final tDue = dueOn(data, _tomorrow);
        final scheme = Theme.of(context).colorScheme;
        final hint = TextStyle(color: scheme.onSurfaceVariant);
        return Scaffold(
          appBar: AppBar(title: Text('Wrap up ${DateFormat('EEEE').format(_today)}')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Today: $done done${worked > 0 ? ' · ${describeMinutes(worked)} on the focus timer' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_open.isEmpty ? 'Nothing left from today' : 'Still open from today',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final t in _open) _card(context, t),
            const SizedBox(height: 16),
            Text('Tomorrow', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              [
                '${tItems.where((i) => i.meeting).length} meetings',
                '${tItems.where((i) => !i.meeting).length} planned',
                '${tDue.length} due',
              ].join(' · '),
              style: hint,
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              if (widget.onOpenDay != null)
                FilledButton.icon(
                  icon: const Icon(Icons.view_day_outlined),
                  label: const Text('Open tomorrow\'s Day plan'),
                  onPressed: () => widget.onOpenDay!(_tomorrow),
                ),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Finish')),
            ]),
          ]),
        );
      },
    );
  }

  Widget _card(BuildContext context, Task t) {
    final handled = _handled[t.id];
    final open = store.data.active.contains(t);
    final now = DateTime.now();
    final planned = t.slots.where((s) => s.doneAt == null && DateUtils.isSameDay(s.start, _today)).firstOrNull;
    final why = [
      if (t.dueAt != null)
        t.dueAt!.isBefore(_today) ? 'Overdue since ${DateFormat('EEE d MMM').format(t.dueAt!)}' : 'Due today',
      if (planned != null) 'Planned ${DateFormat('HH:mm').format(planned.start)}, not ticked',
    ].join(' · ');
    return Opacity(
      opacity: handled != null ? 0.55 : 1,
      child: Card(
        child: Container(
          decoration: BoxDecoration(
            border: Border(
                left: BorderSide(color: ageColor(t, store.data.hoursToRed, byDue: store.data.colourByDue, now: now), width: 6)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            Text(handled ?? why, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (handled == null && open) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                FilledButton.tonal(
                  onPressed: () => _did(t, 'moved to tomorrow', store.rollTask(t, _today, _tomorrow)),
                  child: const Text('Tomorrow'),
                ),
                OutlinedButton(onPressed: () => _pickDay(t), child: const Text('Pick day')),
                OutlinedButton(
                  onPressed: () {
                    final was = t.workedOn(_today);
                    store.setWorked(t, _today, true);
                    final undo = store.rollTask(t, _today, _tomorrow);
                    _did(t, 'worked on today, carried to tomorrow', () {
                      undo();
                      if (!was) store.setWorked(t, _today, false);
                    });
                  },
                  child: const Text('Worked on it'),
                ),
                OutlinedButton(
                  onPressed: () {
                    final index = store.data.active.indexOf(t);
                    final spawned = store.complete(t);
                    _did(t, 'done', () => store.uncomplete(t, index, spawned));
                  },
                  child: const Text('Done'),
                ),
                OutlinedButton(
                  onPressed: () {
                    final index = store.data.active.indexOf(t);
                    store.delete(t);
                    _did(t, 'dropped', () => store.undelete(t, index));
                  },
                  child: const Text('Drop'),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
