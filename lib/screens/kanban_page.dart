import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../store.dart';
import '../task_list.dart';
import '../widgets/task_colors.dart';
import 'settings_page.dart' show askText;
import 'task_page.dart';

/// Colours offered for a stage heading.
const stageColours = [0xFF90CAF9, 0xFFA5D6A7, 0xFFFFE082, 0xFFFFAB91, 0xFFEF9A9A, 0xFFCE93D8, 0xFFB0BEC5];

/// Moves [t] to [to] and applies the "tick it off too" rule for the last stage.
Future<void> moveWithRule(BuildContext context, AppStore store, Task t, KanbanStage to, String how,
    {String? note}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!store.moveToStage(t, to, how: how, note: note)) return;
  var tick = store.data.kanbanDone == KanbanDone.always;
  if (store.data.kanbanDone == KanbanDone.ask) {
    tick = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Tick it off too?'),
            content: Text('"${t.title}" is in ${to.name}. Tick it off into the archive as well?\n\n'
                'You can choose to always or never do this in Settings, Kanban board.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it open')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tick off')),
            ],
          ),
        ) ??
        false;
  }
  if (!tick || t.closedAt != null) return;
  final index = store.data.active.indexOf(t);
  final spawned = store.complete(t);
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text('Archived "${t.title}"'),
      action: SnackBarAction(label: 'Undo', onPressed: () => store.uncomplete(t, index, spawned)),
    ));
}

/// "Move to…": pick any stage, with an optional short note.
Future<void> showMoveTo(BuildContext context, AppStore store, Task t) async {
  final note = TextEditingController();
  final picked = await showDialog<KanbanStage>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Move "${t.title}" to'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in store.data.stages)
            ListTile(
              dense: true,
              enabled: !(t.kanban && t.stageId == s.id),
              leading: _StageDot(s),
              title: Text(s.name),
              trailing: t.kanban && t.stageId == s.id ? const Text('Now') : null,
              onTap: () => Navigator.pop(c, s),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. waiting on parts'),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel'))],
    ),
  );
  final text = note.text;
  note.dispose();
  if (picked == null || !context.mounted) return;
  await moveWithRule(context, store, t, picked, MoveHow.menu, note: text);
}

/// "3 days", "5 h", "20 min".
String describeSpell(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  if (m < 48 * 60) return '${(m / 60).round()} h';
  final days = (m / (24 * 60)).round();
  return '$days day${days == 1 ? '' : 's'}';
}

class _StageDot extends StatelessWidget {
  const _StageDot(this.stage);

  final KanbanStage stage;

  @override
  Widget build(BuildContext context) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: stage.colour == null ? null : Color(stage.colour!),
          border: Border.all(color: Theme.of(context).hintColor),
        ),
      );
}

/// Item 52: the board. One column per stage; side by side when wide, one at a time with tabs
/// when narrow (the folded phone).
class KanbanPage extends StatefulWidget {
  const KanbanPage({super.key, required this.store});

  final AppStore store;

  @override
  State<KanbanPage> createState() => _KanbanPageState();
}

class _KanbanPageState extends State<KanbanPage> {
  QuickFilter _filter = QuickFilter.all;

  /// Category chip: null = all, '' = no category.
  String? _category;
  bool _searching = false;
  final _search = TextEditingController();

  AppStore get store => widget.store;
  AppData get data => store.data;

  /// Phones drag after a press and hold, so a quick swipe still scrolls; mice drag at once.
  static bool get _touch => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Columns narrower than this scroll sideways instead of squeezing.
  static const _minColumn = 170.0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Task> _tasksIn(KanbanStage s, DateTime now) {
    final q = _searching ? _search.text.trim() : '';
    final shown = data.boardTasks.where((t) =>
        _columnOf(t) == s.id &&
        (q.isNotEmpty
            ? matchesSearch(t, q)
            : passesFilter(t, _filter, now) &&
                (_category == null ||
                    (_category!.isEmpty ? data.category(t.categoryId) == null : t.categoryId == _category))));
    return sortTasks(shown.toList(), data, now);
  }

