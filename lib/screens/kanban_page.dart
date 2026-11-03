import 'dart:io';
import 'dart:math';

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

/// What is being dragged on the board: a task, or one of its checklist steps (item 56).
class BoardDrag {
  const BoardDrag(this.task, [this.step]);

  final Task task;
  final TaskStep? step;

  String? get stageId => step == null ? (task.kanban ? task.stageId : null) : (step!.placed ? step!.stageId : null);
}

/// Moves a task or a step, with the rules for each.
Future<void> moveItem(BuildContext context, AppStore store, BoardDrag d, KanbanStage to, String how, {String? note}) =>
    d.step == null
        ? moveWithRule(context, store, d.task, to, how, note: note)
        : moveStepWithRule(context, store, d.task, d.step!, to, how, note: note);

/// Moves one step; when that finishes the checklist, offers to move the task on too.
Future<void> moveStepWithRule(BuildContext context, AppStore store, Task t, TaskStep s, KanbanStage to, String how,
    {String? note}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!store.moveStepToStage(t, s, to, how: how, note: note)) return;
  final last = store.data.stages.lastOrNull;
  if (last == null || t.stageId == last.id) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text('All steps of "${t.title}" are done'),
      action: SnackBarAction(
        label: 'Move it to ${last.name}',
        onPressed: () {
          if (context.mounted) moveWithRule(context, store, t, last, MoveHow.menu);
        },
      ),
    ));
}

