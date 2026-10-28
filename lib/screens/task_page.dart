import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/task_block.dart';
import '../widgets/repeat_dialog.dart';
import 'settings_page.dart' show askText, askLines, remindOptions;

/// Edit a task's name, notes and due date. Changes save as you go.
class TaskPage extends StatefulWidget {
  const TaskPage({super.key, required this.store, required this.task, this.onClose});

  final AppStore store;
  final Task task;

  /// Set when shown inside the home screen rather than as its own page.
  final VoidCallback? onClose;

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _notes = TextEditingController(text: widget.task.notes);
  final _newStep = TextEditingController();
  final _newStepFocus = FocusNode();

  Task get task => widget.task;
  bool get archived => task.closedAt != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _newStep.dispose();
    _newStepFocus.dispose();
    super.dispose();
  }

  void _addStep() {
    final text = _newStep.text.trim();
    if (text.isEmpty) return;
    setState(() => widget.store.addStep(task, text));
    _newStep.clear();
    _newStepFocus.requestFocus();
  }

  void _toggleStep(TaskStep s) {
    final finished = widget.store.toggleStep(task, s);
    setState(() {});
    if (finished && !archived) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text('All steps done'),
          action: SnackBarAction(
            label: 'Tick off task',
            onPressed: () {
              widget.store.complete(task);
              _close();
            },
          ),
        ));
    }
  }

  Future<void> _stepMenu(TaskStep s) async {
    final linked = data.task(s.taskId);
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(s.title),
        children: [
          if (linked != null)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, 'open'), child: Text('Open task "${linked.title}"'))
          else if (!archived)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'task'),
              child: const Text('Make into a task of its own (so it can have a date and notes)'),
            ),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'rename'), child: const Text('Rename')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'remove'), child: const Text('Remove step')),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'open':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: widget.store, task: linked!)));
      case 'task':
        final t = widget.store.stepToTask(task, s);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${t.title}" as a task after this one')));
      case 'rename':
        final name = await askText(context, 'Rename step', initial: s.title);
        if (name != null && name.trim().isNotEmpty) {
          s.title = name.trim();
          _update(() {});
        }
      case 'remove':
        setState(() => widget.store.removeStep(task, s));
    }
  }

  Future<void> _templateMenu() async {
    final templates = data.templates;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Checklist templates'),
        children: [
          for (final t in templates)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, 'use:${t.id}'), child: Text('Add "${t.name}" (${t.steps.length} steps)')),
          if (templates.isEmpty)
            const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 8), child: Text('No templates saved yet.')),
          const Divider(),
          if (task.steps.isNotEmpty)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save this checklist as a template')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'new'), child: const Text('New template…')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.startsWith('use:')) {
      final tpl = templates.where((t) => t.id == choice.substring(4)).firstOrNull;
      if (tpl != null) setState(() => widget.store.applyTemplate(task, tpl));
    } else if (choice == 'save') {
      final name = await askText(context, 'Template name', initial: task.title);
      if (name != null && name.trim().isNotEmpty) {
        widget.store.saveTemplate(name, [for (final s in task.steps) s.title]);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved template "${name.trim()}"')));
      }
    } else if (choice == 'new') {
      final name = await askText(context, 'Template name');
      if (name == null || name.trim().isEmpty || !mounted) return;
      final lines = await askLines(context, 'Steps for "${name.trim()}"');
      if (lines != null && lines.isNotEmpty) widget.store.saveTemplate(name, lines);
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final initial = task.dueAt ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: task.dueAt != null ? TimeOfDay.fromDateTime(initial) : const TimeOfDay(hour: 17, minute: 0),
    );
    if (time == null) return;
    setState(() => task.dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
    widget.store.changed(task: task);
  }

  AppData get data => widget.store.data;

  void _update(VoidCallback change) {
    setState(change);
    widget.store.changed(task: task);
  }

  Future<DateTime?> _pickDateTime(DateTime initial, {TimeOfDay? time}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: time ?? TimeOfDay.fromDateTime(initial));
    if (t == null) return null;
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  Future<void> _pickSnooze() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final d = await _pickDateTime(task.snoozedUntil ?? tomorrow, time: const TimeOfDay(hour: 8, minute: 0));
    if (d != null) _update(() => task.snoozedUntil = d);
  }

  /// Choose the task this one waits for. Tasks that (directly or not) wait for this one are
  /// left out, so a chain can't loop.
  Future<void> _pickAfter() async {
    bool waitsOnThis(Task t) {
      final seen = <String>{};
      for (Task? c = t; c != null && seen.add(c.id); c = data.task(c.afterTaskId)) {
        if (c.afterTaskId == task.id) return true;
      }
      return false;
    }

    final options = data.active.where((t) => t.id != task.id && !waitsOnThis(t)).toList();
    final picked = await showDialog<Task>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Comes after which task?'),
        children: [
          if (options.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No other open tasks.')),
          for (final t in options)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, t), child: Text(t.title)),
        ],
      ),
    );
    if (picked != null) _update(() => task.afterTaskId = picked.id);
  }

  Future<void> _editRepeat() async {
    final r = await showDialog<Repeat>(
      context: context,
      builder: (_) => RepeatDialog(initial: task.repeat),
    );
    if (r != null) _update(() => task.repeat = r);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this task?'),
        content: const Text('It will be removed completely, not archived.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.store.delete(task);
    _close();
  }

  void _close() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onClose == null
            ? null
            : IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: _close),
        title: Text(archived ? 'Archived task' : 'Task'),
        actions: [
          IconButton(
            tooltip: task.starred ? 'Unstar' : 'Star (keep at the top)',
            icon: Icon(task.starred ? Icons.star : Icons.star_border,
                color: task.starred ? const Color(0xFFFFB300) : null),
            onPressed: () => _update(() => task.starred = !task.starred),
          ),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Task', border: OutlineInputBorder()),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) {
            task.title = v;
            widget.store.changed(task: task);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) {
            task.notes = v;
            widget.store.changed(task: task);
          },
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.checklist),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              task.steps.isEmpty ? 'Checklist' : 'Checklist  ${task.stepsDone}/${task.steps.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton.icon(
            onPressed: _templateMenu,
            icon: const Icon(Icons.library_add_outlined, size: 18),
            label: const Text('Templates'),
          ),
        ]),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (o, n) => setState(() => widget.store.reorderSteps(task, o, n)),
          children: [
            for (final (i, s) in task.steps.indexed)
              ListTile(
                key: ValueKey(s.id),
                dense: true,
                contentPadding: const EdgeInsets.only(left: 4),
                leading: Checkbox(value: s.done, onChanged: archived ? null : (_) => _toggleStep(s)),
                title: Text(s.title,
                    style: TextStyle(
                        decoration: s.done ? TextDecoration.lineThrough : null,
                        color: s.done ? Theme.of(context).disabledColor : null)),
                subtitle: s.taskId == null ? null : Text('Task: ${data.task(s.taskId)?.title ?? '(deleted)'}'),
                onTap: () => _stepMenu(s),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (s.taskId != null) const Icon(Icons.link, size: 18),
                  ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                ]),
              ),
          ],
        ),
        if (!archived)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _newStep,
                  focusNode: _newStepFocus,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Add a step…', isDense: true, border: UnderlineInputBorder()),
                  onSubmitted: (_) => _addStep(),
                ),
              ),
              IconButton(tooltip: 'Add step', icon: const Icon(Icons.add), onPressed: _addStep),
            ]),
          ),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('Created'),
          subtitle: Text(dateTimeFmt.format(task.createdAt)),
        ),
        ListTile(
          leading: const Icon(Icons.event),
          title: const Text('Due'),
          subtitle: Text(task.dueAt == null ? 'Tap to set a due date' : dateTimeFmt.format(task.dueAt!)),
          onTap: _pickDue,
          trailing: task.dueAt == null
              ? null
              : IconButton(
                  tooltip: 'Clear due date',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() => task.dueAt = null);
                    widget.store.changed(task: task);
                  },
                ),
        ),
        if (task.dueAt != null && !archived)
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Remind me'),
            subtitle: DropdownButton<int?>(
              isExpanded: true,
              value: task.remindBefore,
              items: [
                DropdownMenuItem(
                    value: null,
                    child: Text('Default (${remindOptions[data.defaultRemindBefore] ?? 'at due time'})')),
                for (final e in remindOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => _update(() => task.remindBefore = v),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.label_outline),
          title: const Text('Category'),
          subtitle: DropdownButton<String?>(
            isExpanded: true,
            value: data.category(task.categoryId)?.id,
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final c in data.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
              const DropdownMenuItem(value: '+', child: Text('New category…')),
            ],
            onChanged: (v) async {
              if (v == '+') {
                final name = await askText(context, 'New category');
                if (name == null || name.trim().isEmpty) return;
                v = widget.store.addCategory(name).id;
              }
              _update(() => task.categoryId = v);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.repeat),
          title: const Text('Repeat'),
          subtitle: Text(task.repeat?.describe() ?? 'Does not repeat'),
          onTap: _editRepeat,
          trailing: task.repeat == null
              ? null
              : IconButton(
                  tooltip: 'Stop repeating',
                  icon: const Icon(Icons.clear),
                  onPressed: () => _update(() => task.repeat = null),
                ),
        ),
        if (!archived) ...[
          ListTile(
            leading: Icon(data.isLocked(task) ? Icons.lock_outline : Icons.link),
            title: const Text('Comes after'),
            subtitle: Text(data.task(task.afterTaskId)?.title ?? 'Nothing (can be done any time)'),
            onTap: _pickAfter,
            trailing: task.afterTaskId == null
                ? null
                : IconButton(
                    tooltip: 'Remove link',
                    icon: const Icon(Icons.clear),
                    onPressed: () => _update(() => task.afterTaskId = null),
                  ),
          ),
          ListTile(
            leading: const Icon(Icons.snooze),
            title: const Text('Snooze'),
            subtitle: Text(task.isSnoozed(DateTime.now())
                ? 'Hidden until ${dateTimeFmt.format(task.snoozedUntil!)}'
                : 'Hide this task until a later date'),
            onTap: _pickSnooze,
            trailing: !task.isSnoozed(DateTime.now())
                ? null
                : IconButton(
                    tooltip: 'Unsnooze',
                    icon: const Icon(Icons.clear),
                    onPressed: () => _update(() => task.snoozedUntil = null),
                  ),
          ),
        ],
        if (archived)
          ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Closed'),
            subtitle: Text(dateTimeFmt.format(task.closedAt!)),
          ),
      ]),
    );
  }
}
