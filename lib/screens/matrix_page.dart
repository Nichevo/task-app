import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../store.dart';
import '../task_list.dart';
import '../widgets/task_colors.dart';
import 'settings_page.dart' show askText;
import 'task_page.dart';

/// Item 60: puts [t] in [box], doing what that box asks for first: Decide offers a due date
/// (item 89: "No date" puts it there without one),
/// Delegate an optional "Waiting on" note, and Delete offers to tick it off or delete it.
/// Returns false when the user cancelled.
Future<bool> putInBox(BuildContext context, AppStore store, Task t, MatrixBox box) async {
  final data = store.data;
  switch (box) {
    case MatrixBox.decide when t.dueAt == null:
      final now = DateTime.now();
      final day = await showDatePicker(
        context: context,
        helpText: 'When will you do it?',
        cancelText: 'No date',
        initialDate: now.add(const Duration(days: 1)),
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 5),
      );
      if (day != null) t.dueAt = DateTime(day.year, day.month, day.day, 9);
    case MatrixBox.delegate:
      if (!context.mounted) return false;
      final who = await askText(context, 'Waiting on (optional)', initial: t.waitingOn ?? '');
      if (who != null) t.waitingOn = who.trim().isEmpty ? null : who.trim();
    case MatrixBox.delete:
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text('${data.boxName(box)}: ${t.title}'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(c, 'box'), child: Text('Just put it in ${data.boxName(box)}')),
            SimpleDialogOption(onPressed: () => Navigator.pop(c, 'tick'), child: const Text('Tick it off')),
            SimpleDialogOption(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete the task')),
          ],
        ),
      );
      if (choice == null) return false;
      if (choice == 'tick') {
        store.complete(t);
        return true;
      }
      if (choice == 'delete') {
        store.delete(t);
        return true;
      }
    default:
      break;
  }
  store.setBox(t, box);
  return true;
}

/// The urgent / important matrix: the four boxes in a 2 by 2 grid, holding only the tasks put
/// on it. Drag a task between boxes, or use its menu.
class MatrixPage extends StatefulWidget {
  const MatrixPage({super.key, required this.store, this.initialBox});

  final AppStore store;

  /// Opened from a widget box: that box is highlighted.
  final MatrixBox? initialBox;

  @override
  State<MatrixPage> createState() => _MatrixPageState();
}

class _MatrixPageState extends State<MatrixPage> {
  bool _searching = false;
  final _search = TextEditingController();

  AppStore get store => widget.store;
  AppData get data => store.data;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setFilter(QuickFilter f, String? category) {
    setState(() {
      store.matrixFilter = f;
      store.matrixCategory = category;
    });
    store.saveDeviceSettings();
  }

  List<Task> _tasksIn(MatrixBox b, DateTime now) {
    final q = _searching ? _search.text.trim() : '';
    final cat = store.matrixCategory;
    return sortTasks([
      for (final t in data.matrixTasks)
        if (t.matrixBox == b.id &&
            passesFilter(t, store.matrixFilter, now) &&
            (cat == null || (cat.isEmpty ? data.category(t.categoryId) == null : t.categoryId == cat)) &&
            (q.isEmpty || matchesSearch(t, q, data)))
          t,
    ], data, now);
  }

