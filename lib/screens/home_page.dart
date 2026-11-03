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
import '../changelog.dart';
import '../native.dart';
import '../photo_import.dart';
import '../store.dart';
import '../task_list.dart';
import '../widgets/add_dialogs.dart';
import '../widgets/task_block.dart';
import '../widgets/task_colors.dart';
import 'about_page.dart';
import 'archive_page.dart';
import 'calendar_page.dart';
import 'events_page.dart';
import 'kanban_page.dart';
import 'matrix_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'side_panel.dart';
import 'starred_page.dart';
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

  /// Whether snoozed tasks are shown anyway.
  bool _showSnoozed = false;

  /// The search box in the top bar, while open.
  bool _searching = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  /// Upcoming calendar events worth offering, when the app checks on its own.
  int _eventCount = 0;

  /// Item 55: starred emails not yet tasks, for the optional line at the top.
  int _starredCount = 0;
  DateTime? _starredCheckedAt;
  bool _starredHidden = false;

  /// The "please update this device" note (item 62) was put away until the app restarts.
  bool _updateNoteHidden = false;

  late final Timer _tick;
  late final AppLifecycleListener _lifecycle;

  AppStore get store => widget.store;
  AppData get data => store.data;

  @override
  void initState() {
    super.initState();
    // Re-colour the blocks as they age, and bring back snoozed tasks.
    // Only while the app is on screen: in the background there is nothing to redraw.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) setState(() {});
    });
    _lifecycle = AppLifecycleListener(onResume: () {
      setState(() {}); // Colours and snoozes may have moved on while it was hidden.
      store.syncIfStale();
      _checkStarred();
      if (store.dropbox == null) store.checkEmailTasks();
    });
    store.addListener(_checkEvents);
    _checkEvents();
    _checkStarred();
    // With Dropbox, each sync checks Gmail too (item 54).
    if (store.dropbox == null) store.checkEmailTasks();
  }

  @override
  void dispose() {
    _tick.cancel();
    _lifecycle.dispose();
    _search.dispose();
    _searchFocus.dispose();
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

  /// When the setting is on, counts starred emails not yet used (at most every 10 minutes).
  Future<void> _checkStarred() async {
    if (!data.starredLine || store.google == null || _starredHidden) return;
    final last = _starredCheckedAt;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) return;
    _starredCheckedAt = DateTime.now();
    try {
      final n = await store.starredWaiting() ?? 0;
      if (mounted && n != _starredCount) setState(() => _starredCount = n);
    } catch (_) {
      // Offline or signed out; the Starred emails page shows why.
    }
  }

  void _dismissEvents() {
    store.eventPromptAt = DateTime.now();
    store.saveDeviceSettings();
    setState(() => _eventCount = 0);
  }

  /// After an update (not a fresh install), shows once what changed in this version.
  Future<void> maybeShowWhatsNew() async {
    final current = releases.first.version;
    if (store.seenVersion == current) return;
    final show = store.hadData;
    store.seenVersion = current;
    await store.saveDeviceSettings();
    if (show && mounted) await showWhatsNew(context, releases.first);
  }

  /// Opens a task (e.g. from the home screen widget).
  void openTask(String id) => _select(id);

  /// Puts the cursor in the add box (e.g. from the quick-add widget), with [text] filled in
  /// and [categoryId] already chosen.
  void focusAdd({String? text, String? categoryId, String? source}) {
    _select(null);
    _addBar.currentState?.focus(text: text, categoryId: categoryId, source: source);
  }

  void openCalendar(DateTime? day) => _open(context, CalendarPage(store: store, initialDay: day));

  void openStats() => _open(context, StatsPage(store: store));

  void openBoard({String? stageId}) => _open(context, KanbanPage(store: store, initialStage: stageId));

  void openMatrix({MatrixBox? box}) => _open(context, MatrixPage(store: store, initialBox: box));

  /// Text shared from another app: one task, or several when it is a list.
  Future<void> addShared(SharedText shared) async {
    final source = shared.voice ? TaskSource.voice : TaskSource.share;
    final lines = splitLines(shared.text);
    if (lines.length > 1 && !lines.every((l) => l.startsWith('http'))) {
      await showAddManyDialog(context, store, lines, source: source);
      return;
    }
    final subject = shared.subject?.trim() ?? '';
    final first = lines.firstOrNull ?? '';
    final isLink = first.startsWith('http');
    final title = subject.isNotEmpty ? subject : (isLink ? 'Look at link' : first);
    final notes = subject.isNotEmpty || isLink ? shared.text.trim() : '';
    await showAddTaskDialog(context, store, title: title, notes: notes, source: source);
  }

  void _complete(Task t) {
    final index = data.active.indexOf(t);
    final spawned = store.complete(t);
    _snack(spawned == null ? 'Archived "${t.title}"' : 'Archived "${t.title}". Next one due ${dateTimeFmt.format(spawned.dueAt!)}',
        () => store.uncomplete(t, index, spawned));
  }

  void _skip(Task t) {
    final undo = store.skip(t);
    _snack('Skipped "${t.title}". Next due ${dateTimeFmt.format(t.dueAt!)}', undo);
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

  String get _query => _searching ? _search.text.trim() : '';

  /// The chip in use; All when the chip row is switched off.
  QuickFilter get _filter => data.showQuickFilters ? store.quickFilter : QuickFilter.all;

  /// Drag to reorder works in any sort (a drop switches to hand-made order), but not while a
  /// search hides most of the list.
  bool get _canDrag => _query.isEmpty;

  /// The open tasks to show, in the chosen order. A search looks through every open task
  /// (snoozed ones too), whatever chip is picked.
  List<Task> _visibleTasks(DateTime now) {
    final q = _query;
    final shown = q.isNotEmpty
        ? data.active.where((t) => matchesSearch(t, q, data))
        : data.active.where((t) =>
            (_showSnoozed || !t.isSnoozed(now)) &&
            passesFilter(t, _filter, now) &&
            !(data.kanbanHideFromList && t.kanban));
    return sortTasks(shown.toList(), data, now);
  }

  void _closeSearch() => setState(() {
        _searching = false;
        _search.clear();
      });

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
    final wasSort = data.sort;
    final before = [...data.active];
    final oldCategory = moved.task.categoryId;
    // Dragging in a sorted list keeps the order on screen as the hand-made order, with the move.
    if (wasSort != ListSort.manual) data.sort = ListSort.manual;
    store.reorderVisible([for (final r in next.whereType<_TaskRow>()) r.task], moved: moved.task, categoryId: category);
    if (wasSort != ListSort.manual) {
      store.changed(settings: true);
      _snack('Now in hand-made order (was ${sortLabels[wasSort]!.toLowerCase()}). Change it in Settings, Sort by.', () {
        final still = data.active.toSet();
        final restored = [...before.where(still.contains), ...data.active.where((t) => !before.contains(t))];
        data.active
          ..clear()
          ..addAll(restored);
        data.sort = wasSort;
        final recat = moved.task.categoryId != oldCategory;
        if (recat) moved.task.categoryId = oldCategory;
        store.changed(order: true, settings: true, task: recat ? moved.task : null);
      });
    } else if (_snapsBack(next, moved)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text('Starred tasks stay at the top. Turn off "Starred at the top" in Settings to move them freely.')));
    }
  }

  /// Whether "Starred at the top" will put [moved] back above or below where it was dropped.
  bool _snapsBack(List<_Row> next, _TaskRow moved) {
    if (!data.starredTop) return false;
    final at = next.indexOf(moved);
    // A category header next to it counts as no neighbour: sorting stays inside each group.
    Task? neighbour(int step) => switch (next.elementAtOrNull(at + step)) {
          _TaskRow r => r.task,
          _ => null,
        };

    final above = neighbour(-1), below = neighbour(1);
    return moved.task.starred ? (above != null && !above.starred) : (below != null && below.starred);
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
          _unfolded(wide);
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
          // Item 59: the matrix needs room for its 2 by 2 grid, so it gets half the screen.
          final half = open == null && store.panelView == PanelView.matrix;
          return Row(children: [
            Expanded(flex: half ? 1 : 3, child: list),
            const VerticalDivider(width: 1),
            Expanded(
              flex: half ? 1 : 2,
              child: open == null
                  ? SidePanel(store: store, onOpen: (t) => _select(t.id))
                  : TaskPage(key: ValueKey(open.id), store: store, task: open, onClose: () => _select(null)),
            ),
          ]);
        });
      },
    );
  }

  bool? _wasWide;

  /// Item 59: on going from narrow to wide (unfolding the Fold), open what Settings asks for.
  void _unfolded(bool wide) {
    final was = _wasWide;
    _wasWide = wide;
    if (was != false || !wide || store.unfoldOpens == UnfoldOpens.panel) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
      _open(context, store.unfoldOpens == UnfoldOpens.board ? KanbanPage(store: store) : MatrixPage(store: store));
    });
  }

  Widget _listScaffold(BuildContext context, bool wide) {
    final now = DateTime.now();
    final rows = _rows(now);
    final searching = _query.isNotEmpty;
    final snoozedCount = searching ? 0 : data.active.where((t) => t.isSnoozed(now)).length;
    final hiddenCount = searching || _filter == QuickFilter.all
        ? 0
        : data.active
            .where((t) => !t.isSnoozed(now) && !passesFilter(t, _filter, now) && !(data.kanbanHideFromList && t.kanban))
            .length;
    final shownTasks = [for (final r in rows) if (r is _TaskRow) r.task];
    final estimate = describeEstimates(shownTasks);
    return Scaffold(
      appBar: AppBar(
        leading: _searching
            ? IconButton(tooltip: 'Close search', icon: const Icon(Icons.arrow_back), onPressed: _closeSearch)
            : null,
        title: _searching
            ? TextField(
                controller: _search,
                focusNode: _searchFocus,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search tasks, notes and steps', border: InputBorder.none),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Tasks'),
        actions: [
          if (_searching)
            IconButton(
              tooltip: 'Search everything (steps, emails, archive)',
              icon: const Icon(Icons.manage_search),
              onPressed: () => _open(context, SearchPage(store: store, initialQuery: _search.text.trim())),
            ),
          if (_searching)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: () => setState(_search.clear),
            )
          else
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _searching = true),
            ),
          if (data.boardTasks.isNotEmpty)
            IconButton(tooltip: 'Kanban board', icon: const Icon(Icons.view_kanban_outlined), onPressed: openBoard),
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
            onPressed: () {
              if (!wide) return _open(context, ArchivePage(store: store));
              store.showPanel(PanelView.archive);
              _select(null);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'group' => () {
                  data.groupByCategory = !data.groupByCategory;
                  store.changed(settings: true);
                }(),
              'stats' => openStats(),
              'board' => openBoard(),
              'matrix' => _open(context, MatrixPage(store: store)),
              'search' => _open(context, SearchPage(store: store)),
              'events' => _open(context, EventsPage(store: store)),
              'starred' => _open(context, StarredPage(store: store)),
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
              const PopupMenuItem(value: 'board', child: Text('Kanban board')),
              const PopupMenuItem(value: 'matrix', child: Text('Matrix')),
              const PopupMenuItem(value: 'search', child: Text('Search everything')),
              if (Native.supported) const PopupMenuItem(value: 'events', child: Text('Upcoming events')),
              const PopupMenuItem(value: 'starred', child: Text('Starred emails')),
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
        if (data.newerAppElsewhere && !_updateNoteHidden)
          MaterialBanner(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            leading: const Icon(Icons.system_update_outlined),
            content: Text('Another device has a newer Task Blocks (${data.newestApp}). Please update this one. '
                'Everything keeps working, and nothing the newer version added is lost.'),
            actions: [TextButton(onPressed: () => setState(() => _updateNoteHidden = true), child: const Text('OK'))],
          ),
        if (store.restoreOffer case final b?)
          MaterialBanner(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            leading: const Icon(Icons.settings_backup_restore),
            content: Text('Dropbox has settings saved from your ${b.device} '
                'on ${DateFormat('d MMM').format(b.savedAt.toLocal())}: ${b.describe()}. Restore them here?'),
            actions: [
              TextButton(onPressed: store.dismissRestoreOffer, child: const Text('Not now')),
              TextButton(onPressed: () => store.restoreDeviceSettings(b), child: const Text('Restore')),
            ],
          ),
        if (_starredCount > 0 && data.starredLine && !_starredHidden)
          MaterialBanner(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            leading: const Icon(Icons.star_outline),
            content: Text('$_starredCount starred email${_starredCount == 1 ? '' : 's'} not yet tasks'),
            actions: [
              TextButton(onPressed: () => setState(() => _starredHidden = true), child: const Text('Not now')),
              TextButton(
                onPressed: () {
                  setState(() => _starredHidden = true);
                  _open(context, StarredPage(store: store));
                },
                child: const Text('Have a look'),
              ),
            ],
          ),
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
        if (data.showQuickFilters && !_searching) _filterChips(),
        if (estimate != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${shownTasks.length} task${shownTasks.length == 1 ? '' : 's'} shown, about $estimate',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ),
          ),
        Expanded(
          child: rows.isEmpty && hiddenCount == 0 && snoozedCount == 0
              ? Center(child: Text(searching ? 'No open task matches "$_query".' : 'No tasks. Type one below.'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  buildDefaultDragHandles: false,
                  itemCount: rows.length,
                  onReorderItem: (o, n) => _onReorder(rows, o, n),
                  footer: _footer(hiddenCount, snoozedCount),
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

  /// All / Today / Next 7 days / ... above the list.
  Widget _filterChips() => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            for (final f in QuickFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(f.label),
                  selected: store.quickFilter == f,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => store.setQuickFilter(f),
                ),
              ),
          ],
        ),
      );

  Widget _taskRow(Task t, int i, DateTime now) {
    final waitingFor = data.isLocked(t) ? data.task(t.afterTaskId)?.title : null;
    final drag = _canDrag;
    final block = _block(t, i, now, waitingFor, drag);
    return drag
        ? ReorderableDelayedDragStartListener(key: ValueKey(t.id), index: i, child: block)
        : KeyedSubtree(key: ValueKey(t.id), child: block);
  }

  Widget _block(Task t, int i, DateTime now, String? waitingFor, bool drag) {
    return Dismissible(
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
          onSkip: () => _skip(t),
          stageName: t.kanban ? (data.stage(t.stageId) ?? data.stages.firstOrNull)?.name : null,
          boxName: MatrixBox.byId(t.matrixBox) == null ? null : data.boxName(MatrixBox.byId(t.matrixBox)!),
          onBoard: t.kanban || data.stages.isEmpty ? null : () => _addToBoard(t),
          trailing: drag
              ? ReorderableDragStartListener(
                  index: i,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.drag_handle, color: Color(0x99000000)),
                  ),
                )
              : null,
        ),
    );
  }

  void _addToBoard(Task t) {
    store.setOnBoard(t, true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Put "${t.title}" on the board in ${data.stage(t.stageId)?.name}'),
        action: SnackBarAction(label: 'Open board', onPressed: openBoard),
      ));
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

  Widget? _footer(int hiddenCount, int snoozedCount) {
    if (hiddenCount == 0 && snoozedCount == 0) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(spacing: 8, children: [
        if (hiddenCount > 0)
          TextButton.icon(
            onPressed: () => store.setQuickFilter(QuickFilter.all),
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: Text('$hiddenCount more not in "${_filter.label}". Show all'),
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

  /// How the text in the box got there, when not typed (the quick-add widget, voice).
  String? _source;

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
    if (_input.text.isEmpty) {
      _ignoreDate = _ignoreCategory = false;
      // Cleared by hand: whatever is typed next is a new task, not the widget's.
      if (_source != TaskSource.widget) _source = null;
    }
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

  void focus({String? text, String? categoryId, String? source}) {
    _source = source;
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
    widget.store.addTask(_ignoreDate ? text : p.title,
        due: _ignoreDate ? null : p.due,
        categoryId: category,
        source: _source ?? TaskSource.typed,
        box: p.box,
        board: p.board,
        star: p.star);
    _source = null;
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
          if (due != null || showCategoryChip || p?.box != null || p?.board == true || p?.star == true)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 6, children: [
                // Item 64: the "!" words that were picked up.
                if (p?.box case final b?)
                  Chip(
                      avatar: const Icon(Icons.grid_view, size: 18),
                      label: Text('Box: ${data.boxName(b)}'),
                      visualDensity: VisualDensity.compact),
                if (p?.board == true)
                  const Chip(
                      avatar: Icon(Icons.view_kanban_outlined, size: 18),
                      label: Text('On the board'),
                      visualDensity: VisualDensity.compact),
                if (p?.star == true)
                  const Chip(
                      avatar: Icon(Icons.star, size: 18), label: Text('Starred'), visualDensity: VisualDensity.compact),
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
    if (saved == null) return;
    messenger.showSnackBar(SnackBar(content: Text('Exported $name')));
    // Board history goes in a second file, one row per move.
    final moves = buildMovesCsv(store.data);
    if (moves == null) {
      await _exportEmails(store, messenger);
      return;
    }
    final movesName = 'kanban_moves_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
    final savedMoves = await FilePicker.saveFile(
      dialogTitle: 'Export Kanban board moves',
      fileName: movesName,
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$moves')),
      mimeType: 'text/csv',
    );
    if (savedMoves != null) messenger.showSnackBar(SnackBar(content: Text('Exported $name and $movesName')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
  await _exportEmails(store, messenger);
}

/// Emails kept on tasks go in a file of their own (item 63).
Future<void> _exportEmails(AppStore store, ScaffoldMessengerState messenger) async {
  final emails = buildEmailsCsv(store.data);
  if (emails == null) return;
  final emailsName = 'task_emails_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
  try {
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Export emails kept on tasks',
      fileName: emailsName,
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$emails')),
      mimeType: 'text/csv',
    );
    if (saved != null) messenger.showSnackBar(SnackBar(content: Text('Exported $emailsName')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
  }
}
