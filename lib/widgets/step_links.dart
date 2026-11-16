import 'package:flutter/material.dart';

import '../gantt.dart';
import '../models.dart';
import '../store.dart';

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

/// Item 106: what a step can be linked to: a whole task, or one step of a task.
typedef LinkTarget = ({Task task, TaskStep? step});

/// Finds a step by id in any task, open or ticked off, with the task it is in.
LinkTarget? stepAnywhere(AppData data, String id) {
  for (final t in [...data.active, ...data.archived]) {
    for (final s in t.steps) {
      if (s.id == id) return (task: t, step: s);
    }
  }
  return null;
}

/// Item 106: the open tasks and steps [s] (a step of [t]) could link to, smartest first: other
/// steps of [t], then tasks in [t]'s category with their steps, then everything else. Each
/// group keeps starred tasks first, then board tasks. [query] keeps a task when its name or
/// one of its steps matches, and keeps only the steps that match unless the task's name does.
List<({String heading, List<LinkTarget> rows})> linkChoices(AppData data, Task t, TaskStep s, {String query = ''}) {
  final q = query.trim().toLowerCase();
  bool hit(String title) => q.isEmpty || title.toLowerCase().contains(q);
  List<LinkTarget> rowsOf(Task x) {
    final steps = [for (final o in x.steps) if (!o.done && o.id != s.id) o];
    final whole = hit(x.title);
    final shown = whole ? steps : steps.where((o) => hit(o.title)).toList();
    if (!whole && shown.isEmpty) return const [];
    return [(task: x, step: null), for (final o in shown) (task: x, step: o)];
  }

  int rank(Task x) => x.starred ? 0 : x.kanban ? 1 : 2;
  final others = [for (final x in data.active) if (x != t) x];
  // A stable sort keeps the list's own order within each rank.
  final ranked = [for (var i = 0; i < others.length; i++) (i, others[i])]
    ..sort((a, b) => rank(a.$2) != rank(b.$2) ? rank(a.$2).compareTo(rank(b.$2)) : a.$1.compareTo(b.$1));
  final cat = t.categoryId == null ? null : data.category(t.categoryId);
  final same = <LinkTarget>[];
  final rest = <LinkTarget>[];
  for (final (_, x) in ranked) {
    (cat != null && x.categoryId == cat.id ? same : rest).addAll(rowsOf(x));
  }
  final own = [for (final o in t.steps) if (!o.done && o.id != s.id && hit(o.title)) (task: t, step: o)];
  return [
    if (own.isNotEmpty) (heading: 'Steps in this task', rows: own),
    if (same.isNotEmpty) (heading: 'In ${cat!.name}', rows: same),
    if (rest.isNotEmpty) (heading: cat == null ? 'Other tasks' : 'Everything else', rows: rest),
  ];
}

/// Asks which task or step to link [s] to, with a search box.
Future<LinkTarget?> pickLinkTarget(BuildContext context, AppData data, Task t, TaskStep s) {
  return showDialog<LinkTarget>(
    context: context,
    builder: (c) {
      var q = '';
      return StatefulBuilder(builder: (c, set) {
        final groups = linkChoices(data, t, s, query: q);
        final theme = Theme.of(c);
        return AlertDialog(
          title: Text('Link "${s.title}" to'),
          content: SizedBox(
            width: 440,
            height: 460,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tasks and steps'),
                onChanged: (v) => set(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: groups.isEmpty
                    ? const Center(child: Text('No open task or step matches.'))
                    : ListView(children: [
                        for (final g in groups) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 10, bottom: 2),
                            child: Text(g.heading,
                                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                          ),
                          for (final r in g.rows)
                            r.step == null
                                ? ListTile(
                                    key: ValueKey('link-task-${r.task.id}'),
                                    dense: true,
                                    leading: Icon(r.task.starred
                                        ? Icons.star
                                        : r.task.kanban
                                            ? Icons.view_kanban_outlined
                                            : Icons.radio_button_unchecked,
                                        color: r.task.starred ? Colors.amber : null),
                                    title: Text(r.task.title),
                                    subtitle: g.heading.startsWith('In ') || data.category(r.task.categoryId) == null
                                        ? null
                                        : Text(data.category(r.task.categoryId)!.name),
                                    onTap: () => Navigator.pop(c, r),
                                  )
                                : ListTile(
                                    key: ValueKey('link-step-${r.step!.id}'),
                                    dense: true,
                                    contentPadding: EdgeInsets.only(left: r.task == t ? 16 : 40, right: 16),
                                    leading: const Icon(Icons.check_box_outline_blank, size: 18),
                                    title: Text(r.step!.title),
                                    onTap: () => Navigator.pop(c, r),
                                  ),
                        ],
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

/// Links [s] to a task or step that already exists, asked with [pickLinkTarget]. A step of the
/// same task can instead be one [s] comes after. Returns true when something changed.
Future<bool> linkStepToTask(BuildContext context, AppStore store, Task t, TaskStep s) async {
  final pick = await pickLinkTarget(context, store.data, t, s);
  if (pick == null || !context.mounted) return false;
  final other = pick.step;
  final String said;
  if (other == null) {
    store.linkStep(t, s, pick.task);
    said = 'Linked: ticking off "${pick.task.title}" ticks this step';
  } else {
    final how = pick.task == t
        ? await showDialog<String>(
            context: context,
            builder: (c) => SimpleDialog(title: Text('Link to "${other.title}"'), children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'tick'),
                child: const Text('Ticking it ticks this step'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, 'after'),
                child: Text(stepWouldLoop(t, s, other)
                    ? 'Comes after it (can\'t: it already comes after this step)'
                    : 'This step comes after it (starts once it ends)'),
              ),
            ]),
          )
        : 'tick';
    if (how == null || !context.mounted) return false;
    if (how == 'after') {
      if (stepWouldLoop(t, s, other)) return false;
      final moved = store.setStepAfter(t, s, {...s.afterIds, other.id});
      if (moved > 0) showMovedSnack(context, moved);
      return true;
    }
    store.linkStepToStep(t, s, other);
    said = pick.task == t
        ? 'Linked: ticking "${other.title}" ticks this step'
        : 'Linked: ticking "${other.title}" in "${pick.task.title}" ticks this step';
  }
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(said)));
  return true;
}

/// The task holding the step [s] is linked to (for "Open task"), or the linked task itself.
Task? stepLinkedTask(TaskStep s, AppData data) {
  if (s.taskId != null) return anyTask(data, s.taskId!);
  if (s.linkStepId != null) return stepAnywhere(data, s.linkStepId!)?.task;
  return null;
}

/// Whether [s] is linked to a task or another step.
bool stepIsLinked(TaskStep s) => s.taskId != null || s.linkStepId != null;

/// The linked task's or step's name for a step ("Task: Book flights", "Step: Pay deposit
/// (Holiday)"), or null.
String? stepLinkLabel(TaskStep s, AppData data, {Task? within}) {
  final id = s.taskId;
  if (id != null) return 'Task: ${anyTask(data, id)?.title ?? '(deleted)'}';
  final sid = s.linkStepId;
  if (sid == null) return null;
  final found = stepAnywhere(data, sid);
  if (found == null) return 'Step: (deleted)';
  final where = found.task == within ? '' : ' (${found.task.title})';
  return 'Step: ${found.step!.title}$where';
}
