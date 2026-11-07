import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../gantt.dart';
import '../habits.dart';
import '../models.dart';
import '../places.dart';
import '../store.dart';
import '../task_list.dart';
import '../widgets/link_text.dart';
import '../widgets/task_block.dart';
import '../widgets/repeat_dialog.dart';
import '../widgets/worked_week.dart';
import 'gantt_page.dart' show GanttPage, editStepPlan;
import 'kanban_page.dart' show moveWithRule, describeSpell;
import 'matrix_page.dart' show putInBox;
import 'settings_page.dart' show askText, askLines, remindOptions;
import 'starred_page.dart' show pickTask;
import 'steps_edit_page.dart';

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
          else if (!archived) ...[
            if (s.carried != null)
              SimpleDialogOption(onPressed: () => Navigator.pop(c, 'carried'), child: const Text('Show what it carries')),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'due'),
              child: Text(s.dueAt == null ? 'Give it a date and reminder' : 'Change its date or reminder'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'note'),
              child: Text(s.note.isEmpty ? 'Add a note' : 'Edit the note'),
            ),
            if (task.gantt)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'plan'),
                child: Text(s.startAt == null && s.takesDays == null && s.progress == null
                    ? 'Start, days of work and progress (Gantt chart)'
                    : 'Change its start, days of work or progress'),
              ),
            if (s.carried == null)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'task'),
                child: const Text('Make into a linked task (ticks this step when done)'),
              ),
          ],
          if (!archived)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'split'),
              child: Text(s.carried != null
                  ? 'Split out into a task of its own (brings back everything it had)'
                  : 'Split out into a task of its own (leaves this checklist)'),
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
      case 'carried':
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('"${s.title}" was a task'),
            content: Text([
              ...carriedSummary(s, data),
              '',
              'All of it comes back when you split it out.',
            ].join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
      case 'due':
        await _stepDue(s);
      case 'plan':
        await editStepPlan(context, widget.store, task, s);
        if (mounted) setState(() {});
      case 'note':
        final note = await askText(context, 'Note for "${s.title}"', initial: s.note);
        if (note != null) setState(() => widget.store.setStepNote(task, s, note));
      case 'split':
        final (t, undo) = widget.store.splitOut(task, s);
        setState(() {});
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('"${t.title}" is now a task of its own'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                undo();
                if (mounted) setState(() {});
              },
            ),
          ));
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

  /// Item 61: a step's date and reminder.
  Future<void> _stepDue(TaskStep s) async {
    if (s.dueAt != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(title: Text(s.title), children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'date'), child: const Text('Change the date')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'remind'), child: const Text('Change the reminder')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 'clear'), child: const Text('Remove the date')),
        ]),
      );
      if (choice == null || !mounted) return;
      if (choice == 'clear') return setState(() => widget.store.setStepDue(task, s, null));
      if (choice == 'remind') return _stepRemind(s);
    }
    final d = await _pickDateTime(s.dueAt ?? task.dueAt ?? DateTime.now().add(const Duration(days: 1)),
        time: s.dueAt == null ? const TimeOfDay(hour: 9, minute: 0) : null);
    if (d == null || !mounted) return;
    setState(() => widget.store.setStepDue(task, s, d, remindBefore: s.remindBefore));
  }

  Future<void> _stepRemind(TaskStep s) async {
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Reminder'), children: [
        SimpleDialogOption(
            onPressed: () => Navigator.pop(c, -1),
            child: Text('Same as Settings (${remindOptions[data.defaultRemindBefore] ?? '${data.defaultRemindBefore} min'})')),
        for (final e in remindOptions.entries)
          SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Text(e.value)),
      ]),
    );
    if (v == null || !mounted) return;
    setState(() => widget.store.setStepDue(task, s, s.dueAt, remindBefore: v < 0 ? null : v));
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

  /// Choose another task this one waits for (item 72 allows several). Tasks that (directly or
  /// not) wait for this one are left out, so a chain can't loop.
  Future<void> _pickAfter() async {
    final options = data.active
        .where((t) => t.id != task.id && !task.afterIds.contains(t.id) && !wouldLoop(task, t, data))
        .toList();
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
    if (picked != null) setState(() => widget.store.addAfter(task, picked));
  }

  /// The tasks this one comes after, each with a remove button, and "Add another".
  Future<void> _editAfter() async {
    if (task.afterIds.isEmpty) return _pickAfter();
    final add = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setInner) => AlertDialog(
          title: const Text('Comes after'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final id in task.afterIds)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(anyTask(data, id)?.title ?? '(deleted task)'),
                subtitle: anyTask(data, id)?.closedAt != null ? const Text('Ticked off') : null,
                trailing: IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    widget.store.removeAfter(task, id);
                    setInner(() {});
                    setState(() {});
                  },
                ),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add another')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Done')),
          ],
        ),
      ),
    );
    if (add == true && mounted) await _pickAfter();
  }

  Future<void> _editRepeat() async {
    final r = await showDialog<Repeat>(
      context: context,
      builder: (_) => RepeatDialog(initial: task.repeat),
    );
    if (r != null) _update(() => task.repeat = r);
  }

  /// Moves a repeating task to its next date without ticking it off.
  void _skip() {
    final undo = widget.store.skip(task);
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Skipped. Next due ${dateTimeFmt.format(task.dueAt!)}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            undo();
            if (mounted) setState(() {});
          },
        ),
      ));
  }

  Future<void> _pickEstimate() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('About how long will it take?'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, -1), child: const Text('Not set')),
          for (final m in estimateOptions)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, m), child: Text(describeMinutes(m))),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, 0), child: const Text('Other…')),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == -1) return _update(() => task.estimate = null);
    if (picked > 0) return _update(() => task.estimate = picked);
    final typed = await askText(context, 'Minutes (or e.g. 1.5h)', initial: task.estimate?.toString() ?? '');
    final minutes = parseEstimate(typed ?? '');
    if (minutes != null) _update(() => task.estimate = minutes);
  }

  Future<void> _pickPlace() async {
    final names = {for (final p in widget.store.places) p.name, ?task.place}.toList();
    if (widget.store.places.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No places saved yet. Add them in Settings, Places (save where you are).')));
      if (task.place == null) return;
    }
    final picked = await showDialog<(String?, bool)>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Remind me'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, (null, false)), child: const Text('No place reminder')),
          for (final n in names) ...[
            SimpleDialogOption(onPressed: () => Navigator.pop(c, (n, false)), child: Text('When I arrive at $n')),
            SimpleDialogOption(onPressed: () => Navigator.pop(c, (n, true)), child: Text('When I leave $n')),
          ],
        ],
      ),
    );
    if (picked == null) return;
    _update(() {
      task.place = picked.$1;
      task.placeLeave = picked.$1 != null && picked.$2;
    });
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

  /// Item 73: turns this task into a step of another one, keeping everything it has.
  Future<void> _makeStep() async {
    final parent = await pickTask(context, data, title: 'Make "${task.title}" a step of', exclude: task);
    if (parent == null || !mounted) return;
    var own = OwnSteps.keep;
    if (task.steps.isNotEmpty) {
      final n = task.steps.length;
      final picked = await showDialog<OwnSteps>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text('"${task.title}" has $n step${n == 1 ? '' : 's'} of its own'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, OwnSteps.keep),
              child: const Text('Keep them inside (back when it is split out)'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, OwnSteps.addToParent),
              child: Text('Add them to "${parent.title}" as steps'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, OwnSteps.splitOut),
              child: const Text('Split them out as tasks of their own'),
            ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      own = picked;
    }
    final messenger = ScaffoldMessenger.of(context);
    final (_, undo) = widget.store.makeStep(task, parent, own: own);
    _close();
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('"${task.title}" is now a step of "${parent.title}"'),
        action: SnackBarAction(label: 'Undo', onPressed: undo),
      ));
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
          if (!archived)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'step' => _makeStep(),
                _ => null,
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'step', child: Text('Make into a step of…'))],
            ),
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
            setState(() {});
            widget.store.changed(task: task);
          },
        ),
        // Links in the notes, ready to tap (the box above is for editing).
        if (findLinks(task.notes) case final links when links.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final l in links)
                ActionChip(
                  avatar: Icon(
                      switch (l.uri.scheme) { 'mailto' => Icons.mail_outline, 'tel' => Icons.call_outlined, _ => Icons.open_in_new },
                      size: 16),
                  label: Text(l.text, overflow: TextOverflow.ellipsis),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => openLink(l.uri),
                ),
            ]),
          ),
        // Item 55: emails kept on the task.
        if (task.emails.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.mail_outline),
            const SizedBox(width: 16),
            Text(task.emails.length == 1 ? 'Email' : 'Emails  ${task.emails.length}',
                style: Theme.of(context).textTheme.titleMedium),
          ]),
          for (final e in task.emails)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 4),
              title: Text(e.subject.isEmpty ? '(no subject)' : e.subject),
              subtitle: Text([
                [e.from, if (e.date != null) dateTimeFmt.format(e.date!)].join(' · '),
                if (e.snippet.isNotEmpty) e.snippet,
              ].join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
              isThreeLine: e.snippet.isNotEmpty,
              onTap: () => launchUrl(e.link, mode: LaunchMode.externalApplication),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Open in Gmail',
                  icon: const Icon(Icons.open_in_new, size: 20),
                  onPressed: () => launchUrl(e.link, mode: LaunchMode.externalApplication),
                ),
                if (!archived)
                  IconButton(
                    tooltip: 'Remove from this task',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => widget.store.removeEmail(task, e)),
                  ),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, box) {
          // In a narrow pane the buttons shrink to icons so "Checklist 0/3" keeps its room.
          final narrow = box.maxWidth < 420;
          Future<void> editAll() async {
            await Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => StepsEditPage(store: widget.store, task: task)));
            if (mounted) setState(() {});
          }

          final canEditAll = task.steps.length >= 2 && !archived;
          return Row(children: [
            const Icon(Icons.checklist),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                task.steps.isEmpty ? 'Checklist' : 'Checklist  ${task.stepsDone}/${task.steps.length}',
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canEditAll && narrow)
              IconButton(tooltip: 'Edit all steps', icon: const Icon(Icons.edit_calendar_outlined), onPressed: editAll),
            if (canEditAll && !narrow)
              TextButton.icon(
                onPressed: editAll,
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: const Text('Edit all'),
              ),
            if (narrow)
              IconButton(tooltip: 'Templates', icon: const Icon(Icons.library_add_outlined), onPressed: _templateMenu)
            else
              TextButton.icon(
                onPressed: _templateMenu,
                icon: const Icon(Icons.library_add_outlined, size: 18),
                label: const Text('Templates'),
              ),
          ]);
        }),
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
                subtitle: s.taskId == null &&
                        !task.boardSteps.contains(s) &&
                        s.dueAt == null &&
                        s.note.isEmpty &&
                        s.carried == null
                    ? null
                    : Text([
                        if (s.carried != null) 'Was a task: ${carriedSummary(s, data, short: true).join(', ')}',
                        if (s.dueAt != null)
                          'Due ${dateTimeFmt.format(s.dueAt!)}${s.remindBefore != null && s.remindBefore! > 0 ? ' (${remindOptions[s.remindBefore] ?? '${s.remindBefore} min before'})' : ''}',
                        if (s.taskId != null) 'Task: ${data.task(s.taskId)?.title ?? '(deleted)'}',
                        if (task.boardSteps.contains(s)) 'Board: ${data.stage(s.stageId)?.name ?? '?'}',
                        if (s.note.isNotEmpty) s.note,
                      ].join(' · ')),
                onTap: () => _stepMenu(s),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (s.dueAt != null && !s.done)
                    Icon(Icons.event, size: 18, color: s.dueAt!.isBefore(DateTime.now()) ? Colors.red : null),
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
          subtitle: Text('${dateTimeFmt.format(task.createdAt)}\nFrom: ${TaskSource.label(task.source)}'),
          isThreeLine: true,
          trailing: _mapButton(task.addedWhere),
        ),
        if (task.splitFrom != null)
          Builder(builder: (context) {
            final from = data.task(task.splitFrom);
            return ListTile(
              leading: const Icon(Icons.call_split),
              title: const Text('Split from'),
              subtitle: Text(from?.title ?? '(a task since deleted)'),
              onTap: from == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: widget.store, task: from))),
            );
          }),
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
              setState(() => widget.store.setCategory(task, v));
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
        if (task.repeat != null && !archived)
          ListTile(
            leading: const Icon(Icons.skip_next),
            title: const Text('Skip this time'),
            subtitle: const Text('Move it to the next date without ticking it off'),
            onTap: _skip,
          ),
        if (!archived && (PlaceReminders.supported || task.place != null))
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: const Text('Place reminder'),
            subtitle: Text(task.place == null
                ? 'Remind me when I arrive at or leave a place'
                : '${task.placeLeave ? 'When I leave' : 'When I arrive at'} ${task.place}'
                    '${!PlaceReminders.supported || widget.store.places.any((p) => p.name == task.place) ? '' : ' (not saved on this phone)'}'),
            onTap: PlaceReminders.supported ? _pickPlace : null,
            trailing: task.place == null
                ? null
                : IconButton(
                    tooltip: 'Remove place reminder',
                    icon: const Icon(Icons.clear),
                    onPressed: () => _update(() {
                      task.place = null;
                      task.placeLeave = false;
                    }),
                  ),
          ),
        ..._habit(context),
        ..._worked(context),
        ..._board(context),
        ..._matrix(context),
        ..._gantt(context),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Time needed'),
          subtitle: Text(task.estimate == null ? 'Not set' : 'About ${describeMinutes(task.estimate!)}'),
          onTap: archived ? null : _pickEstimate,
          trailing: task.estimate == null || archived
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear),
                  onPressed: () => _update(() => task.estimate = null),
                ),
        ),
        if (!archived) ...[
          ListTile(
            leading: Icon(data.isLocked(task) ? Icons.lock_outline : Icons.link),
            title: const Text('Comes after'),
            subtitle: Text(task.afterIds.isEmpty
                ? 'Nothing (can be done any time)'
                : [for (final id in task.afterIds) anyTask(data, id)?.title ?? '(deleted task)'].join(', ')),
            onTap: _editAfter,
            trailing: task.afterIds.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Add another',
                    icon: const Icon(Icons.add),
                    onPressed: _pickAfter,
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
            trailing: _mapButton(task.doneWhere),
          ),
      ]),
    );
  }

  Future<DateTime?> _pickDay(String help, DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      helpText: help,
      initialDate: initial,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 10),
    );
  }

  Future<int?> _askDays(String title, int? initial) async {
    final v = await askText(context, title, initial: initial?.toString() ?? '');
    if (v == null) return null;
    return int.tryParse(v.trim().split(' ').first);
  }

  /// Item 78: the Habit switch, and how often once it is one.
  List<Widget> _habit(BuildContext context) {
    if (archived && !task.habit) return [];
    final now = DateTime.now();
    final n = streak(task, now);
    void edit(VoidCallback f) => _update(f);
    return [
      if (!archived)
        SwitchListTile(
          secondary: const Icon(Icons.repeat_on_outlined),
          title: Text(task.repeat != null && !task.habit ? 'Make into a habit' : 'Habit'),
          subtitle: Text(task.habit
              ? '${goalText(task)}${n > 0 ? ' · streak ${streakText(task, n)}' : ''}'
              : task.repeat != null
                  ? 'Tick the days instead of ticking it off; the days it was done are kept'
                  : 'Tick the days you do it instead of ticking it off'),
          value: task.habit,
          onChanged: (v) => setState(() => widget.store.setHabit(task, v)),
        ),
      if (task.habit && !archived) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 4),
          child: SegmentedButton<HabitGoal>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [for (final g in HabitGoal.values) ButtonSegment(value: g, label: Text(g.label))],
            selected: {task.habitGoal},
            onSelectionChanged: (v) => edit(() => task.habitGoal = v.first),
          ),
        ),
        if (task.habitGoal == HabitGoal.perWeek)
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(72, 0, 16, 0),
            title: Text('${task.habitTimes} time${task.habitTimes == 1 ? '' : 's'} a week'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Fewer',
                icon: const Icon(Icons.remove),
                onPressed: task.habitTimes <= 1 ? null : () => edit(() => task.habitTimes--),
              ),
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.add),
                onPressed: task.habitTimes >= 7 ? null : () => edit(() => task.habitTimes++),
              ),
            ]),
          ),
        if (task.habitGoal == HabitGoal.weekdays)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 4),
            child: Wrap(spacing: 4, children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1]),
                  selected: task.habitDays.contains(d),
                  onSelected: (on) => edit(() {
                    if (on) {
                      task.habitDays.add(d);
                    } else if (task.habitDays.length > 1) {
                      task.habitDays.remove(d);
                    }
                  }),
                ),
            ]),
          ),
        if (task.habitGoal == HabitGoal.daily)
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(72, 0, 16, 0),
            title: const Text('One free missed day a week'),
            subtitle: const Text('Missing one day doesn\'t break the streak'),
            value: task.habitFreeMiss,
            onChanged: (v) => edit(() => task.habitFreeMiss = v),
          ),
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(72, 0, 16, 0),
          title: const Text('Remind me if not done'),
          subtitle: Text(task.habitRemind == null
              ? 'Off'
              : 'At ${TimeOfDay(hour: task.habitRemind! ~/ 60, minute: task.habitRemind! % 60).format(context)}, only on days it isn\'t ticked'),
          trailing: task.habitRemind == null
              ? null
              : IconButton(
                  tooltip: 'No reminder',
                  icon: const Icon(Icons.clear),
                  onPressed: () => edit(() => task.habitRemind = null),
                ),
          onTap: () async {
            final r = task.habitRemind ?? 20 * 60;
            final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: r ~/ 60, minute: r % 60));
            if (picked != null) edit(() => task.habitRemind = picked.hour * 60 + picked.minute);
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(72, 0, 16, 0),
          title: Text(task.habitPaused ? 'Paused' : 'Pause'),
          subtitle: Text(task.habitPaused ? 'Tap to carry on; the streak was kept' : 'Away or ill? Paused days don\'t count'),
          trailing: Switch(value: task.habitPaused, onChanged: (v) => setState(() => widget.store.pauseHabit(task, v))),
        ),
      ],
    ];
  }

  /// Item 75: the days worked this week, tapped to tick.
  List<Widget> _worked(BuildContext context) {
    if (archived && task.worked.isEmpty) return [];
    final week = task.workedInWeek(DateTime.now());
    return [
      ListTile(
        leading: const Icon(Icons.event_available_outlined),
        title: Text(task.habit ? 'Days done' : 'Days worked on it'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            WorkedWeek(
              task: task,
              onToggle: archived ? null : (d) => setState(() => widget.store.setWorked(task, d, !task.workedOn(d))),
            ),
            const SizedBox(height: 4),
            Text(task.worked.isEmpty
                ? 'Tick a day you worked on it, even if it isn\'t finished'
                : '$week ${week == 1 ? 'day' : 'days'} this week, ${task.worked.length} in all'),
          ]),
        ),
      ),
    ];
  }

  /// Item 72: On the Gantt chart, start, how long it takes, milestone and progress.
  List<Widget> _gantt(BuildContext context) {
    if (task.habit || archived && !task.gantt) return [];
    final theme = Theme.of(context);
    final fmt = DateFormat('EEE d MMM');
    final bar = barFor(task, data);
    final weekends = weekendsFor(task, data);
    void changedGantt(VoidCallback f) {
      setState(f);
      widget.store.ganttChanged(task);
    }

    return [
      if (!archived)
        SwitchListTile(
          secondary: const Icon(Icons.view_timeline_outlined),
          title: const Text('On the Gantt chart'),
          subtitle: Text(!task.gantt
              ? 'Off'
              : bar == null
                  ? 'Needs a start or due date'
                  : task.milestone
                      ? 'Milestone on ${fmt.format(bar.start)}'
                      : '${fmt.format(bar.start)} to ${fmt.format(bar.end)}'),
          value: task.gantt,
          onChanged: (on) async {
            DateTime? start;
            if (on && task.startAt == null && task.dueAt == null) {
              start = await _pickDay('When does it start?', earliestStart(task, data) ?? dayOf(DateTime.now()));
              if (!mounted) return;
            }
            setState(() => widget.store.setOnGantt(task, on, start: start));
          },
        ),
      if (task.gantt) ...[
        if (bar != null)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: const Text('Show on the Gantt chart'),
            subtitle: const Text('Zoomed in on this task and its steps'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => GanttPage(store: widget.store, focusTaskId: task.id))),
          ),
        ListTile(
          contentPadding: const EdgeInsets.only(left: 72, right: 16),
          title: const Text('Starts'),
          subtitle: Text(task.startAt != null
              ? fmt.format(task.startAt!)
              : bar != null
                  ? 'Not set: counted back from the due date (${fmt.format(bar.start)})'
                  : 'Not set'),
          onTap: archived
              ? null
              : () async {
                  final d = await _pickDay(
                      'When does it start?', task.startAt ?? earliestStart(task, data) ?? dayOf(DateTime.now()));
                  if (d != null) changedGantt(() => task.startAt = d);
                },
          trailing: task.startAt == null || archived
              ? null
              : IconButton(
                  tooltip: 'Clear start',
                  icon: const Icon(Icons.clear),
                  onPressed: () => changedGantt(() => task.startAt = null),
                ),
        ),
        if (!task.milestone) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: const Text('Takes'),
            subtitle: Text(task.takesDays == null
                ? 'Not set: the bar ends on the due date'
                : '${task.takesDays} ${weekends ? '' : 'work '}day${task.takesDays == 1 ? '' : 's'}'),
            onTap: archived
                ? null
                : () async {
                    final n = await _askDays('How many days does it take?', task.takesDays);
                    if (n != null && n > 0) changedGantt(() => task.takesDays = n);
                  },
            trailing: task.takesDays == null || archived
                ? null
                : IconButton(
                    tooltip: 'Clear length',
                    icon: const Icon(Icons.clear),
                    onPressed: () => changedGantt(() => task.takesDays = null),
                  ),
          ),
          if (task.takesDays != null)
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 72, right: 16),
              title: const Text('Count weekends'),
              subtitle: const Text('Off: Saturdays and Sundays are skipped'),
              value: weekends,
              onChanged: archived ? null : (v) => changedGantt(() => task.countWeekends = v),
            ),
          if (bar != null && task.takesDays != null && !archived)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text(
                bar.late
                    ? 'Expected to finish ${fmt.format(bar.end)}, ${bar.lateDays} day${bar.lateDays == 1 ? '' : 's'} after it\'s due'
                    : 'Expected to finish ${fmt.format(bar.end)}',
                style: TextStyle(color: bar.late ? theme.colorScheme.error : null),
              ),
            ),
        ],
        if (task.afterIds.isNotEmpty)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: const Text('Wait after what it comes after'),
            subtitle: Text(task.lagDays == null || task.lagDays == 0
                ? 'No wait'
                : '${task.lagDays} day${task.lagDays == 1 ? '' : 's'}'),
            onTap: archived
                ? null
                : () async {
                    final n = await _askDays('Days to wait (paint drying, delivery…)', task.lagDays);
                    if (n != null && n >= 0) changedGantt(() => task.lagDays = n == 0 ? null : n);
                  },
          ),
        if (clashes(task, data))
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Text('Starts before what it comes after is done (earliest ${fmt.format(earliestStart(task, data)!)})',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        SwitchListTile(
          contentPadding: const EdgeInsets.only(left: 72, right: 16),
          title: const Text('Milestone'),
          subtitle: const Text('One day, shown as a diamond'),
          value: task.milestone,
          onChanged: archived ? null : (v) => changedGantt(() => task.milestone = v),
        ),
        if (!task.milestone)
          task.steps.isNotEmpty && task.progress == null
              ? ListTile(
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  title: const Text('Progress'),
                  subtitle: Text('${task.stepsDone} of ${task.steps.length} steps (${(task.progressShare * 100).round()}%)'),
                )
              : Padding(
                  padding: const EdgeInsets.only(left: 72, right: 16),
                  child: Row(children: [
                    const Text('Progress'),
                    Expanded(
                      child: Slider(
                        value: (task.progress ?? 0).toDouble(),
                        max: 100,
                        divisions: 10,
                        label: '${task.progress ?? 0}%',
                        onChanged: archived ? null : (v) => setState(() => task.progress = v.round()),
                        onChangeEnd: archived ? null : (_) => widget.store.ganttChanged(task),
                      ),
                    ),
                    Text('${task.progress ?? 0}%'),
                  ]),
                ),
        if (task.planStart != null && task.planDue != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Text(
              'First planned ${DateFormat('d MMM').format(task.planStart!)} to ${DateFormat('d MMM').format(task.planDue!)}'
              '${bar != null && daysBetween(task.planDue!, bar.end) > 0 ? ' · now ${daysBetween(task.planDue!, bar.end)} day${daysBetween(task.planDue!, bar.end) == 1 ? '' : 's'} later' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    ];
  }

  /// Item 60: the On the matrix switch, the box, and "Waiting on" for Delegate.
  List<Widget> _matrix(BuildContext context) {
    final box = MatrixBox.byId(task.matrixBox);
    if (task.habit || archived && box == null) return [];
    final urgent = widget.store.looksUrgent(task, DateTime.now());
    return [
      if (!archived)
        SwitchListTile(
          secondary: const Icon(Icons.grid_view),
          title: const Text('On the matrix'),
          subtitle: Text(box == null
              ? 'Off'
              : '${data.boxName(box)}: ${box.meaning}${urgent ? '. Due soon: urgent?' : ''}'),
          value: box != null,
          onChanged: (v) async {
            if (!v) {
              setState(() => widget.store.setBox(task, null));
              return;
            }
            final picked = await _pickBox();
            if (picked == null || !mounted) return;
            await putInBox(this.context, widget.store, task, picked);
            if (!mounted) return;
            setState(() {});
            if (task.closedAt != null || !data.active.contains(task)) _close();
          },
        ),
      if (box != null && !archived)
        ListTile(
          leading: const SizedBox(width: 24),
          title: const Text('Box'),
          subtitle: DropdownButton<MatrixBox>(
            isExpanded: true,
            value: box,
            items: [
              for (final b in MatrixBox.values) DropdownMenuItem(value: b, child: Text('${data.boxName(b)}: ${b.meaning}')),
            ],
            onChanged: (b) async {
              if (b == null || b == box) return;
              await putInBox(this.context, widget.store, task, b);
              if (!mounted) return;
              setState(() {});
              if (task.closedAt != null || !data.active.contains(task)) _close();
            },
          ),
        ),
      if (box == MatrixBox.delegate || (task.waitingOn ?? '').isNotEmpty)
        ListTile(
          leading: const SizedBox(width: 24),
          title: const Text('Waiting on'),
          subtitle: Text((task.waitingOn ?? '').isEmpty ? 'Nobody yet' : task.waitingOn!),
          onTap: archived
              ? null
              : () async {
                  final who = await askText(context, 'Waiting on', initial: task.waitingOn ?? '');
                  if (who != null) setState(() => widget.store.setWaitingOn(task, who));
                },
        ),
    ];
  }

  Future<MatrixBox?> _pickBox() => showDialog<MatrixBox>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Which box?'),
          children: [
            for (final b in MatrixBox.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, b),
                child: ListTile(title: Text(data.boxName(b)), subtitle: Text(b.meaning)),
              ),
          ],
        ),
      );

  /// Item 52: the On the Kanban board switch, the stage, and the board history.
  List<Widget> _board(BuildContext context) {
    final stages = data.stages;
    if (task.habit || stages.isEmpty && task.moves.isEmpty) return [];
    final current = data.stage(task.stageId) ?? stages.firstOrNull;
    final hint = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    return [
      if (!archived && stages.isNotEmpty)
        SwitchListTile(
          secondary: const Icon(Icons.view_kanban_outlined),
          title: const Text('On the Kanban board'),
          subtitle: Text(task.kanban
              ? 'In ${current?.name}${task.stageSince == null ? '' : ' for ${describeSpell(DateTime.now().difference(task.stageSince!))}'}'
              : task.moves.isEmpty
                  ? 'Off'
                  : 'Off. Goes back to ${current?.name}'),
          value: task.kanban,
          onChanged: (v) => setState(() => widget.store.setOnBoard(task, v)),
        ),
      if (task.kanban && !archived && current != null)
        ListTile(
          leading: const SizedBox(width: 24),
          title: const Text('Stage'),
          subtitle: DropdownButton<String>(
            isExpanded: true,
            value: current.id,
            items: [for (final s in stages) DropdownMenuItem(value: s.id, child: Text(s.name))],
            onChanged: (id) async {
              final to = data.stage(id);
              if (to == null) return;
              await moveWithRule(context, widget.store, task, to, MoveHow.taskPage);
              if (mounted) setState(() {});
              if (task.closedAt != null && mounted) _close();
            },
          ),
        ),
      if (task.kanban && !archived)
        SwitchListTile(
          secondary: const SizedBox(width: 24),
          title: const Text('Steps on the board too'),
          subtitle: const Text('Each checklist step gets its own card and moves through the stages by itself'),
          value: task.stepsOnBoard,
          onChanged: (v) => setState(() => widget.store.setStepsOnBoard(task, v)),
        ),
      if (task.steps.any((st) => st.moves.isNotEmpty))
        ExpansionTile(
          leading: const Icon(Icons.history),
          title: const Text("Steps' board history"),
          subtitle: Text('${task.steps.fold(0, (n, st) => n + st.moves.length)} moves'),
          childrenPadding: const EdgeInsets.only(left: 56, right: 8, bottom: 8),
          children: [
            for (final (st, m) in [
              for (final st in task.steps)
                for (final m in st.moves) (st, m),
            ]..sort((x, y) => y.$2.at.compareTo(x.$2.at)))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${st.title}: ${switch ((m.fromName, m.toName)) {
                  (null, final to?) => 'onto the board, $to',
                  (final from?, null) => 'off the board (was in $from)',
                  (final from, final to) => '${from ?? '?'} → ${to ?? '?'}',
                }}'),
                subtitle: Text(
                  [dateTimeFmt.format(m.at), MoveHow.label(m.how), ?m.device, if (m.note != null) '"${m.note}"'].join(' · '),
                  style: hint,
                ),
                trailing: _mapButton(m.where),
              ),
          ],
        ),
      if (task.moves.isNotEmpty)
        ExpansionTile(
          leading: const Icon(Icons.history),
          title: const Text('Board history'),
          subtitle: Text('${task.moves.length} move${task.moves.length == 1 ? '' : 's'}'),
          childrenPadding: const EdgeInsets.only(left: 56, right: 8, bottom: 8),
          children: [
            for (final (i, m) in task.moves.indexed.toList().reversed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(switch ((m.fromName, m.toName)) {
                  (null, final to?) => 'Onto the board: $to',
                  (final from?, null) => 'Off the board (was in $from)',
                  (final from, final to) => '${from ?? '?'} → ${to ?? '?'}',
                }),
                subtitle: Text(
                  [
                    dateTimeFmt.format(m.at),
                    if (i > 0 && m.fromId != null) 'after ${describeSpell(m.at.difference(task.moves[i - 1].at))}',
                    MoveHow.label(m.how),
                    ?m.device,
                    if (m.note != null) '"${m.note}"',
                  ].join(' · '),
                  style: hint,
                ),
                trailing: _mapButton(m.where),
              ),
          ],
        ),
    ];
  }

  /// Opens a recorded location in the maps app.
  Widget? _mapButton(GeoPoint? where) => where == null
      ? null
      : IconButton(
          tooltip: 'Recorded at $where${where.accuracy == null ? '' : ' (±${where.accuracy!.round()} m)'}. Open in maps',
          icon: const Icon(Icons.place_outlined),
          onPressed: () => launchUrl(
            Uri.parse('https://www.google.com/maps/search/?api=1&query=${where.lat},${where.lng}'),
            mode: LaunchMode.externalApplication,
          ),
        );
}

/// Item 73: what a step made from a task is carrying, one line each (shorter labels with
/// [short], for the checklist row).
List<String> carriedSummary(TaskStep s, AppData data, {bool short = false}) {
  final t = s.carriedTask;
  if (t == null) return const ['its saved details'];
  final cat = data.category(t.categoryId)?.name;
  final steps = t.steps.length;
  final out = [
    if (cat != null) short ? cat : 'Category: $cat',
    if (t.starred) 'starred',
    if (steps > 0) '$steps step${steps == 1 ? '' : 's'}${short ? ' inside' : ' of its own'}',
    if (t.emails.isNotEmpty) '${t.emails.length} email${t.emails.length == 1 ? '' : 's'}',
    if (t.repeat != null) 'repeats',
    if (t.place != null) short ? 'place' : 'Place reminder: ${t.place}',
    if (t.kanban) short ? 'board' : 'On the Kanban board',
    if (t.matrixBox != null) short ? 'matrix' : 'On the matrix',
    if (t.notes.trim().length > 200) short ? 'long notes' : 'Full notes (${t.notes.trim().length} characters)',
    if (!short) 'Added ${dateTimeFmt.format(t.createdAt)}',
  ];
  return out.isEmpty ? const ['its saved details'] : out;
}