/// Moves [t] to [to] and applies the "tick it off too" rule for the last stage.
Future<void> moveWithRule(BuildContext context, AppStore store, Task t, KanbanStage to, String how,
    {String? note}) async {
  final messenger = ScaffoldMessenger.of(context);
  // Steps on the board still open while the task goes to the last stage: ask what to do.
  var tickSteps = false;
  final open = t.boardSteps.where((s) => !s.done).length;
  if (open > 0 && to.id == store.data.stages.lastOrNull?.id && !(t.kanban && t.stageId == to.id)) {
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$open step${open == 1 ? ' is' : 's are'} still open'),
        content: Text('"${t.title}" is going to ${to.name}. What about its open steps?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, 'leave'), child: const Text('Leave them')),
          FilledButton(onPressed: () => Navigator.pop(c, 'tick'), child: const Text('Tick them all')),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    tickSteps = choice == 'tick';
  }
  if (!store.moveToStage(t, to, how: how, note: note)) return;
  if (tickSteps) store.tickAllSteps(t);
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
Future<void> showMoveTo(BuildContext context, AppStore store, Task t, [TaskStep? step]) async {
  final d = BoardDrag(t, step);
  final note = TextEditingController();
  final picked = await showDialog<KanbanStage>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Move "${step?.title ?? t.title}" to'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final s in store.data.stages)
            ListTile(
              dense: true,
              enabled: d.stageId != s.id,
              leading: _StageDot(s),
              title: Text(s.name),
              trailing: d.stageId == s.id ? const Text('Now') : null,
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
  await moveItem(context, store, d, picked, MoveHow.menu, note: text);
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

  /// Tasks whose steps were unfolded (or folded, when Show steps is on) by tapping their chip.
  final _flipped = <String>{};

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
            ? matchesSearch(t, q, store.data) || t.boardSteps.any((st) => st.title.toLowerCase().contains(q.toLowerCase()))
            : passesFilter(t, _filter, now) &&
                (_category == null ||
                    (_category!.isEmpty ? data.category(t.categoryId) == null : t.categoryId == _category))));
    return sortTasks(shown.toList(), data, now);
  }

  /// The column a task shows in: its stage, or the first one if that stage was removed on
  /// another device.
  String? _columnOf(Task t) => (data.stage(t.stageId) ?? data.stages.firstOrNull)?.id;

  /// The same for a step on the board.
  String? _stepColumn(TaskStep st) => (data.stage(st.stageId) ?? data.stages.firstOrNull)?.id;

  bool _unfolded(Task t) => store.boardShowSteps != _flipped.contains(t.id);

  bool get _anySteps => data.boardTasks.any((t) => t.boardSteps.isNotEmpty);

  Future<void> _addTo(KanbanStage s) async {
    final title = await askText(context, 'New task in ${s.name}');
    if (title == null || title.trim().isEmpty) return;
    store.addToStage(title, s);
  }

  void _open(Task t) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: t)));

  KanbanStage? _step(String? stageId, int by) {
    final i = data.stages.indexWhere((s) => s.id == stageId);
    final j = i + by;
    return i < 0 || j < 0 || j >= data.stages.length ? null : data.stages[j];
  }

  Color _colour(Task t, DateTime now) =>
      data.isLocked(t) ? lockedColor : ageColor(t, data.hoursToRed, byDue: data.colourByDue, now: now);

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

  Future<void> _stepMenu(Task t, TaskStep st) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(st.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Step of "${t.title}"'),
          ),
          ListTile(leading: const Icon(Icons.drive_file_move_outline), title: const Text('Move to…'),
              onTap: () => Navigator.pop(c, 'move')),
          ListTile(
              leading: Icon(st.done ? Icons.check_box_outline_blank : Icons.check_box_outlined),
              title: Text(st.done ? 'Untick' : 'Tick off'),
              onTap: () => Navigator.pop(c, 'tick')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Open its task'),
              onTap: () => Navigator.pop(c, 'open')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'move':
        await showMoveTo(context, store, t, st);
      case 'tick':
        store.toggleStep(t, st);
      case 'open':
        _open(t);
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
        final visible = [for (final s in stages) ...columns[s.id]!];
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
                Expanded(
                  child: store.boardLanes && _anySteps
                      ? _lanes(box.maxWidth, stages, visible, now)
                      : _wideBoard(box.maxWidth, stages, columns, visible, now),
                ),
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
                    for (final s in stages) _column(s, columns[s.id]!, visible, now, wide: false),
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
    final anySteps = _anySteps;
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
        if (anySteps && !(wide && store.boardLanes))
          IconButton(
            tooltip: store.boardShowSteps ? 'Fold all steps' : 'Show all steps',
            icon: Icon(store.boardShowSteps ? Icons.unfold_less : Icons.unfold_more),
            onPressed: () {
              _flipped.clear();
              store.setBoardView(showSteps: !store.boardShowSteps);
            },
          ),
        if (anySteps && wide)
          IconButton(
            tooltip: store.boardLanes ? 'Columns' : 'Lanes: a row for each task with steps',
            icon: Icon(store.boardLanes ? Icons.view_week_outlined : Icons.view_stream_outlined),
            onPressed: () => store.setBoardView(lanes: !store.boardLanes),
          ),
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
                    child: Text(
                        '${s.name} ${columns[s.id]!.length}${_stepCount(s) == 0 ? '' : '·${_stepCount(s)}'}',
                        style: TextStyle(color: _over(s) ? const Color(0xFFE65100) : null)),
                  ),
              ],
            ),
    );
  }

  int _count(KanbanStage s) => data.boardTasks.where((t) => _columnOf(t) == s.id).length;

  /// Steps on the board in [s], whatever is folded.
  int _stepCount(KanbanStage s) =>
      data.boardTasks.fold(0, (n, t) => n + t.boardSteps.where((st) => _stepColumn(st) == s.id).length);

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

  /// A drop zone for stage [s]: tasks and steps dropped on it move there.
  Widget _target(KanbanStage s, Widget Function(bool hovering) child) => DragTarget<BoardDrag>(
        onWillAcceptWithDetails: (d) => d.data.stageId != s.id,
        onAcceptWithDetails: (d) => moveItem(context, store, d.data, s, MoveHow.dragged),
        builder: (context, hovering, _) => child(hovering.isNotEmpty),
      );

  Widget _wideBoard(
      double width, List<KanbanStage> stages, Map<String, List<Task>> columns, List<Task> visible, DateTime now) {
    Widget col(KanbanStage s) => _target(
          s,
          (hovering) => Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: hovering
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _column(s, columns[s.id]!, visible, now, wide: true),
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

  Widget _stageHeader(KanbanStage s, {required bool wide}) {
    final total = _count(s);
    final steps = _stepCount(s);
    final over = _over(s);
    final hint = Theme.of(context).hintColor;
    return Container(
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
                  fontWeight: FontWeight.bold, color: over || s.colour != null ? const Color(0xDD000000) : null)),
        ),
        Flexible(
          child: Tooltip(
            message: [
              s.limit == null ? '$total on the board' : '$total of at most ${s.limit}',
              if (steps > 0) 'and $steps step${steps == 1 ? '' : 's'}',
            ].join(' '),
            child: Text(
                [s.limit == null ? '$total' : '$total/${s.limit}', if (steps > 0) '+ $steps step${steps == 1 ? '' : 's'}']
                    .join(' '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: over || s.colour != null ? const Color(0xAA000000) : hint)),
          ),
        ),
        IconButton(
          tooltip: 'Add a task to ${s.name}',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.add, size: 20, color: over || s.colour != null ? const Color(0xDD000000) : null),
          onPressed: () => _addTo(s),
        ),
      ]),
    );
  }

  Widget _column(KanbanStage s, List<Task> tasks, List<Task> visible, DateTime now, {required bool wide}) {
    final hint = Theme.of(context).hintColor;
    // Unfolded steps in this column whose task is in another one sit together at the top.
    final groups = [
      for (final t in visible)
        if (_unfolded(t) && _columnOf(t) != s.id)
          if (t.boardSteps.where((st) => _stepColumn(st) == s.id).toList() case final steps when steps.isNotEmpty)
            (t, steps),
    ];
    final children = <Widget>[
      for (final (t, steps) in groups) _StepGroup(task: t, color: _colour(t, now), count: steps.length, children: [
        for (final st in steps) _stepCard(t, st, s, now, wide: wide),
      ]),
      for (final t in tasks) ...[
        _card(t, s, now, wide: wide),
        if (_unfolded(t))
          for (final st in t.boardSteps)
            // One column at a time: show all of its steps under it, with their stage.
            if (!wide || _stepColumn(st) == s.id) _stepCard(t, st, s, now, wide: wide, under: true),
      ],
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stageHeader(s, wide: wide),
      Expanded(
        child: children.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_count(s) == 0 ? 'Nothing here' : 'None match the filter',
                      style: TextStyle(color: hint), textAlign: TextAlign.center),
                ),
              )
            : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: children),
      ),
    ]);
  }

  /// Item 56: one row per task with steps on the board, its task and steps across the stages;
  /// the other tasks share a row at the bottom.
  Widget _lanes(double width, List<KanbanStage> stages, List<Task> visible, DateTime now) {
    const label = 150.0;
    final colW = max(_minColumn, (width - label - 16) / stages.length);
    final total = label + colW * stages.length + 16;
    final withSteps = visible.where((t) => t.boardSteps.isNotEmpty).toList();
    final others = visible.where((t) => t.boardSteps.isEmpty).toList();
    final scheme = Theme.of(context).colorScheme;

    Widget cell(KanbanStage s, List<Widget> items) => SizedBox(
          width: colW,
          child: _target(
            s,
            (hovering) => Container(
              constraints: const BoxConstraints(minHeight: 56),
              margin: const EdgeInsets.all(3),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: hovering ? scheme.primaryContainer : scheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
            ),
          ),
        );

    Widget lane({required Widget head, required Color tint, required List<Widget> Function(KanbanStage) items}) =>
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: label - 8, child: head),
            for (final s in stages) cell(s, items(s)),
          ]),
        );

    final body = ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Row(children: [
          const SizedBox(width: label - 8),
          for (final s in stages)
            SizedBox(
                width: colW,
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: _stageHeader(s, wide: true))),
        ]),
      ),
      for (final t in withSteps)
        lane(
          tint: _colour(t, now).withValues(alpha: 0.18),
          head: _LaneHead(task: t, color: _colour(t, now), onTap: () => _open(t)),
          items: (s) => [
            if (_columnOf(t) == s.id) _card(t, s, now, wide: true, lanes: true),
            for (final st in t.boardSteps)
              if (_stepColumn(st) == s.id) _stepCard(t, st, s, now, wide: true),
          ],
        ),
      if (others.isNotEmpty)
        lane(
          tint: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          head: const Padding(
            padding: EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Other tasks', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('No steps on the board', style: TextStyle(fontSize: 12)),
            ]),
          ),
          items: (s) => [
            for (final t in others)
              if (_columnOf(t) == s.id) _card(t, s, now, wide: true),
          ],
        ),
    ]);
    if (total <= width) return body;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: total, child: body));
  }

  /// Wraps a card so it can be dragged (and on touch screens swiped a stage on).
  Widget _movable(Widget card, BoardDrag d, String key, {KanbanStage? back, KanbanStage? next, required bool wide}) {
    if (!wide) return card;
    final feedback = Material(
      elevation: 6,
      color: Colors.transparent,
      child: SizedBox(width: 220, child: Opacity(opacity: 0.9, child: card)),
    );
    final ghost = Opacity(opacity: 0.3, child: card);
    if (!_touch) {
      return Draggable<BoardDrag>(
          key: ValueKey('kcard-$key'), data: d, feedback: feedback, childWhenDragging: ghost, child: card);
    }
    final swipeable = Dismissible(
      key: ValueKey('kswipe-$key'),
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
        if (to != null) await moveItem(context, store, d, to, MoveHow.swiped);
        return false; // the board redraws with the card in its new column
      },
      child: card,
    );
    // Phones: press and hold to drag, so a quick sideways swipe moves one stage instead.
    return LongPressDraggable<BoardDrag>(
        key: ValueKey('kcard-$key'), data: d, feedback: feedback, childWhenDragging: ghost, child: swipeable);
  }

  Widget _card(Task t, KanbanStage s, DateTime now, {required bool wide, bool lanes = false}) {
    final next = _step(t.stageId, 1), back = _step(t.stageId, -1);
    final steps = t.boardSteps;
    final parent = data.active.where((p) => p.steps.any((st) => st.taskId == t.id)).firstOrNull;
    final card = _KanbanCard(
      task: t,
      stage: s,
      color: _colour(t, now),
      categoryName: data.category(t.categoryId)?.name,
      now: now,
      onTap: () => _open(t),
      onMenu: () => _cardMenu(t),
      // One column at a time: a button moves it on, since sideways swipes change column.
      onNext: wide || next == null ? null : () => moveWithRule(context, store, t, next, MoveHow.menu),
      nextName: next?.name,
      stepOf: parent?.title,
      stepsChip: steps.isEmpty || lanes
          ? null
          : _StepsChip(
              steps: steps,
              firstStageId: data.stages.first.id,
              unfolded: _unfolded(t),
              onTap: () => setState(() => _flipped.contains(t.id) ? _flipped.remove(t.id) : _flipped.add(t.id)),
            ),
    );
    return _movable(card, BoardDrag(t), t.id, back: back, next: next, wide: wide);
  }

  Widget _stepCard(Task t, TaskStep st, KanbanStage column, DateTime now, {required bool wide, bool under = false}) {
    final next = _step(st.stageId, 1), back = _step(st.stageId, -1);
    final stage = data.stage(_stepColumn(st));
    final since = st.stageSince;
    final card = _StepCard(
      step: st,
      color: _colour(t, now),
      under: under,
      details: [
        'step ${t.steps.indexOf(st) + 1} of ${t.steps.length}',
        if (stage != null && since != null && !st.done)
          '${stage.name} for ${describeSpell(now.difference(since))}'
        else if (stage != null && stage.id != column.id)
          stage.name,
      ].join(' · '),
      onTap: () => _stepMenu(t, st),
      onNext: wide || next == null ? null : () => moveStepWithRule(context, store, t, st, next, MoveHow.menu),
      nextName: next?.name,
    );
    return _movable(card, BoardDrag(t, st), '${t.id}-${st.id}', back: back, next: next, wide: wide);
  }
}

