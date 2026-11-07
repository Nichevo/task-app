import 'package:flutter/material.dart';

import '../gantt.dart';
import '../models.dart';
import '../store.dart';
import '../screens/starred_page.dart' show pickTask;

/// Item 85: linking steps. Shared by the task page's step menu and "Edit all steps".

/// Asks which other steps [s] comes after. Steps that would make a loop can't be picked.
/// Returns the chosen ids, or null on Cancel.
Future<List<String>?> pickStepsBefore(BuildContext context, Task t, TaskStep s) {
  final chosen = {...s.afterIds};
  final others = [for (final o in t.steps) if (o.id != s.id) o];
  return showDialog<List<String>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('"${s.title}" comes after'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('It can only start once these end. If one of them moves later, this step moves too.'),
            ),
            for (final o in others)
              Builder(builder: (c) {
                final loop = !chosen.contains(o.id) && stepWouldLoop(t, s, o);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: chosen.contains(o.id),
                  title: Text(o.title, style: TextStyle(decoration: o.done ? TextDecoration.lineThrough : null)),
                  subtitle: loop ? const Text('Already comes after this step') : null,
                  onChanged: loop ? null : (v) => set(() => v == true ? chosen.add(o.id) : chosen.remove(o.id)),
                );
              }),
          ]),
        ),
        actions: [
          if (chosen.isNotEmpty) TextButton(onPressed: () => set(chosen.clear), child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, [for (final o in others) if (chosen.contains(o.id)) o.id]),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

/// Asks and sets what [s] comes after, saying how many later steps moved. Returns true when
/// something changed.
Future<bool> editStepsBefore(BuildContext context, AppStore store, Task t, TaskStep s) async {
  final ids = await pickStepsBefore(context, t, s);
  if (ids == null || !context.mounted) return false;
  final moved = store.setStepAfter(t, s, ids);
  if (moved > 0) showMovedSnack(context, moved);
  return true;
}

void showMovedSnack(BuildContext context, int moved) => ScaffoldMessenger.of(context)
  ..clearSnackBars()
  ..showSnackBar(SnackBar(
      content: Text('Moved $moved step${moved == 1 ? '' : 's'} later to keep them in order')));

/// Links [s] to a task that already exists (not [t] itself). Returns true when linked.
Future<bool> linkStepToTask(BuildContext context, AppStore store, Task t, TaskStep s) async {
  final other = await pickTask(context, store.data, title: 'Link "${s.title}" to which task?', exclude: t);
  if (other == null || !context.mounted) return false;
  store.linkStep(t, s, other);
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text('Linked: ticking off "${other.title}" ticks this step')));
  return true;
}

/// The linked task's name for a step ("Task: Book flights"), or null.
String? stepLinkLabel(TaskStep s, AppData data) {
  final id = s.taskId;
  if (id == null) return null;
  return 'Task: ${anyTask(data, id)?.title ?? '(deleted)'}';
}