  void _open(Task t) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: t)));

  Future<void> _menu(Task t) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600))),
          for (final b in MatrixBox.values)
            if (b.id != t.matrixBox)
              ListTile(
                leading: const Icon(Icons.arrow_forward),
                title: Text('Move to ${data.boxName(b)}'),
                subtitle: Text(b.meaning),
                onTap: () => Navigator.pop(c, b.id),
              ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open the task'),
            onTap: () => Navigator.pop(c, 'open'),
          ),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: const Text('Take off the matrix'),
            onTap: () => Navigator.pop(c, 'off'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'open') return _open(t);
    if (choice == 'off') return store.setBox(t, null);
    await putInBox(context, store, t, MatrixBox.byId(choice)!);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search the matrix', border: InputBorder.none),
                    onChanged: (_) => setState(() {}),
                  )
                : const Text('Matrix'),
            actions: [
              IconButton(
                tooltip: _searching ? 'Close search' : 'Search',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _search.clear();
                }),
              ),
            ],
          ),
          body: Column(children: [
            _filters(),
            Expanded(
              child: data.matrixTasks.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No tasks on the matrix yet. Put one on from its task page ("On the matrix"), or type '
                          '!do, !decide, !delegate or !delete when adding a task.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : LayoutBuilder(builder: (context, size) => _grid(size, now)),
            ),
          ]),
        );
      },
    );
  }

  Widget _filters() {
    final cats = data.categories;
    final cat = store.matrixCategory;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          if (cats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PopupMenuButton<String>(
                tooltip: 'Category',
                onSelected: (v) => _setFilter(store.matrixFilter, v == '*' ? null : v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '*', child: Text('All categories')),
                  for (final c in cats) PopupMenuItem(value: c.id, child: Text(c.name)),
                  const PopupMenuItem(value: '', child: Text('No category')),
                ],
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.label_outline, size: 18),
                  label: Text(cat == null
                      ? 'All categories'
                      : cat.isEmpty
                          ? 'No category'
                          : data.category(cat)?.name ?? 'All categories'),
                ),
              ),
            ),
          for (final f in QuickFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(f.label),
                selected: store.matrixFilter == f,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _setFilter(f, store.matrixCategory),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(BoxConstraints size, DateTime now) {
    Widget box(MatrixBox b) => Expanded(child: _box(b, _tasksIn(b, now), now));
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(children: [
            Expanded(child: Text('Urgent', textAlign: TextAlign.center, style: _axis)),
            Expanded(child: Text('Not urgent', textAlign: TextAlign.center, style: _axis)),
          ]),
        ),
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [box(MatrixBox.doNow), box(MatrixBox.decide)])),
        Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [box(MatrixBox.delegate), box(MatrixBox.delete)])),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Top: important · Bottom: not important', style: _axis),
        ),
      ]),
    );
  }

  TextStyle get _axis => TextStyle(fontSize: 11, color: Theme.of(context).hintColor);

  static const _tints = {
    MatrixBox.doNow: Color(0xFFFBEBEB),
    MatrixBox.decide: Color(0xFFE7F1FB),
    MatrixBox.delegate: Color(0xFFF9EEDA),
    MatrixBox.delete: Color(0xFFF0EFEC),
  };

  Widget _box(MatrixBox b, List<Task> tasks, DateTime now) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.matrixBox != b.id,
      onAcceptWithDetails: (d) => putInBox(context, store, d.data, b),
      builder: (context, hovering, _) => Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: hovering.isNotEmpty
              ? Theme.of(context).colorScheme.primaryContainer
              : dark
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : _tints[b],
          borderRadius: BorderRadius.circular(8),
          border: widget.initialBox == b ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Row(children: [
              Expanded(
                child: Text('${data.boxName(b)} · ${tasks.length}',
                    style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
              ),
              Tooltip(message: b.meaning, child: Icon(Icons.info_outline, size: 16, color: Theme.of(context).hintColor)),
            ]),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(child: Text('Nothing here', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)))
                : ListView(padding: const EdgeInsets.fromLTRB(6, 0, 6, 6), children: [
                    for (final t in tasks)
                      LongPressDraggable<Task>(
                        data: t,
                        feedback: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(width: 220, child: _card(t, now)),
                        ),
                        childWhenDragging: Opacity(opacity: 0.4, child: _card(t, now)),
                        child: _card(t, now),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _card(Task t, DateTime now) {
    final colour = data.isLocked(t) ? lockedColor : ageColor(t, data.hoursToRed, byDue: data.colourByDue, now: now);
    final hint = TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.6));
    final details = [
      if (t.dueAt != null) 'Due ${DateFormat('EEE d MMM').format(t.dueAt!)}',
      if (t.waitingOn != null) 'Waiting on ${t.waitingOn}',
      if (data.category(t.categoryId) case final c?) c.name,
    ];
    return Card(
      margin: const EdgeInsets.only(top: 4),
      color: colour,
      child: InkWell(
        onTap: () => _open(t),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (t.starred) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star, size: 14)),
                  Expanded(
                    child: Text(t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                  ),
                ]),
                if (details.isNotEmpty) Text(details.join(' · '), style: hint, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (store.looksUrgent(t, now))
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFFC62828), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Urgent?', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
              ]),
            ),
            IconButton(
              tooltip: 'Move to box…',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_vert, size: 18, color: Colors.black54),
              onPressed: () => _menu(t),
            ),
          ]),
        ),
      ),
    );
  }
}
