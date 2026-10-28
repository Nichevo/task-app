import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../csv_export.dart';
import '../csv_import.dart';
import '../input_parse.dart';
import '../models.dart';
import '../native.dart';
import '../photo_import.dart';
import '../store.dart';
import '../widgets/add_dialogs.dart';
import '../widgets/task_block.dart';
import '../widgets/task_colors.dart';
import 'archive_page.dart';
import 'calendar_page.dart';
import 'events_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
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
  final _addBar = GlobalKey<_AddBarState>();
  final _expanded = <String>{};

  /// The task open for editing: beside the list on wide screens, in place of it on narrow ones.
  String? _selectedId;

  /// Whether tasks due after 30 days / snoozed tasks are shown despite the filters.
  bool _showLater = false;
  bool _showSnoozed = false;

  /// Upcoming calendar events worth offering, when the app checks on its own.
  int _eventCount = 0;

  late final Timer _tick;
  late final AppLifecycleListener _lifecycle;

  AppStore get store => widget.store;
  AppData get data => store.data;

  @override
  void initState() {
    super.initState();
    // Re-colour the blocks as they age, and bring back snoozed tasks.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    _lifecycle = AppLifecycleListener(onResume: store.syncIfStale);
    store.addListener(_checkEvents);
    _checkEvents();
  }

  @override
  void dispose() {
    _tick.cancel();
    _lifecycle.dispose();
    store.removeListener(_checkEvents);
    super.dispose();
  }

  bool _checkingEvents = false;

  /// Once a day or week (as chosen in Settings) looks for events to offer as tasks.
  Future<void> _checkEvents() async {
    if (_checkingEvents || !Native.supported || data.eventSuggest == EventSuggest.off) return;
    final last = store.eventPromptAt;
    final period = Duration(days: data.eventSuggest == EventSuggest.daily ? 1 : 7);
    if (last != null && DateTime.now().difference(last) < period) return;
    _checkingEvents = true;
    try {
      final n = (await upcomingEvents(data)).length;
      if (mounted && n != _eventCount) setState(() => _eventCount = n);
    } catch (_) {
      // No access yet; the Upcoming events page explains how to allow it.
    } finally {
      _checkingEvents = false;
    }
  }

  void _dismissEvents() {
    store.eventPromptAt = DateTime.now();
    store.saveDeviceSettings();
    setState(() => _eventCount = 0);
  }

  /// Opens a task (e.g. from the home screen widget).
  void openTask(String id) => _select(id);

  /// Puts the cursor in the add box (e.g. from the quick-add widget), with [text] filled in
  /// and [categoryId] already chosen.
  void focusAdd({String? text, String? categoryId}) {
    _select(null);
    _addBar.currentState?.focus(text: text, categoryId: categoryId);
  }

  void openCalendar(DateTime? day) => _open(context, CalendarPage(store: store, initialDay: day));

  void openStats() => _open(context, StatsPage(store: store));

  /// Text shared from another app: one task, or several when it is a list.
  Future<void> addShared(SharedText shared) async {
    final lines = splitLines(shared.text);
    if (lines.length > 1 && !lines.every((l) => l.startsWith('http'))) {
      await showAddManyDialog(context, store, lines);
      return;
    }
    final subject = shared.subject?.trim() ?? '';
    final first = lines.firstOrNull ?? '';
    final isLink = first.startsWith('http');
    final title = subject.isNotEmpty ? subject : (isLink ? 'Look at link' : first);
    final notes = subject.isNotEmpty || isLink ? shared.text.trim() : '';
    await showAddTaskDialog(context, store, title: title, notes: notes);
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

  void _open(BuildContext context, Widget page) =>
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

  Future<void> _pasteList() async {
    final text = (await Clipboard.getData('text/plain'))?.text ?? '';
    final lines = splitLines(text);
    if (!mounted) return;
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to paste. Copy a list first.')));
      return;
    }
    await showAddManyDialog(context, store, lines);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: 'Calendar',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => openCalendar(null),
          ),
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
            onSelected: (v) => switch (v) {
              'group' => () {
                  data.groupByCategory = !data.groupByCategory;
                  store.changed(settings: true);
                }(),
              'stats' => openStats(),
              'events' => _open(context, EventsPage(store: store)),
              'paste' => _pasteList(),
              'photo' => importPhoto(context, store),
              'csv' => exportCsv(context, store),
              'import' => importCsv(context, store),
              'sync' => store.sync(),
              'settings' => _open(context, SettingsPage(store: store)),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'group',
                  child: Text(data.groupByCategory ? 'Show as one list' : 'Group by category')),
              const PopupMenuItem(value: 'stats', child: Text('Statistics')),
              if (Native.supported) const PopupMenuItem(value: 'events', child: Text('Upcoming events')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'paste', child: Text('Paste a list')),
              if (Native.supported) const PopupMenuItem(value: 'photo', child: Text('Photo of a list')),
              const PopupMenuItem(value: 'import', child: Text('Import from CSV')),
              const PopupMenuItem(value: 'csv', child: Text('Export to CSV')),
              const PopupMenuDivider(),
              if (store.dropbox != null)
                const PopupMenuItem(value: 'sync', child: Text('Sync with Dropbox now')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_eventCount > 0)
          MaterialBanner(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            leading: const Icon(Icons.event_available_outlined),
            content: Text('$_eventCount event${_eventCount == 1 ? '' : 's'} coming up could be tasks'),
            actions: [
              TextButton(onPressed: _dismissEvents, child: const Text('Not now')),
              TextButton(
                onPressed: () {
                  _dismissEvents();
                  _open(context, EventsPage(store: store));
                },
                child: const Text('Have a look'),
              ),
            ],
          ),
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
        _AddBar(key: _addBar, store: store),
      ]),
    );
  }

  Widget _header(_Header h) => Padding(
        key: ValueKey('h:${h.key}'),
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 0),
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
            IconButton(
              tooltip: 'Add a task to ${h.name}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 20),
              onPressed: () => focusAdd(categoryId: h.key.isEmpty ? null : h.key),
            ),
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
          onStep: (s) => _toggleStep(t, s),
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

  void _toggleStep(Task t, TaskStep s) {
    if (store.toggleStep(t, s)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('All steps of "${t.title}" done'),
          action: SnackBarAction(label: 'Tick off task', onPressed: () => _complete(t)),
        ));
    }
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

