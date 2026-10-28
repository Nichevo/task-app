import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../input_parse.dart';
import '../models.dart';
import '../store.dart';

final _dayFmt = DateFormat('EEE d MMM, HH:mm');

/// Offers one task per line (from a pasted list, a photo or shared text), each with the
/// date and category read out of it, and adds the ticked ones.
Future<void> showAddManyDialog(BuildContext context, AppStore store, List<String> lines, {String? title}) async {
  if (lines.isEmpty) return;
  final added = await showDialog<List<Task>>(
    context: context,
    builder: (_) => _AddManyDialog(store: store, lines: lines, title: title),
  );
  if (added != null && added.isNotEmpty && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${added.length} task${added.length == 1 ? '' : 's'}')),
    );
  }
}

class _AddManyDialog extends StatefulWidget {
  const _AddManyDialog({required this.store, required this.lines, this.title});

  final AppStore store;
  final List<String> lines;
  final String? title;

  @override
  State<_AddManyDialog> createState() => _AddManyDialogState();
}

class _AddManyDialogState extends State<_AddManyDialog> {
  late final List<bool> _picked = List.filled(widget.lines.length, true);
  late final List<ParsedInput> _parsed = [
    for (final l in widget.lines) parseInput(l, widget.store.data, DateTime.now()),
  ];

  @override
  Widget build(BuildContext context) {
    final data = widget.store.data;
    final n = _picked.where((p) => p).length;
    return AlertDialog(
      title: Text(widget.title ?? 'Add ${widget.lines.length} tasks?'),
      content: SizedBox(
        width: 420,
        child: ListView(shrinkWrap: true, children: [
          for (final (i, p) in _parsed.indexed)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _picked[i],
              onChanged: (v) => setState(() => _picked[i] = v ?? false),
              title: Text(p.title),
              subtitle: p.due == null && p.categoryId == null
                  ? null
                  : Text([
                      if (p.due != null) 'Due ${_dayFmt.format(p.due!)}',
                      if (p.categoryId != null) data.category(p.categoryId)?.name ?? '',
                    ].join(' · ')),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: n == 0
              ? null
              : () {
                  final lines = [for (final (i, l) in widget.lines.indexed) if (_picked[i]) l];
                  Navigator.pop(context, widget.store.addMany(lines));
                },
          child: Text('Add $n'),
        ),
      ],
    );
  }
}

/// Adds one task with a name and notes already filled in (e.g. text shared from another app).
Future<Task?> showAddTaskDialog(BuildContext context, AppStore store, {required String title, String notes = ''}) {
  final name = TextEditingController(text: title);
  final notesField = TextEditingController(text: notes);
  return showDialog<Task>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Add task'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Task', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesField,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty) return;
            final p = parseInput(name.text, store.data, DateTime.now());
            Navigator.pop(c, store.addTask(p.title, due: p.due, categoryId: p.categoryId, notes: notesField.text.trim()));
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