/// The chip on a task's card that folds and unfolds its steps.
class _StepsChip extends StatelessWidget {
  const _StepsChip({required this.steps, required this.firstStageId, required this.unfolded, required this.onTap});

  final List<TaskStep> steps;
  final String firstStageId;
  final bool unfolded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = steps.where((s) => s.done).length;
    final going = steps.where((s) => !s.done && s.stageId != firstStageId).length;
    final n = steps.length;
    final text = unfolded
        ? 'Hide $n step${n == 1 ? '' : 's'}'
        : '$n step${n == 1 ? '' : 's'}: ${[if (going > 0) '$going under way', '$done done'].join(', ')}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: const Color(0x33FFFFFF),
        shape: const StadiumBorder(side: BorderSide(color: Color(0x55000000))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.checklist, size: 16, color: Color(0xDD000000)),
                const SizedBox(width: 6),
                Flexible(child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xDD000000)))),
                Icon(unfolded ? Icons.expand_less : Icons.expand_more, size: 18, color: const Color(0xDD000000)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Steps of a task that sits in another column, gathered under the task's name.
class _StepGroup extends StatelessWidget {
  const _StepGroup({required this.task, required this.color, required this.count, required this.children});

  final Task task;
  final Color color;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${task.title} · $count step${count == 1 ? '' : 's'} here',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          ...children,
        ]),
      );
}