/// The box at the bottom for typing a new task. Its own widget so each keystroke only
/// redraws this bar, not the whole list. Shows chips for the date and category it reads
/// out of the words; tap ✕ on a chip to ignore that.
class _AddBar extends StatefulWidget {
  const _AddBar({super.key, required this.store});

  final AppStore store;

  @override
  State<_AddBar> createState() => _AddBarState();
}

class _AddBarState extends State<_AddBar> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _ignoreDate = false;
  bool _ignoreCategory = false;

  /// A category chosen on purpose (heading +, widget, or the chip menu) beats a guess.
  String? _forcedCategory;
  bool _handlingPaste = false;

  AppData get data => widget.store.data;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onChanged);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (_input.text.isEmpty) _ignoreDate = _ignoreCategory = false;
    final lines = splitLines(_input.text);
    if (lines.length > 1 && !_handlingPaste) {
      // Several lines were pasted: offer them as separate tasks.
      _handlingPaste = true;
      _input.clear();
      showAddManyDialog(context, widget.store, lines).whenComplete(() => _handlingPaste = false);
      return;
    }
    setState(() {});
  }

  void focus({String? text, String? categoryId}) {
    if (text != null && text.isNotEmpty) _input.text = text;
    if (categoryId != null) _forcedCategory = categoryId;
    _ignoreCategory = false;
    setState(() {});
    _focus.requestFocus();
  }

  ParsedInput get _parsed => parseInput(_input.text, data, DateTime.now(), classify: _forcedCategory == null);

  void _add() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final p = _parsed;
    final category = _forcedCategory ?? (_ignoreCategory ? null : p.categoryId);
    widget.store.addTask(_ignoreDate ? text : p.title, due: _ignoreDate ? null : p.due, categoryId: category);
    _input.clear();
    _ignoreDate = _ignoreCategory = false;
    _forcedCategory = null;
    _focus.requestFocus();
  }

  Future<void> _pickCategory() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Category for this task'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, ''), child: const Text('None')),
          for (final cat in data.categories)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, cat.id), child: Text(cat.name)),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _forcedCategory = picked.isEmpty ? null : picked;
      _ignoreCategory = picked.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _input.text.trim().isEmpty ? null : _parsed;
    final due = _ignoreDate ? null : p?.due;
    final categoryId = _forcedCategory ?? (_ignoreCategory ? null : p?.categoryId);
    final category = data.category(categoryId);
    final showCategoryChip = category != null && (_forcedCategory != null || data.autoCategory != AutoCategory.off);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (due != null || showCategoryChip)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 6, children: [
                if (due != null)
                  InputChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text('Due ${dateTimeFmt.format(due)}'),
                    tooltip: 'Picked from what you typed. Tap ✕ to keep the words instead.',
                    onDeleted: () => setState(() => _ignoreDate = true),
                  ),
                if (showCategoryChip)
                  InputChip(
                    avatar: Icon(
                        _forcedCategory != null
                            ? Icons.label
                            : p?.source == CategorySource.learned
                                ? Icons.auto_awesome
                                : Icons.label_outline,
                        size: 18),
                    label: Text(category.name),
                    tooltip: switch (p?.source) {
                      _ when _forcedCategory != null => 'Category for this task. Tap to change.',
                      CategorySource.learned => 'Guessed from similar tasks. Tap to change, ✕ to drop.',
                      CategorySource.keyword => 'Matched a keyword in Settings. Tap to change, ✕ to drop.',
                      _ => 'From the #tag you typed. Tap to change, ✕ to drop.',
                    },
                    onPressed: _pickCategory,
                    onDeleted: () => setState(() {
                      _forcedCategory = null;
                      _ignoreCategory = true;
                    }),
                  ),
              ]),
            ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                textCapitalization: TextCapitalization.sentences,
                // Not a strict single-line field, so a pasted list keeps its line breaks
                // (and is offered as several tasks); Enter still adds the task.
                minLines: 1,
                maxLines: 3,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Add a task… (e.g. "Call bank tomorrow 5pm #home")',
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