  /// The column a task shows in: its stage, or the first one if that stage was removed on
  /// another device.
  String? _columnOf(Task t) => (data.stage(t.stageId) ?? data.stages.firstOrNull)?.id;

  Future<void> _addTo(KanbanStage s) async {
    final title = await askText(context, 'New task in ${s.name}');
    if (title == null || title.trim().isEmpty) return;
    store.addToStage(title, s);
  }

  void _open(Task t) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: t)));

  KanbanStage? _step(Task t, int by) {
    final i = data.stages.indexWhere((s) => s.id == t.stageId);
    final j = i + by;
    return i < 0 || j < 0 || j >= data.stages.length ? null : data.stages[j];
  }

  Future<void> _cardMenu(Task t) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w600))),
          ListTile(leading: const Icon(Icons.drive_file_move_outline), title: const Text('Move to…'),
              onTap: () => Navigator.pop(c, 'move')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Open task'),
              onTap: () => Navigator.pop(c, 'open')),
          ListTile(leading: const Icon(Icons.check_box_outlined), title: const Text('Tick off'),
              onTap: () => Navigator.pop(c, 'done')),
          ListTile(leading: const Icon(Icons.remove_circle_outline), title: const Text('Take off the board'),
              subtitle: const Text('It stays in the main list and keeps its board history'),
              onTap: () => Navigator.pop(c, 'off')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'move':
        await showMoveTo(context, store, t);
      case 'open':
        _open(t);
      case 'done':
        final index = data.active.indexOf(t);
        final spawned = store.complete(t);
        _snack('Archived "${t.title}"', () => store.uncomplete(t, index, spawned));
      case 'off':
        store.setOnBoard(t, false);
        _snack('Took "${t.title}" off the board', () => store.setOnBoard(t, true));
    }
  }

  void _snack(String text, VoidCallback undo) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(text), action: SnackBarAction(label: 'Undo', onPressed: undo)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        final stages = data.stages;
        final columns = {for (final s in stages) s.id: _tasksIn(s, now)};
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 600;
          final appBar = _appBar(context, wide, stages, columns);
          if (stages.isEmpty) {
            return Scaffold(appBar: appBar, body: const Center(child: Text('No stages. Add some in Settings, Kanban board.')));
          }
          if (wide) {
            return Scaffold(
              appBar: appBar,
              body: Column(children: [
                _chips(),
                Expanded(child: _wideBoard(box.maxWidth, stages, columns, now)),
              ]),
            );
          }
          return DefaultTabController(
            key: ValueKey(stages.map((s) => s.id).join(',')),
            length: stages.length,
            child: Scaffold(
              appBar: appBar,
              body: Column(children: [
                _chips(),
                Expanded(
                  child: TabBarView(children: [
                    for (final s in stages) _column(s, columns[s.id]!, now, wide: false),
                  ]),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, bool wide, List<KanbanStage> stages, Map<String, List<Task>> columns) {
    return AppBar(
      leading: _searching
          ? IconButton(
              tooltip: 'Close search',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _searching = false;
                _search.clear();
              }),
            )
          : null,
      title: _searching
          ? TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Search the board', border: InputBorder.none),
              onChanged: (_) => setState(() {}),
            )
          : const Text('Kanban board'),
      actions: [
        if (!_searching)
          IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: () => setState(() => _searching = true)),
      ],
      bottom: wide || stages.isEmpty
          ? null
          : TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final s in stages)
                  Tab(
                    child: Text('${s.name} ${columns[s.id]!.length}',
                        style: TextStyle(color: _over(s) ? const Color(0xFFE65100) : null)),
                  ),
              ],
            ),
    );
  }

  int _count(KanbanStage s) => data.boardTasks.where((t) => _columnOf(t) == s.id).length;

  bool _over(KanbanStage s) => s.limit != null && _count(s) > s.limit!;

  Widget _chips() {
    final cats = data.categories;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          if (cats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PopupMenuButton<String>(
                tooltip: 'Category',
                onSelected: (v) => setState(() => _category = v == '*' ? null : v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: '*', child: Text('All categories')),
                  for (final c in cats) PopupMenuItem(value: c.id, child: Text(c.name)),
                  const PopupMenuItem(value: '', child: Text('No category')),
                ],
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.label_outline, size: 18),
                  label: Text(_category == null
                      ? 'All categories'
                      : _category!.isEmpty
                          ? 'No category'
                          : data.category(_category)?.name ?? 'All categories'),
                ),
              ),
            ),
          for (final f in QuickFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(f.label),
                selected: _filter == f,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wideBoard(double width, List<KanbanStage> stages, Map<String, List<Task>> columns, DateTime now) {
    Widget col(KanbanStage s) => DragTarget<Task>(
          onWillAcceptWithDetails: (d) => d.data.stageId != s.id,
          onAcceptWithDetails: (d) => moveWithRule(context, store, d.data, s, MoveHow.dragged),
          builder: (context, hovering, _) => Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: hovering.isNotEmpty
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _column(s, columns[s.id]!, now, wide: true),
          ),
        );
    if (width / stages.length >= _minColumn) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final s in stages) Expanded(child: col(s)),
      ]);
    }
    return ListView(scrollDirection: Axis.horizontal, children: [
      for (final s in stages) SizedBox(width: 240, child: col(s)),
    ]);
  }

  Widget _column(KanbanStage s, List<Task> tasks, DateTime now, {required bool wide}) {
    final total = _count(s);
    final over = _over(s);
    final hint = Theme.of(context).hintColor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
        decoration: BoxDecoration(
          color: over ? const Color(0xFFFFC107) : (s.colour == null ? null : Color(s.colour!)),
          borderRadius: wide ? const BorderRadius.vertical(top: Radius.circular(6)) : null,
        ),
        child: Row(children: [
          Expanded(
            child: Text(s.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: over || s.colour != null ? const Color(0xDD000000) : null)),
          ),
          Tooltip(
            message: s.limit == null ? '$total on the board' : '$total of at most ${s.limit}',
            child: Text(s.limit == null ? '$total' : '$total/${s.limit}',
                style: TextStyle(color: over || s.colour != null ? const Color(0xAA000000) : hint)),
          ),
          IconButton(
            tooltip: 'Add a task to ${s.name}',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 20, color: over || s.colour != null ? const Color(0xDD000000) : null),
            onPressed: () => _addTo(s),
          ),
        ]),
      ),
      Expanded(
        child: tasks.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(total == 0 ? 'Nothing here' : 'None match the filter',
                      style: TextStyle(color: hint), textAlign: TextAlign.center),
                ),
              )
            : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                for (final t in tasks) _card(t, s, now, wide: wide),
              ]),
      ),
    ]);
  }

  Widget _card(Task t, KanbanStage s, DateTime now, {required bool wide}) {
    final next = _step(t, 1), back = _step(t, -1);
    final card = _KanbanCard(
      task: t,
      stage: s,
      color: data.isLocked(t) ? lockedColor : ageColor(t, data.hoursToRed, byDue: data.colourByDue, now: now),
      categoryName: data.category(t.categoryId)?.name,
      now: now,
      onTap: () => _open(t),
      onMenu: () => _cardMenu(t),
      // One column at a time: a button moves it on, since sideways swipes change column.
      onNext: wide || next == null ? null : () => moveWithRule(context, store, t, next, MoveHow.menu),
      nextName: next?.name,
    );
    if (!wide) return card;
    final feedback = Material(
      elevation: 6,
      color: Colors.transparent,
      child: SizedBox(width: 220, child: Opacity(opacity: 0.9, child: card)),
    );
    final ghost = Opacity(opacity: 0.3, child: card);
    if (!_touch) {
      return Draggable<Task>(
          key: ValueKey('kcard-${t.id}'), data: t, feedback: feedback, childWhenDragging: ghost, child: card);
    }
    final swipeable = Dismissible(
      key: ValueKey('kswipe-${t.id}'),
      direction: switch ((back, next)) {
        (null, null) => DismissDirection.none,
        (null, _) => DismissDirection.startToEnd,
        (_, null) => DismissDirection.endToStart,
        _ => DismissDirection.horizontal,
      },
      background: _SwipeHint(next?.name, Icons.arrow_forward, Alignment.centerLeft),
      secondaryBackground: _SwipeHint(back?.name, Icons.arrow_back, Alignment.centerRight),
      confirmDismiss: (dir) async {
        final to = dir == DismissDirection.startToEnd ? next : back;
        if (to != null) await moveWithRule(context, store, t, to, MoveHow.swiped);
        return false; // the board redraws with the card in its new column
      },
      child: card,
    );
    // Phones: press and hold to drag, so a quick sideways swipe moves one stage instead.
    return LongPressDraggable<Task>(
        key: ValueKey('kcard-${t.id}'), data: t, feedback: feedback, childWhenDragging: ghost, child: swipeable);
  }
}

