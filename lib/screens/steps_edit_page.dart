import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../gantt.dart';
import '../models.dart';
import '../step_bulk.dart';
import '../store.dart';
import 'settings_page.dart' show askText, remindOptions;

/// Item 80: "Edit all steps". Every step of one task on one screen: tap a field to change that
/// step, or tick several and change them all at once (start, due, days of work, move dates,
/// line up in order, stage, reminder, progress). Changes save as you go; Undo takes them back
/// one at a time.
class StepsEditPage extends StatefulWidget {
  const StepsEditPage({super.key, required this.store, required this.task});

  final AppStore store;
  final Task task;

  @override
  State<StepsEditPage> createState() => _StepsEditPageState();
}

final _day = DateFormat('EEE d MMM');
final _dayTime = DateFormat('EEE d MMM, HH:mm');

class _StepsEditPageState extends State<StepsEditPage> {
  final _sel = <String>{};
  final _undo = <List<Map<String, dynamic>>>[];
  bool? _undoWeekends;

  AppStore get store => widget.store;
  Task get task => widget.task;
  AppData get data => store.data;

  List<TaskStep> get _selected => [for (final s in task.steps) if (_sel.contains(s.id)) s];

  bool get _showPlan =>
      task.gantt || task.steps.any((s) => s.startAt != null || s.takesDays != null || s.progress != null);
  bool get _showStage => task.boardSteps.isNotEmpty && data.stages.isNotEmpty;

