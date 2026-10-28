import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../csv_export.dart';
import '../csv_import.dart';
import '../models.dart';
import '../quick_date.dart';
import '../store.dart';
import '../widgets/task_block.dart';
import '../widgets/task_colors.dart';
import 'archive_page.dart';
import 'settings_page.dart';
import 'task_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final AppStore store;

  @override
  State<HomePage> createState() => HomePageState();
}

/// A row in the main list: a category heading or a task.
sealed class _Row {}

class _Header extends _Row {
  _Header(this.key, this.name, this.count, this.collapsed);

  /// Category id, or '' for "No category".
  final String key;
  final String name;
  final int count;
  final bool collapsed;
}

class _TaskRow extends _Row {
  _TaskRow(this.task);
  final Task task;
}

class HomePageState extends State<HomePage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _expanded = <String>{};

  /// The task open for editing: beside the list on wide screens, in place of it on narrow ones.
  String? _selectedId;

  /// Whether tasks due after 30 days / snoozed tasks are shown despite the filters.
  bool _showLater = false;
  bool _showSnoozed = false;

  /// The user dismissed the date picked out of what they're typing.
  bool _ignoreQuickDate = false;

  late final Timer _tick;
  late final AppLifecycleListener _lifecycle;

  AppStore get store => widget.store;
  AppData get data => store.data;

  @override
  void initState() {
    super.initState();
    // Re-colour the blocks as they age, and bring back snoozed tasks.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    _lifecycle = AppLifecycleListener(onResume: store.sync);
    _input.addListener(() => setState(() {
          if (_input.text.isEmpty) _ignoreQuickDate = false;
        }));
  }

  @override
  void dispose() {
    _tick.cancel();
    _lifecycle.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Opens a task (e.g. from the home screen widget).
  void openTask(String id) => _select(id);

  /// Puts the cursor in the add box (e.g. from the quick-add widget).
  void focusAdd() {
    _select(null);
    _inputFocus.requestFocus();
  }

  QuickDate? get _quickDate {
    if (_ignoreQuickDate) return null;
    final q = QuickDate.parse(_input.text, DateTime.now());
    return q.due == null ? null : q;
  }

  void _add() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final q = _quickDate;
    store.addTask(q?.title ?? text, due: q?.due);
    _input.clear();
    _ignoreQuickDate = false;
    _inputFocus.requestFocus();
  }

  void _complete(Task t) {
    final index = data.active.indexOf(t);
    final spawned = store.complete(t);
    _snack(spawned == null ? 'Archived "${t.title}"' : 'Archived "${t.title}". Next one due ${dateTimeFmt.format(spawned.dueAt!)}',
        () => store.uncomplete(t, index, spawned));
  }

  void _delete(Task t) {
    final index = data.active.indexOf(t);
    store.delete(t);
    _snack('Deleted "${t.title}"', () => store.undelete(t, index));
  }

  void _snack(String text, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text), action: SnackBarAction(label: 'Undo', onPressed: undo)));
  }

  void _open(BuildContext context, page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  /// Wide enough (unfolded Fold, tablet, wide window) to show two panes.
  static const _twoPaneWidth = 600.0;

  void _select(String? id) => setState(() => _selectedId = id);

  bool _dueSoon(Task t, DateTime now) =>
      t.dueAt == null || !t.dueAt!.isAfter(now.add(const Duration(days: 30)));

  /// The open tasks the filters let through, starred first.
  List<Task> _visibleTasks(DateTime now) {
    final shown = data.active.where((t) =>
        (_showSnoozed || !t.isSnoozed(now)) && (!data.focusNext30 || _showLater || _dueSoon(t, now)));
    return [...shown.where((t) => t.starred), ...shown.where((t) => !t.starred)];
  }

  List<_Row> _rows(DateTime now) {
    final tasks = _visibleTasks(now);
    if (!data.groupByCategory) return [for (final t in tasks) _TaskRow(t)];
    final known = {for (final c in data.categories) c.id};
    String keyOf(Task t) => known.contains(t.categoryId) ? t.categoryId! : '';
    final rows = <_Row>[];
    for (final (key, name) in [('', 'No category'), for (final c in data.categories) (c.id, c.name)]) {
      final inGroup = tasks.where((t) => keyOf(t) == key).toList();
      final collapsed = data.collapsed.contains(key);
      rows.add(_Header(key, name, inGroup.length, collapsed));
      if (!collapsed) rows.addAll(inGroup.map(_TaskRow.new));
    }
    return rows;
  }

  void _onReorder(List<_Row> rows, int oldIndex, int newIndex) {
    final moved = rows[oldIndex];
    if (moved is! _TaskRow) return;
    final next = [...rows]..removeAt(oldIndex);
    next.insert(newIndex, moved);
    String? category = moved.task.categoryId;
    if (data.groupByCategory) {
      final above = next.take(newIndex).whereType<_Header>().lastOrNull ?? next.whereType<_Header>().first;
      category = above.key.isEmpty ? null : above.key;
    }
    store.reorderVisible([for (final r in next.whereType<_TaskRow>()) r.task], moved: moved.task, categoryId: category);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        // Forget a selection whose task was deleted (e.g. on another device).
        final open = data.task(_selectedId);
        if (open == null) _selectedId = null;
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= _twoPaneWidth;
          final list = _listScaffold(context, wide);
          if (!wide) {
            return PopScope(
              canPop: open == null,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _select(null);
              },
              child: open == null
                  ? list
                  : TaskPage(key: ValueKey(open.id), store: store, task: open, onClose: () => _select(null)),
            );
          }
          return Row(children: [
            Expanded(flex: 3, child: list),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 2,
              child: open == null
                  ? ArchivePage(store: store, embedded: true, onOpen: (t) => _select(t.id))
                  : TaskPage(key: ValueKey(open.id), store: store, task: open, onClose: () => _select(null)),
            ),
          ]);
        });
      },
    );
  }

  Widget _listScaffold(BuildContext context, bool wide) {
    final now = DateTime.now();
    final rows = _rows(now);
    final snoozedCount = data.active.where((t) => t.isSnoozed(now)).length;
    final laterCount = data.focusNext30
        ? data.active.where((t) => !t.isSnoozed(now) && !_dueSoon(t, now)).length
        : 0;
    final quick = _quickDate;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: 'Archive',
            icon: Badge(
              isLabelVisible: data.archived.isNotEmpty,
              label: Text('${data.archived.length}'),
              child: const Icon(Icons.inventory_2_outlined),
            ),
            // On wide screens the archive lives in the right-hand pane.
            onPressed: () => wide ? _select(null) : _open(context, ArchivePage(store: store)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'csv') exportCsv(context, store);
              if (v == 'import') importCsv(context, store);
              if (v == 'sync') store.sync();
              if (v == 'group') {
                data.groupByCategory = !data.groupByCategory;
                store.changed(settings: true);
              }
              if (v == 'settings') _open(context, SettingsPage(store: store));
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'group',
                  child: Text(data.groupByCategory ? 'Show as one list' : 'Group by category')),
              const PopupMenuItem(value: 'csv', child: Text('Export to CSV')),
              const PopupMenuItem(value: 'import', child: Text('Import from CSV')),
              if (store.dropbox != null)
                const PopupMenuItem(value: 'sync', child: Text('Sync with Dropbox now')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: rows.isEmpty && laterCount == 0 && snoozedCount == 0
              ? const Center(child: Text('No tasks. Type one below.'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  buildDefaultDragHandles: false,
                  itemCount: rows.length,
                  onReorderItem: (o, n) => _onReorder(rows, o, n),
                  footer: _footer(laterCount, snoozedCount),
                  itemBuilder: (context, i) => switch (rows[i]) {
                    _Header h => _header(h),
                    _TaskRow r => _taskRow(r.task, i, now),
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (quick != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text('Due ${dateTimeFmt.format(quick.due!)}'),
                    tooltip: 'Picked from what you typed. Tap ✕ to keep the words instead.',
                    onDeleted: () => setState(() => _ignoreQuickDate = true),
                  ),
                ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Add a task… (e.g. "Call bank tomorrow 5pm")',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _header(_Header h) => Padding(
        key: ValueKey('h:${h.key}'),
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 2),
        child: InkWell(
          onTap: () => store.toggleCollapsed(h.key),
          child: Row(children: [
            Icon(h.collapsed ? Icons.chevron_right : Icons.expand_more, size: 22),
            const SizedBox(width: 4),
            Expanded(
              child: Text(h.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (h.collapsed || h.count > 0)
              Text('${h.count}', style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(width: 8),
          ]),
        ),
      );

  Widget _taskRow(Task t, int i, DateTime now) {
    final waitingFor = data.isLocked(t) ? data.task(t.afterTaskId)?.title : null;
    return ReorderableDelayedDragStartListener(
      key: ValueKey(t.id),
      index: i,
      // Swipe right to tick off, left to delete (both can be undone).
      child: Dismissible(
        key: ValueKey('swipe-${t.id}'),
        direction: waitingFor == null ? DismissDirection.horizontal : DismissDirection.endToStart,
        background: const _SwipeBackground(
            color: Color(0xFF2E7D32), icon: Icons.check, alignment: Alignment.centerLeft),
        secondaryBackground: const _SwipeBackground(
            color: Color(0xFFC62828), icon: Icons.delete, alignment: Alignment.centerRight),
        onDismissed: (dir) => dir == DismissDirection.startToEnd ? _complete(t) : _delete(t),
        child: TaskBlock(
          task: t,
          color: waitingFor != null
              ? lockedColor
              : ageColor(t, data.hoursToRed, byDue: data.colourByDue, now: now),
          lockedBy: waitingFor,
          categoryName: data.category(t.categoryId)?.name,
          selected: _selectedId == t.id,
          expanded: _expanded.contains(t.id),
          onTap: () => setState(() => _expanded.contains(t.id) ? _expanded.remove(t.id) : _expanded.add(t.id)),
          onOpen: () => _select(t.id),
          onCheck: () => _complete(t),
          trailing: ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.drag_handle, color: Color(0x99000000)),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _footer(int laterCount, int snoozedCount) {
    if (laterCount == 0 && snoozedCount == 0) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(spacing: 8, children: [
        if (laterCount > 0)
          TextButton.icon(
            onPressed: () => setState(() => _showLater = !_showLater),
            icon: Icon(_showLater ? Icons.visibility_off : Icons.event_note),
            label: Text(_showLater ? 'Hide tasks due later' : 'Due later ($laterCount)'),
          ),
        if (snoozedCount > 0)
          TextButton.icon(
            onPressed: () => setState(() => _showSnoozed = !_showSnoozed),
            icon: Icon(_showSnoozed ? Icons.visibility_off : Icons.snooze),
            label: Text(_showSnoozed ? 'Hide snoozed' : 'Snoozed ($snoozedCount)'),
          ),
      ]),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.color, required this.icon, required this.alignment});

  final Color color;
  final IconData icon;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: alignment,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        child: Icon(icon, color: Colors.white),
      );
}

Future<void> exportCsv(BuildContext context, AppStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  // BOM so Excel reads the file as UTF-8.
  final bytes = Uint8List.fromList(utf8.encode('﻿${buildCsv(store.data)}'));
  final name = 'tasks_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
  try {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Export tasks',
      fileName: name,
      bytes: bytes,
      mimeType: 'text/csv',
    );
    if (saved != null) messenger.showSnackBar(SnackBar(content: Text('Exported $name')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}
