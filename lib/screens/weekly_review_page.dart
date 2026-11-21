import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../day_plan.dart' show describeLength;
import '../models.dart';
import '../store.dart';
import '../weekly_review.dart';
import '../widgets/task_colors.dart';

/// Item 114 E: the weekly review, one pile at a time. Empty piles are skipped.
class WeeklyReviewPage extends StatefulWidget {
  const WeeklyReviewPage({super.key, required this.store, this.onOpenTask, this.onPlanDay, this.now});

  final AppStore store;
  final void Function(Task t)? onOpenTask;

  /// Opens the Day plan on a day, to plan it (✨ Plan Monday).
  final void Function(DateTime day)? onPlanDay;

  /// For tests.
  final DateTime? now;

  @override
  State<WeeklyReviewPage> createState() => _WeeklyReviewPageState();
}

enum _Pile { last, slipped, ageing, stalled, next }

class _WeeklyReviewPageState extends State<WeeklyReviewPage> {
  AppStore get store => widget.store;
  AppData get data => store.data;
  late final DateTime _now = widget.now ?? DateTime.now();
  late final DateTime _today = DateTime(_now.year, _now.month, _now.day);

  late final List<Task> _slipped = slipped(data, _now);
  late final List<Task> _ageing = ageing(data, _now).take(15).toList();
  late final List<Task> _stalled = stalled(data, _now);
  late final LastWeek _last = lastWeek(data, _now);
  late final List<_Pile> _piles = [
    _Pile.last,
    if (_slipped.isNotEmpty) _Pile.slipped,
    if (_ageing.isNotEmpty) _Pile.ageing,
    if (_stalled.isNotEmpty) _Pile.stalled,
    _Pile.next,
  ];
  int _at = 0;

  /// What happened to each task here, by id, and the counts for the summary.
  final _handled = <String, String>{};
  final _tally = <String, int>{};
  final _started = DateTime.now();

