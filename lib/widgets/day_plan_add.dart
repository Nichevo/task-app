import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../day_plan.dart';
import '../models.dart';
import '../modes.dart';
import '../store.dart';

/// Item 109 (1.12.10): adding straight onto the Day plan. A tap on an empty time offers a new
/// task, a new step of a task (with the likely owners one tap away) or one already in the app,
/// planned at that time.

/// Open tasks that could own a step planned at [at], most likely first: tasks the Day plan shows
/// that are planned that day (the closest to [at] first), then others it shows (starred first,
/// then by due date), then the rest (hidden by the chips or the focus mode). Habits are left out.
List<Task> ownerChoices(AppData data, DateTime at, {Task? exclude}) {
  final day = DateTime(at.year, at.month, at.day);
  final next = day.add(const Duration(days: 1));
  int? distance(Task t) {
    int? best;
    for (final s in t.ownSlots) {
      if (s.start.isBefore(day) || !s.start.isBefore(next)) continue;
      final d = !at.isBefore(s.start) && at.isBefore(s.end)
          ? 0
          : at.isBefore(s.start)
              ? s.start.difference(at).inMinutes
              : at.difference(s.end).inMinutes + 1;
      if (best == null || d < best) best = d;
    }
    return best;
  }

  final planned = <(Task, int)>[];
  final shown = <Task>[];
  final rest = <Task>[];
  for (final t in data.active) {
    if (t == exclude || t.habit) continue;
    final d = distance(t);
    if (planHides(data, t)) {
      rest.add(t);
    } else if (d != null) {
      planned.add((t, d));
    } else {
      shown.add(t);
    }
  }
  planned.sort((a, b) => a.$2.compareTo(b.$2));
  int byUse(Task a, Task b) {
    if (a.starred != b.starred) return a.starred ? -1 : 1;
    final da = a.dueAt, db = b.dueAt;
    if (da != null && db != null) return da.compareTo(db);
    if (da != null || db != null) return da != null ? -1 : 1;
    return 0;
  }

  shown.sort(byUse);
  rest.sort(byUse);
  return [for (final (t, _) in planned) t, ...shown, ...rest];
}

