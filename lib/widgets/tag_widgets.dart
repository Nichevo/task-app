import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../tags.dart';

/// Item 107: the "Tags" row on a task's page: its tags (✕ takes one off) and "Add tag".
class TaskTagsTile extends StatelessWidget {
  const TaskTagsTile({super.key, required this.store, required this.task, this.onChanged});

  final AppStore store;
  final Task task;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.tag),
    title: const Text('Tags'),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final x in task.tags)
            InputChip(
              label: Text('#$x'),
              visualDensity: VisualDensity.compact,
              tooltip: 'Tap ✕ to take this tag off',
              onDeleted: () {
                store.removeTag(task, x);
                onChanged?.call();
              },
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: Text(task.tags.isEmpty ? 'Add a tag' : 'Add'),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await showTaskTagsSheet(context, store, task);
              onChanged?.call();
            },
          ),
        ],
      ),
    ),
  );
}

/// A sheet to type a new tag or tick ones already in use, for [task].
Future<void> showTaskTagsSheet(BuildContext context, AppStore store, Task task) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (c) => _TaskTagsSheet(store: store, task: task),
);

class _TaskTagsSheet extends StatefulWidget {
  const _TaskTagsSheet({required this.store, required this.task});
  final AppStore store;
  final Task task;

  @override
  State<_TaskTagsSheet> createState() => _TaskTagsSheetState();
}

class _TaskTagsSheetState extends State<_TaskTagsSheet> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add() {
    final text = _field.text;
    // Several at once: "meeting, coding" or "#meeting #coding".
    for (final part in text.split(RegExp(r'[,;]|\s(?=#)'))) {
      widget.store.addTag(widget.task, part);
    }
    _field.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final typed = tagKey(_field.text);
    final all = tagsInUse(widget.store.data);
    final shown = [
      for (final x in all)
        if (typed.isEmpty || tagKey(x.tag).contains(typed)) x,
    ];
    final isNew = typed.isNotEmpty && !all.any((x) => tagKey(x.tag) == typed);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tags for "${task.title}"',
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Words like meeting, brainstorming or coding. Filter by them above the list, the board and the matrix.',
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _field,
            autofocus: all.isEmpty,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              prefixText: '#',
              hintText: 'New tag',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(icon: const Icon(Icons.add), tooltip: 'Add tag', onPressed: _add),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _add(),
          ),
          const SizedBox(height: 12),
          if (shown.isNotEmpty || isNew)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (isNew)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text('New: #${cleanTag(_field.text)}'),
                        onPressed: _add,
                      ),
                    for (final x in shown)
                      FilterChip(
                        label: Text('#${x.tag}'),
                        tooltip: '${x.open} open task${x.open == 1 ? '' : 's'}',
                        selected: hasTag(task, x.tag),
                        onSelected: (on) {
                          on ? widget.store.addTag(task, x.tag) : widget.store.removeTag(task, x.tag);
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ),
        ],
      ),
    );
  }
}

/// The chip at the start of a filter row: "Tags", or the tags picked. Tapping it opens a sheet
/// to pick tags. Nothing shows until some task has a tag (or a filter is still set).
class TagFilterChip extends StatelessWidget {
  const TagFilterChip({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final picked = store.liveTagFilter;
    if (picked.isEmpty && tagsInUse(store.data).isEmpty) return const SizedBox.shrink();
    final names = [for (final f in picked) f == untaggedFilter ? 'No tag' : '#$f'];
    final label = names.isEmpty
        ? 'All tags'
        : names.length == 1
        ? names.first
        : '${names.first} +${names.length - 1}';
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        avatar: picked.isEmpty ? const Icon(Icons.tag, size: 18) : null,
        label: Text(label),
        selected: picked.isNotEmpty,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        tooltip: 'Show only tasks with these tags',
        onPressed: () => showTagFilterSheet(context, store),
        onDeleted: picked.isEmpty ? null : () => store.setTagFilter(const []),
      ),
    );
  }
}

/// Picks the tags the list, board and matrix show. A task shows when it has any of them.
Future<void> showTagFilterSheet(BuildContext context, AppStore store) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (c) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final picked = store.liveTagFilter;
      final all = tagsInUse(store.data);
      void toggle(String f, bool on) {
        final next = {...picked};
        if (on) {
          next.add(f);
        } else {
          next.removeWhere(
            (x) => f == untaggedFilter ? x == untaggedFilter : x != untaggedFilter && tagKey(x) == tagKey(f),
          );
        }
        store.setTagFilter(next);
      }

      bool isPicked(String f) =>
          picked.any((x) => f == untaggedFilter ? x == untaggedFilter : x != untaggedFilter && tagKey(x) == tagKey(f));
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Show tasks tagged', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Pick one or more: a task shows when it has any of them. Used by the list, the board and the matrix.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final x in all)
                      FilterChip(
                        label: Text('#${x.tag}  ${x.open}'),
                        selected: isPicked(x.tag),
                        onSelected: (on) => toggle(x.tag, on),
                      ),
                    FilterChip(
                      label: const Text('No tag'),
                      selected: isPicked(untaggedFilter),
                      onSelected: (on) => toggle(untaggedFilter, on),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: picked.isEmpty ? null : () => store.setTagFilter(const []),
                  child: const Text('Show all'),
                ),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ],
            ),
          ],
        ),
      );
    },
  ),
);

/// Item 107: Settings > Tags: every tag with how many tasks have it; rename (which merges into
/// a tag of that name) or delete.
class TagsPage extends StatelessWidget {
  const TagsPage({super.key, required this.store});
  final AppStore store;

  Future<String?> _ask(BuildContext context, String title, String initial) {
    final field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(prefixText: '#'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, field.text), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tags')),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = tagsInUse(store.data);
        if (all.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No tags yet. Add them on a task\'s page (Tags), or type #word in the add box: '
              'a #word that isn\'t a category becomes a tag.',
            ),
          );
        }
        return ListView(
          children: [
            for (final x in all)
              ListTile(
                leading: const Icon(Icons.tag),
                title: Text(x.tag),
                subtitle: Text(
                  '${x.open} open'
                  '${x.all > x.open ? ', ${x.all - x.open} ticked off' : ''}',
                ),
                onTap: () async {
                  final name = await _ask(context, 'Rename #${x.tag}', x.tag);
                  if (name != null && cleanTag(name).isNotEmpty) store.renameTag(x.tag, name);
                },
                trailing: IconButton(
                  tooltip: 'Delete tag',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Delete #${x.tag}?'),
                        content: Text('It comes off ${x.all} task${x.all == 1 ? '' : 's'}. The tasks stay.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) store.deleteTag(x.tag);
                  },
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Tap a tag to rename it. Renaming to a tag that already exists joins the two.'),
            ),
          ],
        );
      },
    ),
  );
}