  /// Runs [change] with a copy kept for Undo, then saves.
  void _do(void Function() change) {
    _undo.add(snapshotSteps(task));
    if (_undo.length > 50) _undo.removeAt(0);
    change();
    _sel.retainWhere((id) => task.steps.any((s) => s.id == id));
    store.changed(task: task);
    setState(() {});
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    restoreSteps(task, _undo.removeLast());
    if (_undo.isEmpty && _undoWeekends != null) {
      task.countWeekends = _undoWeekends;
      _undoWeekends = null;
    }
    _sel.retainWhere((id) => task.steps.any((s) => s.id == id));
    store.changed(task: task);
    setState(() {});
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text)));

  String _who(List<TaskStep> steps) => steps.length == 1 ? '"${steps.single.title}"' : '${steps.length} steps';

  // --- Changes (each works on one step or on all the ticked ones) ---

  Future<void> _setStart(List<TaskStep> steps) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: 'Start ${_who(steps)} on',
      initialDate: steps.first.startAt ?? (task.startAt != null ? dayOf(task.startAt!) : dayOf(now)),
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    _do(() {
      for (final s in steps) {
        s.startAt = dayOf(picked);
      }
    });
  }

  Future<void> _setDue(List<TaskStep> steps) async {
    final now = DateTime.now();
    final first = steps.first.dueAt;
    final date = await showDatePicker(
      context: context,
      helpText: '${_who(steps)} due on',
      initialDate: first ?? task.dueAt ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: first != null ? TimeOfDay.fromDateTime(first) : const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) return;
    _do(() {
      for (final s in steps) {
        s.dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      }
    });
  }

  /// Asks for a whole number with − and + buttons. Returns null on Cancel, or -1 for Clear when
  /// [clearLabel] is given.
  Future<int?> _askNumber(String title, int initial,
      {int min = 1, int max = 365, required String Function(int) label, String? clearLabel}) {
    var n = initial;
    return showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(title),
          content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              tooltip: 'Less',
              icon: const Icon(Icons.remove),
              onPressed: n <= min ? null : () => set(() => n--),
            ),
            SizedBox(width: 150, child: Text(label(n), textAlign: TextAlign.center)),
            IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.add),
              onPressed: n >= max ? null : () => set(() => n++),
            ),
          ]),
          actions: [
            if (clearLabel != null) TextButton(onPressed: () => Navigator.pop(c, -1), child: Text(clearLabel)),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, n), child: const Text('OK')),
          ],
        ),
      ),
    );
  }

  Future<void> _setDays(List<TaskStep> steps) async {
    final n = await _askNumber('Days of work for ${_who(steps)}', steps.first.takesDays ?? 1,
        label: (n) => '$n day${n == 1 ? '' : 's'}', clearLabel: 'Not set');
    if (n == null || !mounted) return;
    _do(() {
      for (final s in steps) {
        s.takesDays = n < 1 ? null : n;
      }
    });
  }

  Future<void> _stepDays(TaskStep s, int by) async {
    final n = (s.takesDays ?? 0) + by;
    _do(() => s.takesDays = n < 1 ? null : n);
  }

  Future<void> _moveDates(List<TaskStep> steps) async {
    if (!steps.any((s) => s.startAt != null || s.dueAt != null)) {
      return _snack('${steps.length == 1 ? 'It has' : 'They have'} no dates to move yet');
    }
    final n = await _askNumber('Move the dates of ${_who(steps)}', 1, min: -365,
        label: (n) => n == 0 ? 'Not moved' : '${n.abs()} day${n.abs() == 1 ? '' : 's'} ${n > 0 ? 'later' : 'earlier'}');
    if (n == null || n == 0 || !mounted) return;
    _do(() => moveStepDates(steps, n));
  }

  Future<void> _setStage(List<TaskStep> steps) async {
    final to = await showDialog<KanbanStage>(
      context: context,
      builder: (c) => SimpleDialog(title: Text('Move ${_who(steps)} to'), children: [
        for (final st in data.stages) SimpleDialogOption(onPressed: () => Navigator.pop(c, st), child: Text(st.name)),
      ]),
    );
    if (to == null || !mounted) return;
    _do(() {
      for (final s in steps) {
        store.moveStepToStage(task, s, to, how: MoveHow.menu);
      }
    });
  }

  Future<void> _setReminder(List<TaskStep> steps) async {
    final dated = steps.where((s) => s.dueAt != null).toList();
    if (dated.isEmpty) return _snack('Give ${steps.length == 1 ? 'it' : 'them'} a due date first');
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(title: Text('Reminder for ${_who(dated)}'), children: [
        SimpleDialogOption(
            onPressed: () => Navigator.pop(c, -1),
            child: Text('Same as Settings (${remindOptions[data.defaultRemindBefore] ?? '${data.defaultRemindBefore} min'})')),
        for (final e in remindOptions.entries)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Text(e.value)),
      ]),
    );
    if (v == null || !mounted) return;
    _do(() {
      for (final s in dated) {
        s.remindBefore = v < 0 ? null : v;
      }
    });
    if (dated.length < steps.length) _snack('Steps without a due date were left without a reminder');
  }

  Future<void> _setProgress(List<TaskStep> steps) async {
    var p = (steps.first.progress ?? 0).toDouble();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Progress of ${_who(steps)}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${p.round()}%'),
            Slider(value: p, max: 100, divisions: 20, label: '${p.round()}%', onChanged: (v) => set(() => p = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    _do(() {
      for (final s in steps.where((s) => !s.done)) {
        s.progress = p.round() <= 0 ? null : p.round();
      }
    });
  }

  Future<void> _rename(TaskStep s) async {
    final name = await askText(context, 'Rename step', initial: s.title);
    if (name != null && name.trim().isNotEmpty) _do(() => s.title = name.trim());
  }

  Future<void> _addStep() async {
    final name = await askText(context, 'New step');
    if (name != null && name.trim().isNotEmpty) _do(() => store.addStep(task, name.trim()));
  }

  Future<void> _more(List<TaskStep> steps) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: Text(_who(steps)), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'clear'), child: const Text('Clear their dates and days of work')),
        if (steps.any((s) => !s.done))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'tick'), child: const Text('Tick them')),
        if (steps.any((s) => s.done))
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'untick'), child: const Text('Untick them')),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'remove'), child: const Text('Remove them')),
      ]),
    );
    if (choice == null || !mounted) return;
    _do(() {
      for (final s in steps) {
        switch (choice) {
          case 'clear':
            s
              ..startAt = null
              ..takesDays = null
              ..dueAt = null
              ..remindBefore = null;
          case 'tick' when !s.done:
          case 'untick' when s.done:
            store.toggleStep(task, s);
          case 'remove':
            task.steps.remove(s);
        }
      }
    });
  }

  // --- Line up in order ---

  Future<void> _lineUp(List<TaskStep> steps) async {
    final open = steps.where((s) => !s.done).toList();
    if (open.isEmpty) return _snack('Those steps are all ticked');
    // Steps not being lined up that have dates, to start after.
    final others = [
      for (final s in task.steps)
        if (!open.contains(s) && stepBar(task, s, data) != null) s,
    ];
    // Default: after the nearest dated step above the first one, else today.
    final firstAt = task.steps.indexOf(open.first);
    TaskStep? before;
    for (final s in others) {
      if (task.steps.indexOf(s) < firstAt) before = s;
    }
    var startKey = before != null ? 'after:${before.id}' : 'today';
    DateTime? onDate;
    var gap = 0;
    var defaultDays = 1;
    var weekends = weekendsFor(task, data);
    var due = LineUpDue.fillMissing;
    final missing = open.where((s) => s.takesDays == null).toList();

    DateTime from() {
      if (startKey == 'today') return dayOf(DateTime.now());
      if (startKey == 'task') return dayOf(task.startAt ?? DateTime.now());
      if (startKey == 'date') return dayOf(onDate ?? DateTime.now());
      final s = task.steps.where((s) => 'after:${s.id}' == startKey).firstOrNull;
      return (s == null ? null : dayAfterStep(task, s, data)) ?? dayOf(DateTime.now());
    }

    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final plan = planLineUp(open, from: from(), weekends: weekends, gap: gap, defaultDays: defaultDays);
        final taskDue = task.dueAt == null ? null : dayOf(task.dueAt!);
        final over = taskDue == null ? <LineUpSlot>[] : plan.where((p) => p.end.isAfter(taskDue)).toList();
        final hint = Theme.of(c).textTheme.bodySmall;
        Widget stepper(String title, String sub, String value, VoidCallback? less, VoidCallback more) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              subtitle: Text(sub),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Less', icon: const Icon(Icons.remove), onPressed: less),
                SizedBox(width: 60, child: Text(value, textAlign: TextAlign.center)),
                IconButton(tooltip: 'More', icon: const Icon(Icons.add), onPressed: more),
              ]),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(c).viewInsets.bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Line up ${open.length} step${open.length == 1 ? '' : 's'}', style: Theme.of(c).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'One after another, in the order they are listed.'
                '${open.length < steps.length ? ' Ticked steps are left alone.' : ''}',
                style: hint,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: startKey,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Start', border: OutlineInputBorder()),
                items: [
                  for (final s in others)
                    DropdownMenuItem(
                      value: 'after:${s.id}',
                      child: Text('After ${s.title} (ends ${_day.format(stepBar(task, s, data)!.end)})',
                          overflow: TextOverflow.ellipsis),
                    ),
                  const DropdownMenuItem(value: 'today', child: Text('Today')),
                  if (task.startAt != null)
                    DropdownMenuItem(value: 'task', child: Text('When the task starts (${_day.format(task.startAt!)})')),
                  DropdownMenuItem(
                    value: 'date',
                    child: Text(onDate == null ? 'On a date…' : 'On ${_day.format(onDate!)}'),
                  ),
                ],
                onChanged: (v) async {
                  if (v == 'date') {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: c,
                      initialDate: onDate ?? from(),
                      firstDate: DateTime(now.year - 3),
                      lastDate: DateTime(now.year + 10),
                    );
                    if (picked == null) return;
                    onDate = picked;
                  }
                  set(() => startKey = v ?? startKey);
                },
              ),
              const SizedBox(height: 4),
              stepper('Gap between steps', 'Free days in between', '$gap day${gap == 1 ? '' : 's'}',
                  gap <= 0 ? null : () => set(() => gap--), () => set(() => gap++)),
              if (missing.isNotEmpty)
                stepper(
                  'Steps with no days of work',
                  missing.map((s) => s.title).join(', '),
                  '$defaultDays day${defaultDays == 1 ? '' : 's'}',
                  defaultDays <= 1 ? null : () => set(() => defaultDays--),
                  () => set(() => defaultDays++),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Count Saturdays and Sundays'),
                subtitle: const Text("This is the task's own setting, so the Gantt chart uses it too"),
                value: weekends,
                onChanged: (v) => set(() => weekends = v),
              ),
              Text('Due dates', style: Theme.of(c).textTheme.titleSmall),
              RadioGroup<LineUpDue>(
                groupValue: due,
                onChanged: (v) => set(() => due = v ?? due),
                child: const Column(children: [
                  RadioListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: LineUpDue.fillMissing,
                      title: Text('Fill in only the missing ones (their end day)')),
                  RadioListTile(
                      contentPadding: EdgeInsets.zero, dense: true, value: LineUpDue.setAll, title: Text('Set all to their end day')),
                  RadioListTile(
                      contentPadding: EdgeInsets.zero, dense: true, value: LineUpDue.keep, title: Text("Don't touch due dates")),
                ]),
              ),
              const SizedBox(height: 8),
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PREVIEW', style: hint?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    for (final p in plan)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Expanded(child: Text(p.step.title, overflow: TextOverflow.ellipsis)),
                          Text(
                            [
                              p.start == p.end ? _day.format(p.start) : '${_day.format(p.start)} – ${_day.format(p.end)}',
                              if (p.step.dueAt != null && due == LineUpDue.fillMissing) 'due ${_day.format(p.step.dueAt!)} kept',
                            ].join(' · '),
                            style: hint,
                          ),
                        ]),
                      ),
                    if (taskDue != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(over.isEmpty ? Icons.check : Icons.warning_amber,
                            size: 16, color: over.isEmpty ? Theme.of(c).colorScheme.primary : Theme.of(c).colorScheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            over.isEmpty
                                ? 'All end before the task is due (${_day.format(taskDue)})'
                                : '${over.map((p) => p.step.title).join(', ')} end${over.length == 1 ? 's' : ''} after the task is due (${_day.format(taskDue)})',
                            style: hint?.copyWith(
                                color: over.isEmpty ? Theme.of(c).colorScheme.primary : Theme.of(c).colorScheme.error),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Line up')),
              ]),
            ]),
          ),
        );
      }),
    );
    if (apply != true || !mounted) return;
    if (weekends != weekendsFor(task, data)) {
      if (_undo.isEmpty) _undoWeekends = task.countWeekends;
      task.countWeekends = weekends;
    }
    _do(() => applyLineUp(
          planLineUp(open, from: from(), weekends: weekends, gap: gap, defaultDays: defaultDays),
          due: due,
        ));
  }

  // --- Layout ---

  @override
  Widget build(BuildContext context) {
    final steps = task.steps;
    final n = _sel.length;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 760;
      return Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Edit all steps'),
            Text(
              [
                task.title,
                '${steps.length} step${steps.length == 1 ? '' : 's'}',
                if (task.dueAt != null && wide) 'task due ${_day.format(task.dueAt!)}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
          actions: [
            IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo), onPressed: _undo.isEmpty ? null : _undoLast),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ),
          ],
        ),
        bottomNavigationBar: !wide && n > 0 ? _phoneBar() : null,
        body: Column(children: [
          if (wide) _wideBar() else _selectAllRow(),
          if (wide) _header(),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: EdgeInsets.fromLTRB(wide ? 16 : 12, 4, wide ? 16 : 12, 16),
              itemCount: steps.length,
              onReorderItem: (o, nIndex) => _do(() => task.steps.insert(nIndex, task.steps.removeAt(o))),
              footer: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextButton.icon(onPressed: _addStep, icon: const Icon(Icons.add), label: const Text('Add a step')),
                // Folded, the chart sits under the steps and scrolls with them, showing every row.
                if (!wide && _showPlan && steps.isNotEmpty) ...[const SizedBox(height: 8), _preview(wide)],
              ]),
              itemBuilder: (context, i) => wide ? _row(steps[i], i) : _card(steps[i], i),
            ),
          ),
          if (wide && _showPlan && steps.isNotEmpty) _preview(wide),
        ]),
      );
    });
  }

  void _toggle(TaskStep s) => setState(() => _sel.contains(s.id) ? _sel.remove(s.id) : _sel.add(s.id));

  void _toggleAll() => setState(() {
        if (_sel.length == task.steps.length) {
          _sel.clear();
        } else {
          _sel.addAll(task.steps.map((s) => s.id));
        }
      });

  bool? get _allValue => _sel.isEmpty ? false : (_sel.length == task.steps.length ? true : null);

  Widget _selectAllRow() {
    final needs = task.steps.where((s) => !s.done && s.dueAt == null && s.startAt == null).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Row(children: [
        Checkbox(tristate: true, value: _allValue, onChanged: (_) => _toggleAll()),
        const Expanded(child: Text('Select all', overflow: TextOverflow.ellipsis)),
        if (needs.isNotEmpty)
          ActionChip(
            label: Text('Needs dates · ${needs.length}'),
            onPressed: () => setState(() => _sel
              ..clear()
              ..addAll(needs.map((s) => s.id))),
          ),
      ]),
    );
  }

  List<(IconData, String, VoidCallback)> _actions(List<TaskStep> sel) => [
        (Icons.play_arrow_outlined, 'Start', () => _setStart(sel)),
        (Icons.event, 'Due', () => _setDue(sel)),
        (Icons.timelapse, 'Days of work', () => _setDays(sel)),
        (Icons.swap_horiz, 'Move dates ±', () => _moveDates(sel)),
        (Icons.segment, 'Line up in order', () => _lineUp(sel)),
        if (_showStage) (Icons.view_kanban_outlined, 'Stage', () => _setStage(sel)),
        (Icons.notifications_outlined, 'Reminder', () => _setReminder(sel)),
        if (_showPlan) (Icons.percent, 'Progress', () => _setProgress(sel)),
        (Icons.more_horiz, 'More', () => _more(sel)),
      ];

  Widget _wideBar() {
    final sel = _selected;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: sel.isEmpty ? null : scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.centerLeft,
      child: sel.isEmpty
          ? Text('Tick boxes to change several steps at once, or tap any field to change just that one.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          : Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('${sel.length} selected', style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              for (final (icon, label, onTap) in _actions(sel))
                label == 'Line up in order'
                    ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label))
                    : FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label)),
            ]),
    );
  }

  Widget _phoneBar() {
    final sel = _selected;
    final all = _actions(sel);
    const main = {'Start', 'Due', 'Days of work', 'Line up in order'};
    final rest = all.where((a) => !main.contains(a.$2)).toList();
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Text('${sel.length} selected', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (final (icon, label, onTap) in all.where((a) => main.contains(a.$2)))
              _barButton(icon, label == 'Days of work' ? 'Days' : (label == 'Line up in order' ? 'Line up' : label), onTap,
                  strong: label == 'Line up in order'),
            _barButton(Icons.more_horiz, 'More', () async {
              final pick = await showModalBottomSheet<VoidCallback>(
                context: context,
                showDragHandle: true,
                builder: (c) => SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final (icon, label, onTap) in rest)
                      ListTile(
                        leading: Icon(icon),
                        title: Text(label == 'More' ? 'Clear, tick or remove…' : label),
                        onTap: () => Navigator.pop(c, onTap),
                      ),
                  ]),
                ),
              );
              pick?.call();
            }),
          ]),
        ]),
      ),
    );
  }

  Widget _barButton(IconData icon, String label, VoidCallback onTap, {bool strong = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: strong ? scheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 56,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: strong ? scheme.onPrimary : null),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: strong ? scheme.onPrimary : null)),
          ]),
        ),
      ),
    );
  }

  static const _wStart = 124.0, _wDays = 112.0, _wDue = 150.0, _wRemind = 128.0, _wStage = 124.0, _wProg = 92.0;

  List<Widget> _columns(List<Widget> plan, Widget due, Widget remind, Widget? stage) => [
        if (_showPlan) ...[SizedBox(width: _wStart, child: plan[0]), const SizedBox(width: 8)],
        if (_showPlan) ...[SizedBox(width: _wDays, child: plan[1]), const SizedBox(width: 8)],
        SizedBox(width: _wDue, child: due),
        const SizedBox(width: 8),
        SizedBox(width: _wRemind, child: remind),
        if (stage != null) ...[const SizedBox(width: 8), SizedBox(width: _wStage, child: stage)],
        if (_showPlan) ...[const SizedBox(width: 8), SizedBox(width: _wProg, child: plan[2])],
      ];

  Widget _header() {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    Text h(String s) => Text(s, style: style);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Row(children: [
        SizedBox(
          width: 40,
          child: Checkbox(tristate: true, value: _allValue, onChanged: (_) => _toggleAll()),
        ),
        const SizedBox(width: 28),
        Expanded(child: h('STEP')),
        ..._columns([h('STARTS'), h('DAYS OF WORK'), h('PROGRESS')], h('DUE'), h('REMINDER'), _showStage ? h('STAGE') : null),
      ]),
    );
  }

  String _remindText(TaskStep s) {
    if (s.dueAt == null) return 'None';
    final r = s.remindBefore;
    if (r == null) return 'Default';
    return remindOptions[r] ?? '$r min before';
  }

  String? _lateText(TaskStep s) {
    if (s.done) return s.doneAt == null ? null : 'Ticked ${_day.format(s.doneAt!)}';
    final bar = stepBar(task, s, data);
    if (bar != null && bar.late && bar.task.id == task.id && !stepIsPoint(s)) {
      return 'Ends ${_day.format(bar.end)}, ${bar.lateDays} day${bar.lateDays == 1 ? '' : 's'} after due';
    }
    return null;
  }

  Widget _row(TaskStep s, int i) {
    final scheme = Theme.of(context).colorScheme;
    final on = _sel.contains(s.id);
    final late = _lateText(s);
    final isLate = late != null && !s.done;
    return Container(
      key: ValueKey(s.id),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: on
            ? scheme.secondaryContainer.withValues(alpha: 0.6)
            : isLate
                ? scheme.errorContainer.withValues(alpha: 0.25)
                : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        SizedBox(width: 40, child: Checkbox(value: on, onChanged: (_) => _toggle(s))),
        ReorderableDragStartListener(
          index: i,
          child: const SizedBox(width: 28, child: Icon(Icons.drag_indicator, size: 20)),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _rename(s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                s.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  decoration: s.done ? TextDecoration.lineThrough : null,
                  color: s.done ? Theme.of(context).disabledColor : null,
                ),
              ),
              if (late != null || s.note.isNotEmpty)
                Text(
                  late ?? s.note,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isLate ? scheme.error : null,
                        fontWeight: isLate ? FontWeight.w500 : null,
                      ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        ..._columns(
          [
            _cell(s.startAt == null ? 'Set start' : _day.format(s.startAt!), s.startAt == null, () => _setStart([s])),
            _daysCell(s),
            _progressCell(s),
          ],
          _cell(s.dueAt == null ? 'Set due' : _dayTime.format(s.dueAt!), s.dueAt == null, () => _setDue([s])),
          _cell(_remindText(s), s.dueAt == null, () => _setReminder([s])),
          _showStage ? _stageCell(s) : null,
        ),
      ]),
    );
  }

  Widget _cell(String text, bool empty, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 40),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        foregroundColor: empty ? scheme.onSurfaceVariant : scheme.onSurface,
        side: BorderSide(color: empty ? scheme.outlineVariant : scheme.outline),
      ),
      child: Text(text, overflow: TextOverflow.ellipsis, maxLines: 1),
    );
  }

  Widget _daysCell(TaskStep s) {
    final t = s.takesDays;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        IconButton(
          tooltip: 'Fewer days',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Icons.remove),
          onPressed: t == null ? null : () => _stepDays(s, -1),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _setDays([s]),
            child: Text(t == null ? 'not set' : '$t day${t == 1 ? '' : 's'}', textAlign: TextAlign.center),
          ),
        ),
        IconButton(
          tooltip: 'More days',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Icons.add),
          onPressed: () => _stepDays(s, 1),
        ),
      ]),
    );
  }

  Widget _progressCell(TaskStep s) {
    final p = s.done ? 100 : s.progress ?? 0;
    return InkWell(
      onTap: s.done ? null : () => _setProgress([s]),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$p%', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: p / 100, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        ]),
      ),
    );
  }

  Widget _stageCell(TaskStep s) {
    final stage = s.placed ? data.stage(s.stageId) : null;
    return FilledButton.tonal(
      onPressed: () => _setStage([s]),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(children: [
        Expanded(child: Text(stage?.name ?? '—', overflow: TextOverflow.ellipsis)),
        const Icon(Icons.arrow_drop_down, size: 18),
      ]),
    );
  }

  Widget _card(TaskStep s, int i) {
    final scheme = Theme.of(context).colorScheme;
    final on = _sel.contains(s.id);
    final late = _lateText(s);
    final isLate = late != null && !s.done;
    final stage = _showStage && s.placed ? data.stage(s.stageId) : null;
    Widget chip(IconData icon, String text, bool empty, VoidCallback onTap) => ActionChip(
          avatar: Icon(icon, size: 16),
          label: Text(text),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: empty ? scheme.outlineVariant : scheme.outline),
          labelStyle: TextStyle(color: empty ? scheme.onSurfaceVariant : null),
        );
    return Card.outlined(
      key: ValueKey(s.id),
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: on ? scheme.secondaryContainer.withValues(alpha: 0.6) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: on ? scheme.primary : (isLate ? scheme.error : scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(value: on, onChanged: (_) => _toggle(s)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _rename(s),
                    child: Text(s.title,
                        style: TextStyle(
                          decoration: s.done ? TextDecoration.lineThrough : null,
                          color: s.done ? Theme.of(context).disabledColor : null,
                        )),
                  ),
                ),
                if (stage != null)
                  InkWell(
                    onTap: () => _setStage([s]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(10)),
                      child: Text(stage.name, style: Theme.of(context).textTheme.labelSmall),
                    ),
                  ),
              ]),
              if (late != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(late,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isLate ? scheme.error : null,
                            fontWeight: isLate ? FontWeight.w500 : null,
                          )),
                ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (_showPlan)
                  chip(Icons.play_arrow_outlined, s.startAt == null ? 'Start' : _day.format(s.startAt!), s.startAt == null,
                      () => _setStart([s])),
                if (_showPlan)
                  chip(Icons.timelapse, s.takesDays == null ? 'Days' : '${s.takesDays} day${s.takesDays == 1 ? '' : 's'}',
                      s.takesDays == null, () => _setDays([s])),
                chip(Icons.event, s.dueAt == null ? 'Due' : _dayTime.format(s.dueAt!), s.dueAt == null, () => _setDue([s])),
                if (s.dueAt != null) chip(Icons.notifications_outlined, _remindText(s), false, () => _setReminder([s])),
              ]),
            ]),
          ),
          ReorderableDragStartListener(
            index: i,
            child: const Padding(padding: EdgeInsets.only(top: 12, left: 4), child: Icon(Icons.drag_handle)),
          ),
        ]),
      ),
    );
  }

  /// A small Gantt chart of the steps that updates as you edit.
  Widget _preview(bool wide) {
    final bars = [for (final s in task.steps) stepBar(task, s, data)];
    final dated = bars.whereType<GanttBar>().toList();
    final needs = bars.where((b) => b == null).length;
    final today = dayOf(DateTime.now());
    final taskDue = task.dueAt == null ? null : dayOf(task.dueAt!);
    var from = dated.isEmpty ? today : dated.map((b) => b.start).reduce((a, b) => a.isBefore(b) ? a : b);
    var to = dated.isEmpty ? addDays(today, 27) : dated.map((b) => b.end).reduce((a, b) => a.isAfter(b) ? a : b);
    if (taskDue != null && taskDue.isAfter(to)) to = taskDue;
    if (today.isBefore(from) && daysBetween(today, from) < 14) from = today;
    from = addDays(from, -(from.weekday - 1)); // back to Monday
    to = addDays(to, 7 - to.weekday); // on to Sunday
    final scheme = Theme.of(context).colorScheme;
    final hint = Theme.of(context).textTheme.bodySmall;
    final rows = task.steps.length;
    const rowH = 16.0;
    return Container(
      margin: wide ? const EdgeInsets.fromLTRB(16, 0, 16, 16) : const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 2, alignment: WrapAlignment.spaceBetween, children: [
          Text(task.gantt ? 'How it looks on the Gantt chart' : 'Timeline',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            [
              weekendsFor(task, data) ? 'Weekends count' : "Weekends don't count",
              if (needs > 0) '$needs step${needs == 1 ? '' : 's'} need${needs == 1 ? 's' : ''} dates',
            ].join(' · '),
            style: hint,
          ),
        ]),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: wide ? 12 * rowH + 18 : double.infinity),
          child: SingleChildScrollView(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: wide ? 140 : 96,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 18),
                  for (final s in task.steps)
                    SizedBox(
                      height: rowH,
                      child: Text(s.title, style: hint?.copyWith(fontSize: 11), overflow: TextOverflow.ellipsis),
                    ),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: rows * rowH + 18,
                  child: CustomPaint(
                    painter: _PreviewPainter(
                      bars: bars,
                      points: [for (final s in task.steps) stepIsPoint(s)],
                      done: [for (final s in task.steps) s.done],
                      from: from,
                      to: to,
                      today: today,
                      taskDue: taskDue,
                      weekends: !weekendsFor(task, data),
                      scheme: scheme,
                      labelStyle: hint?.copyWith(fontSize: 11) ?? const TextStyle(fontSize: 11),
                      rowH: rowH,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter({
    required this.bars,
    required this.points,
    required this.done,
    required this.from,
    required this.to,
    required this.today,
    required this.taskDue,
    required this.weekends,
    required this.scheme,
    required this.labelStyle,
    required this.rowH,
  });

  final List<GanttBar?> bars;
  final List<bool> points;
  final List<bool> done;
  final DateTime from, to, today;
  final DateTime? taskDue;

  /// Shade Saturdays and Sundays (when they don't count).
  final bool weekends;
  final ColorScheme scheme;
  final TextStyle labelStyle;
  final double rowH;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 18.0;
    final days = daysBetween(from, to) + 1;
    final w = size.width / max(days, 1);
    double x(DateTime d) => daysBetween(from, d) * w;
    final shade = Paint()..color = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    var labelEnd = -1.0;
    for (var d = from; !d.isAfter(to); d = addDays(d, 1)) {
      if (weekends && isWeekend(d)) canvas.drawRect(Rect.fromLTWH(x(d), top, w, size.height - top), shade);
      if (d.weekday == DateTime.monday) {
        final tp = TextPainter(text: TextSpan(text: DateFormat('d MMM').format(d), style: labelStyle), textDirection: TextDirection.ltr)
          ..layout();
        if (x(d) > labelEnd && x(d) + tp.width <= size.width) {
          tp.paint(canvas, Offset(x(d), 0));
          labelEnd = x(d) + tp.width + 6;
        }
      }
    }
    if (!today.isBefore(from) && !today.isAfter(to)) {
      canvas.drawRect(Rect.fromLTWH(x(today) + w / 2 - 1, top, 2, size.height - top), Paint()..color = scheme.primary);
    }
    if (taskDue != null) {
      final dx = x(taskDue!) + w;
      final p = Paint()
        ..color = scheme.error
        ..strokeWidth = 2;
      for (var y = top; y < size.height; y += 6) {
        canvas.drawLine(Offset(dx, y), Offset(dx, min(y + 3, size.height)), p);
      }
    }
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      if (b == null) continue;
      final y = top + i * rowH + 3;
      final color = done[i] ? scheme.outline : scheme.primary;
      if (points[i]) {
        final c = Offset(x(b.start) + w / 2, y + 5);
        final path = Path()
          ..moveTo(c.dx, c.dy - 5)
          ..lineTo(c.dx + 5, c.dy)
          ..lineTo(c.dx, c.dy + 5)
          ..lineTo(c.dx - 5, c.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = color);
        continue;
      }
      final r = Radius.circular(5);
      final onTimeEnd = b.late ? b.due! : b.end;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(x(b.start), y, x(onTimeEnd) + w, y + 10), r), Paint()..color = color);
      if (b.late && !done[i]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x(b.due!) + w, y, x(b.end) + w, y + 10), r),
            Paint()..color = scheme.error);
      }
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