/// Picks the task a step belongs to, the likely ones for [at] first ([ownerChoices]), with search.
Future<Task?> pickOwner(BuildContext context, AppData data, {required String title, required DateTime at, Task? exclude}) {
  final all = ownerChoices(data, at, exclude: exclude);
  final day = DateTime(at.year, at.month, at.day);
  bool plannedThatDay(Task t) => t.ownSlots.any((s) => DateUtils.isSameDay(s.start, day));
  return showDialog<Task>(
    context: context,
    builder: (c) {
      var q = '';
      return StatefulBuilder(builder: (c, setState) {
        final tasks = q.isEmpty ? all : all.where((t) => t.title.toLowerCase().contains(q.toLowerCase())).toList();
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            height: 420,
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tasks'),
                onChanged: (v) => setState(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(child: Text('No open task matches.'))
                    : ListView(children: [
                        for (final t in tasks)
                          ListTile(
                            dense: true,
                            leading: plannedThatDay(t)
                                ? const Icon(Icons.schedule)
                                : t.starred
                                    ? const Icon(Icons.star, color: Colors.amber)
                                    : const Icon(Icons.radio_button_unchecked),
                            title: Text(t.title),
                            subtitle: Text([
                              if (plannedThatDay(t)) 'On the plan ${_times(t, day)}',
                              if (data.category(t.categoryId) case final cat?) cat.name,
                            ].join(' · ')),
                            onTap: () => Navigator.pop(c, t),
                          ),
                      ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel'))],
        );
      });
    },
  );
}

String _times(Task t, DateTime day) {
  final hm = DateFormat('HH:mm');
  return [
    for (final s in t.ownSlots)
      if (DateUtils.isSameDay(s.start, day)) hm.format(s.start),
  ].join(', ');
}

/// What the "Add at" sheet made.
typedef AddedAt = ({Task task, TaskStep? step, String title, DateTime start});

/// What to add at a tapped time.
enum AddKind { task, step, existing }

/// The sheet for a tap on an empty time of the Day plan. Adds a new task or a step and plans it
/// at the time chosen; returns what was added. For "One I have", returns null after asking
/// [onExisting] to plan it.
Future<AddedAt?> showAddAtSheet(BuildContext context, AppStore store, DateTime start,
    {required Future<void> Function(DateTime start) onExisting}) async {
  final r = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _AddAtSheet(store: store, start: start),
  );
  if (r is DateTime && context.mounted) await onExisting(r);
  return r is AddedAt ? r : null;
}

class _AddAtSheet extends StatefulWidget {
  const _AddAtSheet({required this.store, required this.start});

  final AppStore store;
  final DateTime start;

  @override
  State<_AddAtSheet> createState() => _AddAtSheetState();
}

class _AddAtSheetState extends State<_AddAtSheet> {
  AppData get data => widget.store.data;
  late DateTime _start = widget.start;
  late int _minutes = data.dayPlan.length;
  AddKind _kind = AddKind.task;
  final _title = TextEditingController();
  // A new task starts in the focus mode's category for new tasks, as elsewhere.
  late String? _cat = data.category(modeNow.mode?.newCategory)?.id;
  Task? _owner;
  late final List<Task> _owners = ownerChoices(data, widget.start);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _ready => _title.text.trim().isNotEmpty && (_kind != AddKind.step || _owner != null);

  void _add() {
    if (!_ready) return;
    final title = _title.text.trim();
    final store = widget.store;
    if (_kind == AddKind.step) {
      final owner = _owner!;
      final step = store.addStep(owner, title, readTags: true);
      store.planTime(owner, _start, _minutes, step: step);
      Navigator.pop(context, (task: owner, step: step, title: title, start: _start));
    } else {
      final t = store.addTask(title, categoryId: _cat, plan: (at: _start, minutes: _minutes));
      Navigator.pop(context, (task: t, step: null, title: title, start: _start));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null || !mounted) return;
    setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
  }

  Future<void> _otherOwner() async {
    final t = await pickOwner(context, data, title: 'A step of', at: _start);
    if (t != null && mounted) setState(() => _owner = t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = data.dayPlan.snap;
    final lengths = {for (var m = snap; m <= 4 * 60; m += m < 60 ? snap : (m < 120 ? 30 : 60)) m, _minutes}.toList()..sort();
    final top = _owners.take(5).toList();
    if (_owner != null && !top.contains(_owner)) top.insert(0, _owner!);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text('Add to ${DateFormat('EEE d MMM').format(_start)}', style: theme.textTheme.titleMedium)),
              TextButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(DateFormat('HH:mm').format(_start)),
                onPressed: _pickTime,
              ),
              DropdownButton<int>(
                value: _minutes,
                underline: const SizedBox(),
                items: [for (final m in lengths) DropdownMenuItem(value: m, child: Text(describeLength(m)))],
                onChanged: (v) => setState(() => _minutes = v ?? _minutes),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AddKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: AddKind.task, icon: Icon(Icons.add_task), label: Text('New task')),
                  ButtonSegment(value: AddKind.step, icon: Icon(Icons.subdirectory_arrow_right), label: Text('New step')),
                  ButtonSegment(value: AddKind.existing, icon: Icon(Icons.search), label: Text('One I have')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) {
                  if (v.first == AddKind.existing) {
                    Navigator.pop(context, _start);
                    return;
                  }
                  setState(() => _kind = v.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _kind == AddKind.step ? 'Step' : 'Task',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 12),
            if (_kind == AddKind.task && data.categories.isNotEmpty) ...[
              Text('Category', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                ChoiceChip(label: const Text('None'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
                for (final c in data.categories)
                  ChoiceChip(label: Text(c.name), selected: _cat == c.id, onSelected: (_) => setState(() => _cat = c.id)),
              ]),
            ],
            if (_kind == AddKind.step) ...[
              Text('A step of', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final t in top)
                  ChoiceChip(
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(t.title, overflow: TextOverflow.ellipsis),
                    ),
                    selected: _owner == t,
                    onSelected: (_) => setState(() => _owner = _owner == t ? null : t),
                  ),
                ActionChip(avatar: const Icon(Icons.search, size: 18), label: const Text('Other task…'), onPressed: _otherOwner),
              ]),
              if (top.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('No open tasks yet.', style: TextStyle(color: theme.hintColor)),
                ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _ready ? _add : null,
                child: Text(_kind == AddKind.step ? 'Add step' : 'Add task'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
