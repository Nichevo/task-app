import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/task_block.dart';
import '../widgets/repeat_dialog.dart';
import 'settings_page.dart' show askText, remindOptions;

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

  Task get task => widget.task;
  bool get archived => task.closedAt != null;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
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
            trailing: DropdownButton<int?>(
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
          trailing: DropdownButton<String?>(
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