  void _did(Task t, String what, String kind, VoidCallback undo) {
    setState(() {
      _handled[t.id] = what;
      _tally[kind] = (_tally[kind] ?? 0) + 1;
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('${t.title}: $what'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            undo();
            setState(() {
              _handled.remove(t.id);
              _tally[kind] = (_tally[kind] ?? 1) - 1;
            });
          },
        ),
      ));
  }

  DateTime _withTime(DateTime day, DateTime? like) => DateTime(day.year, day.month, day.day, like?.hour ?? 17, like?.minute ?? 0);

  /// Moves [t]'s due date (and planned times that day) to [day].
  void _moveTo(Task t, DateTime day, String what) {
    final due = t.dueAt;
    if (due == null) {
      final old = t.dueAt;
      store.setDue(t, _withTime(day, null));
      _did(t, what, 'moved', () => store.setDue(t, old));
    } else {
      _did(t, what, 'moved', store.rollTask(t, DateTime(due.year, due.month, due.day), day));
    }
  }

  Future<void> _pickDay(Task t) async {
    final d = await showDatePicker(
      context: context,
      initialDate: nextWeekStart(_now),
      firstDate: _today,
      lastDate: _today.add(const Duration(days: 365 * 2)),
    );
    if (d == null || !mounted) return;
    _moveTo(t, d, 'moved to ${DateFormat('EEE d MMM').format(d)}');
  }

  Future<void> _delegate(Task t) async {
    final c = TextEditingController(text: t.waitingOn ?? '');
    final who = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Who is doing it?'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Delegate')),
        ],
      ),
    );
    if (who == null || who.trim().isEmpty || !mounted) return;
    final box = t.matrixBox, waiting = t.waitingOn;
    store.setBox(t, MatrixBox.delegate);
    store.setWaitingOn(t, who);
    _did(t, 'delegated to ${who.trim()}', 'delegated', () {
      store.setBox(t, MatrixBox.byId(box));
      store.setWaitingOn(t, waiting);
    });
  }

  void _done(Task t) {
    final index = data.active.indexOf(t);
    final spawned = store.complete(t);
    _did(t, 'done', 'done', () => store.uncomplete(t, index, spawned));
  }

  void _drop(Task t) {
    final index = data.active.indexOf(t);
    store.delete(t);
    _did(t, 'dropped', 'dropped', () => store.undelete(t, index));
  }

  void _keep(Task t) {
    final was = t.workedOn(_today);
    store.setWorked(t, _today, true);
    _did(t, 'kept (fresh again)', 'kept', () {
      if (!was) store.setWorked(t, _today, false);
    });
  }

  void _thisWeek(Task t) {
    // Friday of the coming week.
    final start = nextWeekStart(_now);
    final fri = DateTime(start.year, start.month, start.day + (DateTime.friday - start.weekday + 7) % 7);
    _moveTo(t, fri, 'due ${DateFormat('EEE d MMM').format(fri)}');
  }

  String _title(_Pile p) => switch (p) {
        _Pile.last => 'Last week',
        _Pile.slipped => 'Slipped: ${_slipped.length} task${_slipped.length == 1 ? '' : 's'} passed their date',
        _Pile.ageing => 'Ageing: ${_ageing.length} without a date going ${_ageing.length == 1 ? 'red' : 'red or orange'}',
        _Pile.stalled => 'Stalled: ${_stalled.length} with no step ticked in 2 weeks',
        _Pile.next => 'Next week',
      };

  String _short(_Pile p) => switch (p) {
        _Pile.last => 'Last week',
        _Pile.slipped => 'Slipped',
        _Pile.ageing => 'Ageing',
        _Pile.stalled => 'Stalled',
        _Pile.next => 'Next week',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final pile = _piles[_at];
        final theme = Theme.of(context);
        final hint = TextStyle(color: theme.colorScheme.onSurfaceVariant);
        final last = _at == _piles.length - 1;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            title: const Text('Weekly review'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text('${_at + 1} of ${_piles.length}', style: hint)),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Row(children: [
              for (var i = 0; i < _piles.length; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= _at ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Text(_title(pile), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            ..._body(pile, hint),
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 6, children: [
              if (_at > 0) OutlinedButton(onPressed: () => setState(() => _at--), child: const Text('Back')),
              if (!last)
                FilledButton(
                  onPressed: () => setState(() => _at++),
                  child: Text('Next: ${_short(_piles[_at + 1])} →'),
                ),
              if (last && widget.onPlanDay != null && data.helperOn(Helper.planMyDay))
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: Text('Plan ${DateFormat('EEEE').format(nextWeekStart(_now))}'),
                  onPressed: () => widget.onPlanDay!(nextWeekStart(_now)),
                ),
              if (last) OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Finish')),
            ]),
          ]),
        );
      },
    );
  }

  List<Widget> _body(_Pile pile, TextStyle hint) {
    final fmt = DateFormat('EEE d MMM');
    switch (pile) {
      case _Pile.last:
        final l = _last;
        return [
          Text('${l.done} done · ${l.added} added${l.focusMinutes > 0 ? ' · ${describeLength(l.focusMinutes)} on the focus timer' : ''}',
              style: hint),
          const SizedBox(height: 10),
          if (l.doneTitles.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Done lately', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  for (final t in l.doneTitles) Text('✓ $t'),
                ]),
              ),
            ),
          Text(
            [
              if (_slipped.isNotEmpty) '${_slipped.length} slipped',
              if (_ageing.isNotEmpty) '${_ageing.length} ageing',
              if (_stalled.isNotEmpty) '${_stalled.length} stalled',
            ].isEmpty
                ? 'Nothing slipped, ageing or stalled. Next comes a look at next week.'
                : 'To look at: ${[
                    if (_slipped.isNotEmpty) '${_slipped.length} slipped',
                    if (_ageing.isNotEmpty) '${_ageing.length} ageing',
                    if (_stalled.isNotEmpty) '${_stalled.length} stalled',
                  ].join(', ')}.',
            style: hint,
          ),
        ];
      case _Pile.slipped:
        final next = nextWorkday(_now);
        return [
          Text('Pick what happens to each one.', style: hint),
          const SizedBox(height: 8),
          for (final t in _slipped)
            _card(t, 'Was due ${fmt.format(t.dueAt!)}', [
              FilledButton.tonal(
                onPressed: () => _moveTo(t, next, 'moved to ${DateFormat('EEEE').format(next)}'),
                child: Text(DateFormat('EEE').format(next)),
              ),
              OutlinedButton(
                onPressed: () => _moveTo(t, _nextMonday(), 'moved to next week'),
                child: const Text('Next week'),
              ),
              OutlinedButton(onPressed: () => _pickDay(t), child: const Text('Pick date')),
              OutlinedButton(onPressed: () => _delegate(t), child: const Text('Delegate')),
              OutlinedButton(onPressed: () => _drop(t), child: const Text('Drop')),
              OutlinedButton(onPressed: () => _done(t), child: const Text('Done')),
            ]),
        ];
      case _Pile.ageing:
        return [
          Text('No date and getting old. Give it one, keep it (fresh again), or let it go.', style: hint),
          const SizedBox(height: 8),
          for (final t in _ageing)
            _card(t, 'Added ${fmt.format(t.createdAt)}', [
              FilledButton.tonal(onPressed: () => _thisWeek(t), child: const Text('Do next week')),
              OutlinedButton(onPressed: () => _pickDay(t), child: const Text('Pick date')),
              OutlinedButton(onPressed: () => _keep(t), child: const Text('Keep')),
              OutlinedButton(onPressed: () => _drop(t), child: const Text('Drop')),
              OutlinedButton(onPressed: () => _done(t), child: const Text('Done')),
            ]),
        ];
      case _Pile.stalled:
        return [
          Text('Steps waiting, nothing ticked lately. Open one to see what is stuck.', style: hint),
          const SizedBox(height: 8),
          for (final t in _stalled)
            _card(t, '${t.stepsDone} of ${t.steps.length} steps${t.dueAt == null ? '' : ' · due ${fmt.format(t.dueAt!)}'}', [
              if (widget.onOpenTask != null) FilledButton.tonal(onPressed: () => widget.onOpenTask!(t), child: const Text('Open')),
              OutlinedButton(onPressed: () => _pickDay(t), child: const Text('Pick date')),
              OutlinedButton(onPressed: () => _drop(t), child: const Text('Drop')),
              OutlinedButton(onPressed: () => _done(t), child: const Text('Done')),
            ]),
        ];
      case _Pile.next:
        final week = nextWeek(data, _now);
        final due = week.fold(0, (a, d) => a + d.due);
        final meetings = week.fold(0, (a, d) => a + d.meetings);
        final work = week.fold(0, (a, d) => a + d.dueMinutes);
        final free = week.fold(0, (a, d) => a + d.freeMinutes);
        final took = DateTime.now().difference(_started).inMinutes;
        final tally = [
          for (final k in const ['moved', 'dropped', 'delegated', 'done', 'kept'])
            if ((_tally[k] ?? 0) > 0) '${_tally[k]} ${k == 'moved' ? 'rescheduled' : k == 'done' ? 'marked done' : k}',
        ];
        return [
          Text(
            '$due task${due == 1 ? '' : 's'} due · $meetings work meeting${meetings == 1 ? '' : 's'}'
            '${work > 0 ? ' · about ${describeLength(work)} of estimated work' : ''} in ${describeLength(free)} of free time.',
            style: hint,
          ),
          const SizedBox(height: 8),
          for (final d in week)
            Card(
              child: ListTile(
                title: Row(children: [
                  Text(fmt.format(d.day)),
                  if (d.tooFull) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('too full', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onErrorContainer)),
                    ),
                  ],
                ]),
                subtitle: Text([
                  '${d.due} due${d.dueMinutes > 0 ? ' (${describeLength(d.dueMinutes)})' : ''}',
                  '${d.meetings} meeting${d.meetings == 1 ? '' : 's'}',
                  '${describeLength(d.freeMinutes)} free',
                ].join(' · ')),
              ),
            ),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('This review', style: TextStyle(fontWeight: FontWeight.w600)),
                Text([...tally.isEmpty ? ['nothing changed'] : tally, if (took > 0) 'took $took min'].join(' · ')),
              ]),
            ),
          ),
        ];
    }
  }

  DateTime _nextMonday() {
    final d = _today;
    return DateTime(d.year, d.month, d.day + (8 - d.weekday));
  }

  Widget _card(Task t, String sub, List<Widget> actions) {
    final handled = _handled[t.id];
    final open = data.active.contains(t);
    return Opacity(
      opacity: handled != null ? 0.55 : 1,
      child: Card(
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: ageColor(t, data.hoursToRed, byDue: data.colourByDue, now: _now), width: 6)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            Text(
              [handled ?? sub, if (handled == null && data.category(t.categoryId) != null) data.category(t.categoryId)!.name].join(' · '),
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (handled == null && open) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: actions),
            ],
          ]),
        ),
      ),
    );
  }
}