class _SwipeHint extends StatelessWidget {
  const _SwipeHint(this.name, this.icon, this.alignment);

  final String? name;
  final IconData icon;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: alignment,
        decoration: BoxDecoration(color: const Color(0xFF455A64), borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (alignment == Alignment.centerLeft) Icon(icon, color: Colors.white, size: 18),
          if (name != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(name!, style: const TextStyle(color: Colors.white)),
            ),
          if (alignment != Alignment.centerLeft) Icon(icon, color: Colors.white, size: 18),
        ]),
      );
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({
    required this.task,
    required this.stage,
    required this.color,
    required this.now,
    required this.onTap,
    required this.onMenu,
    this.categoryName,
    this.onNext,
    this.nextName,
  });

  final Task task;
  final KanbanStage stage;
  final Color color;
  final DateTime now;
  final String? categoryName;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final VoidCallback? onNext;
  final String? nextName;

  static final _due = DateFormat('d MMM HH:mm');

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xDD000000);
    const soft = TextStyle(fontSize: 12, color: Color(0xAA000000));
    final since = task.stageSince;
    final due = task.dueAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: ink),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      if (task.starred) const Icon(Icons.star, size: 16, color: Color(0xFF8D6E00)),
                    ]),
                    const SizedBox(height: 2),
                    Wrap(spacing: 8, children: [
                      if (categoryName != null) Text(categoryName!, style: soft),
                      if (due != null)
                        Text('Due ${_due.format(due)}',
                            style: soft.copyWith(fontWeight: due.isBefore(now) ? FontWeight.bold : null)),
                      if (task.steps.isNotEmpty) Text('${task.stepsDone}/${task.steps.length}', style: soft),
                      if (task.estimate != null) Text(shortMinutes(task.estimate!), style: soft),
                    ]),
                    if (since != null) Text('${stage.name} for ${describeSpell(now.difference(since))}', style: soft),
                  ]),
                ),
                if (onNext != null)
                  IconButton(
                    tooltip: 'Move to $nextName',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_forward, color: ink, size: 20),
                    onPressed: onNext,
                  ),
                IconButton(
                  tooltip: 'Move to…, take off the board',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_vert, color: ink, size: 20),
                  onPressed: onMenu,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings, Kanban board: the stages, their limits and colours, and the rules.