/// The task at the start of its lane.
class _LaneHead extends StatelessWidget {
  const _LaneHead({required this.task, required this.color, required this.onTap});

  final Task task;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = task.steps.length;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 5))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('$n step${n == 1 ? '' : 's'} · ${task.stepsDone} done',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ]),
      ),
    );
  }
}

/// A checklist step on the board: smaller than a task, tinted and edged in its task's colour.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.color,
    required this.details,
    required this.onTap,
    this.under = false,
    this.onNext,
    this.nextName,
  });

  final TaskStep step;
  final Color color;
  final String details;
  final VoidCallback onTap;

  /// Straight under its task's card: indented.
  final bool under;
  final VoidCallback? onNext;
  final String? nextName;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final ink = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.fromLTRB(under ? 22 : 8, 2, 8, 2),
      child: Material(
        color: Color.alphaBlend(color.withValues(alpha: 0.28), surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: color.withValues(alpha: 0.8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
            child: Row(children: [
              Icon(step.done ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: ink.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(step.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          decoration: step.done ? TextDecoration.lineThrough : null,
                          color: step.done ? ink.withValues(alpha: 0.6) : ink)),
                  Text(details, style: TextStyle(fontSize: 11, color: ink.withValues(alpha: 0.7))),
                ]),
              ),
              if (onNext != null)
                IconButton(
                  tooltip: 'Move to $nextName',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  onPressed: onNext,
                ),
              if (onNext == null) const SizedBox(width: 8),
            ]),
          ),
        ),
      ),
    );
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
    this.stepOf,
    this.stepsChip,
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

  /// The task this one was made from ("Make into task" on a checklist step).
  final String? stepOf;

  /// Item 56: folds and unfolds its steps on the board.
  final Widget? stepsChip;

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
                      if (task.steps.isNotEmpty && stepsChip == null)
                        Text('${task.stepsDone}/${task.steps.length}', style: soft),
                      if (task.estimate != null) Text(shortMinutes(task.estimate!), style: soft),
                    ]),
                    if (since != null) Text('${stage.name} for ${describeSpell(now.difference(since))}', style: soft),
                    if (stepOf != null) Text('Step of "$stepOf"', style: soft),
                    ?stepsChip,
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
