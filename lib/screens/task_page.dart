import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/task_block.dart';

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