class KanbanSettingsPage extends StatelessWidget {
  const KanbanSettingsPage({super.key, required this.store});

  final AppStore store;

  AppData get data => store.data;

  Future<void> _edit(BuildContext context, KanbanStage s) async {
    final name = TextEditingController(text: s.name);
    final limit = TextEditingController(text: s.limit?.toString() ?? '');
    int? colour = s.colour;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Stage'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: limit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Most tasks at once (optional)', helperText: 'The heading turns amber above this'),
              ),
              const SizedBox(height: 16),
              const Text('Colour'),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final v in [null, ...stageColours])
                  InkWell(
                    onTap: () => setState(() => colour = v),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: v == null ? null : Color(v),
                        border: Border.all(
                            width: colour == v ? 3 : 1,
                            color: colour == v ? Theme.of(context).colorScheme.primary : Theme.of(context).hintColor),
                      ),
                      child: v == null ? const Icon(Icons.block, size: 16) : null,
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) {
      final n = int.tryParse(limit.text.trim());
      store.updateStage(s,
          name: name.text,
          colour: colour,
          clearColour: colour == null,
          limit: n != null && n > 0 ? n : null,
          clearLimit: n == null || n <= 0);
    }
    name.dispose();
    limit.dispose();
  }

  Future<void> _delete(BuildContext context, KanbanStage s) async {
    final messenger = ScaffoldMessenger.of(context);
    if (data.stages.length <= 2) {
      messenger.showSnackBar(const SnackBar(content: Text('The board needs at least two stages.')));
      return;
    }
    final others = data.stages.where((o) => o != s).toList();
    final inIt = data.boardTasks.where((t) => t.stageId == s.id).length;
    final moveTo = await showDialog<KanbanStage>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Remove "${s.name}"?'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(inIt == 0
                ? 'No tasks are in it. Tasks that were in it before go back to the stage you pick.'
                : '$inIt task${inIt == 1 ? ' is' : 's are'} in it. Move ${inIt == 1 ? 'it' : 'them'} to:'),
          ),
          for (final o in others) SimpleDialogOption(onPressed: () => Navigator.pop(c, o), child: Text(o.name)),
        ],
      ),
    );
    if (moveTo != null) store.deleteStage(s, moveTo);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Kanban board')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(child: Text('Stages', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
              onPressed: () async {
                final name = await askText(context, 'New stage');
                if (name != null && name.trim().isNotEmpty) store.addStage(name);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ]),
          const Text('Drag to reorder. Tap a stage to rename it or give it a colour or a limit.'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: store.moveStage,
            children: [
              for (final (i, s) in data.stages.indexed)
                ListTile(
                  key: ValueKey(s.id),
                  contentPadding: EdgeInsets.zero,
                  leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                  title: Row(children: [_StageDot(s), const SizedBox(width: 8), Flexible(child: Text(s.name))]),
                  subtitle: Text([
                    '${data.boardTasks.where((t) => t.stageId == s.id).length} on the board',
                    if (s.limit != null) 'at most ${s.limit}',
                    if (i == data.stages.length - 1) 'last stage',
                  ].join(' · ')),
                  onTap: () => _edit(context, s),
                  trailing: IconButton(
                    tooltip: 'Remove stage',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, s),
                  ),
                ),
            ],
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Moving a task to ${data.stages.lastOrNull?.name ?? 'the last stage'}'),
            subtitle: const Text('Whether it is ticked off into the archive too'),
            trailing: DropdownButton<KanbanDone>(
              value: data.kanbanDone,
              items: const [
                DropdownMenuItem(value: KanbanDone.ask, child: Text('Ask')),
                DropdownMenuItem(value: KanbanDone.always, child: Text('Tick off')),
                DropdownMenuItem(value: KanbanDone.never, child: Text('Keep open')),
              ],
              onChanged: (v) {
                data.kanbanDone = v ?? KanbanDone.ask;
                store.changed(settings: true);
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hide board tasks from the main list'),
            subtitle: const Text('Otherwise they show there too, with their stage.'),
            value: data.kanbanHideFromList,
            onChanged: (v) {
              data.kanbanHideFromList = v;
              store.changed(settings: true);
            },
          ),
        ]),
      ),
    );
  }
}
