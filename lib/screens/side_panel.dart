import 'achievements_page.dart' show AchievementsView;
import 'gantt_page.dart' show GanttTimeline;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../native.dart';
import '../stats.dart';
import '../store.dart';
import '../task_list.dart' show sortTasks;
import 'archive_page.dart';
import 'calendar_page.dart';
import 'events_page.dart';
import 'kanban_page.dart' show KanbanPage, boardColumnOrder, describeSpell, moveWithRule;
import 'matrix_page.dart';
import 'starred_page.dart' show pickTask;
import 'stats_page.dart';

/// Item 59: the right-hand panel on a wide screen (the unfolded Fold, a tablet, a computer)
/// when no task is open. A row of chips picks the view; the choice is remembered on this device
/// and opening a task comes back to it.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.store, required this.onOpen});

  final AppStore store;
  final void Function(Task t) onOpen;

  @override
  Widget build(BuildContext context) {
    final views = [for (final v in store.shownPanelViews) if (v != PanelView.events || Native.supported) v];
    final view = views.contains(store.panelView) ? store.panelView : views.first;
    return Material(child: Column(children: [
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SafeArea(
          bottom: false,
          left: false,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(children: [
              for (final v in views)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(v.label),
                    selected: v == view,
                    onSelected: (_) => store.showPanel(v),
                  ),
                ),
            ]),
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: switch (view) {
          PanelView.agenda => AgendaView(store: store, onOpen: onOpen),
          PanelView.matrix => MatrixPage(store: store),
          PanelView.board => MiniBoard(store: store, onOpen: onOpen),
          PanelView.timeline => GanttTimeline(store: store, onOpen: onOpen),
          PanelView.calendar => CalendarPage(store: store),
          PanelView.events => EventsPage(store: store),
          PanelView.stats => PanelStats(store: store),
          PanelView.achievements => AchievementsView(store: store, onOpen: onOpen),
          PanelView.archive => ArchivePage(store: store, embedded: true, onOpen: onOpen),
        },
      ),
    ]));
  }
}

/// One line in the agenda: a task, or a step with its own date.
class AgendaItem {
  const AgendaItem(this.task, this.when, {this.step});

  final Task task;
  final TaskStep? step;
  final DateTime when;
}

/// The agenda's groups: Overdue, Today, Tomorrow, then each of the next days up to a week.
/// Snoozed tasks and ticked steps are left out.
List<(String, List<AgendaItem>)> agendaGroups(AppData data, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final end = today.add(const Duration(days: 8));
  final items = <AgendaItem>[
    for (final t in data.active)
      if (t.dueAt != null && t.dueAt!.isBefore(end) && !t.isSnoozed(now)) AgendaItem(t, t.dueAt!),
    for (final t in data.active)
      for (final s in t.steps)
        if (s.dueAt != null && !s.done && s.dueAt!.isBefore(end)) AgendaItem(t, s.dueAt!, step: s),
  ]..sort((a, b) => a.when.compareTo(b.when));
  final fmt = DateFormat('EEEE d MMM');
  final groups = <String, List<AgendaItem>>{};
  for (final i in items) {
    final day = DateTime(i.when.year, i.when.month, i.when.day);
    final name = i.when.isBefore(now) && day.isBefore(today)
        ? 'Overdue'
        : day == today
            ? 'Today'
            : day == today.add(const Duration(days: 1))
                ? 'Tomorrow'
                : fmt.format(day);
    groups.putIfAbsent(name, () => []).add(i);
  }
  return [for (final e in groups.entries) (e.key, e.value)];
}

/// Item 59: what is overdue, due today and in the next 7 days, steps with dates included.
class AgendaView extends StatelessWidget {
  const AgendaView({super.key, required this.store, required this.onOpen});

  final AppStore store;
  final void Function(Task t) onOpen;

  @override
  Widget build(BuildContext context) {
    final data = store.data;
    final now = DateTime.now();
    final groups = agendaGroups(data, now);
    final hint = Theme.of(context).hintColor;
    final time = DateFormat('HH:mm');
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Nothing due in the next 7 days.', style: TextStyle(color: hint)),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      for (final (name, items) in groups) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
          child: Text(name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: name == 'Overdue' ? Colors.red : null)),
        ),
        for (final i in items)
          ListTile(
            dense: true,
            leading: Checkbox(
              value: false,
              onChanged: (_) => i.step == null ? store.complete(i.task) : store.toggleStep(i.task, i.step!),
            ),
            title: Text(i.step?.title ?? i.task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([
              if (name == 'Overdue') DateFormat('EEE d MMM').format(i.when),
              time.format(i.when),
              if (i.step != null) 'Step of ${i.task.title}',
              if (i.step == null) ?data.category(i.task.categoryId)?.name,
            ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: i.task.starred ? const Icon(Icons.star, size: 18, color: Colors.amber) : null,
            onTap: () => onOpen(i.task),
          ),
      ],
    ]);
  }
}

/// Item 59: the Kanban board in a narrow panel: one row per stage with its count, unfolding to
/// its tasks, with + to put a task in that stage.
class MiniBoard extends StatefulWidget {
  const MiniBoard({super.key, required this.store, required this.onOpen});

  final AppStore store;
  final void Function(Task t) onOpen;

  @override
  State<MiniBoard> createState() => _MiniBoardState();
}

class _MiniBoardState extends State<MiniBoard> {
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final data = store.data;
    final hint = Theme.of(context).hintColor;
    if (data.stages.isEmpty) return const Center(child: Text('No board stages. Add them in Settings.'));
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      for (final st in data.stages)
        Builder(builder: (context) {
          final tasks = boardColumnOrder(
              sortTasks([for (final t in data.boardTasks) if ((data.stage(t.stageId) ?? data.stages.first).id == st.id) t],
                  data, DateTime.now()),
              data);
          final open = _open.contains(st.id);
          return Column(children: [
            ListTile(
              leading: Icon(open ? Icons.expand_more : Icons.chevron_right),
              title: Text(st.name),
              subtitle: st.limit != null && tasks.length > st.limit!
                  ? Text('Over the limit of ${st.limit}', style: const TextStyle(color: Colors.red))
                  : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Put a task in ${st.name}',
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () async {
                    final t = await pickTask(context, data, title: 'Put in ${st.name}');
                    if (t == null || !context.mounted) return;
                    if (!t.kanban) {
                      store.setOnBoard(t, true, stage: st);
                    } else {
                      await moveWithRule(context, store, t, st, MoveHow.menu);
                    }
                  },
                ),
                CircleAvatar(radius: 14, child: Text('${tasks.length}', style: const TextStyle(fontSize: 13))),
              ]),
              onTap: () => setState(() => open ? _open.remove(st.id) : _open.add(st.id)),
            ),
            if (open)
              for (final t in tasks)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 56, right: 16),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: t.stageSince == null
                      ? null
                      : Text('For ${describeSpell(DateTime.now().difference(t.stageSince!))}',
                          style: TextStyle(fontSize: 12, color: hint)),
                  onTap: () => widget.onOpen(t),
                ),
          ]);
        }),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Tap a stage to see its tasks, or + to put a task there.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: hint)),
      ),
      Center(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => KanbanPage(store: store))),
          icon: const Icon(Icons.open_in_full, size: 18),
          label: const Text('Open the whole board'),
        ),
      ),
    ]);
  }
}

/// Item 59: the statistics picked in Settings, stacked to fit the panel.
class PanelStats extends StatelessWidget {
  const PanelStats({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final data = store.data;
    final now = DateTime.now();
    final stats = Stats(data, now);
    final week = Stats.weekOf(now);
    final hint = Theme.of(context).hintColor;
    final picked = store.panelStats;
    Widget card(String title, List<Widget> rows) => Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ...rows,
            ]),
          ),
        );
    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [Expanded(child: Text(a)), Text(b, style: const TextStyle(fontWeight: FontWeight.w600))]),
        );
    final weekStart = now.subtract(const Duration(days: 6));
    final from = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      if (picked.contains(PanelStat.week))
        card('This week', [
          row('Done today', '${stats.doneToday}'),
          row('Done this week', '${stats.doneThisWeek}'),
          row('Streak', '${stats.streak} day${stats.streak == 1 ? '' : 's'}'),
          row('Open', '${stats.openCount}'),
          row('Overdue', '${stats.overdueCount}'),
        ]),
      if (picked.contains(PanelStat.addedDone))
        card('Last 7 days', [
          row('Added', '${stats.added.where((a) => !a.createdAt.isBefore(from)).length}'),
          row('Done', '${stats.doneSince(from).length}'),
        ]),
      if (picked.contains(PanelStat.category))
        card('By category this week', [
          for (final (name, done, open) in stats.byCategory(week))
            if (done + open > 0) row(name, '$done done · $open open'),
        ]),
      if (picked.contains(PanelStat.source))
        card('By source this week', [
          for (final r in stats.bySource(week))
            if (r.added + r.done > 0) row(TaskSource.label(r.source), '${r.added} added · ${r.done} done'),
        ]),
      if (picked.contains(PanelStat.board))
        if (stats.kanban(null) case final k?)
          card('Typical time in each stage', [
            for (final st in k.stages)
              if (st.median != null) row(st.stage.name, describeSpell(Duration(minutes: st.median!))),
          ]),
      if (picked.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Pick what shows here in Settings, Right-hand panel.', style: TextStyle(color: hint)),
        ),
      const SizedBox(height: 8),
      Center(
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatsPage(store: store))),
          icon: const Icon(Icons.bar_chart, size: 18),
          label: const Text('All statistics'),
        ),
      ),
    ]);
  }
}

/// Item 59: Settings → Right-hand panel.
class PanelSettingsPage extends StatelessWidget {
  const PanelSettingsPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Right-hand panel')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final hint = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
          Widget heading(String t) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(t, style: Theme.of(context).textTheme.titleMedium),
              );
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                  'On a wide screen (the Fold unfolded, a tablet or a computer) the right-hand side shows this when no '
                  'task is open. These settings are for this device only.',
                  style: hint),
            ),
            ListTile(
              title: const Text('Starts on'),
              trailing: DropdownButton<PanelView>(
                value: store.panelStart,
                items: [for (final v in PanelView.values) DropdownMenuItem(value: v, child: Text(v.label))],
                onChanged: (v) {
                  if (v == null) return;
                  store
                    ..panelStart = v
                    ..panelView = v
                    ..panelHidden.remove(v)
                    ..panelSettingsChanged();
                },
              ),
            ),
            SwitchListTile(
              title: const Text('Reopen the view I used last'),
              subtitle: const Text('Instead of starting on the one above each time'),
              value: store.panelRemember,
              onChanged: (v) => store
                ..panelRemember = v
                ..panelSettingsChanged(),
            ),
            ListTile(
              title: const Text('When I unfold the phone, open'),
              subtitle: DropdownButton<UnfoldOpens>(
                isExpanded: true,
                value: store.unfoldOpens,
                items: [for (final v in UnfoldOpens.values) DropdownMenuItem(value: v, child: Text(v.label))],
                onChanged: (v) {
                  if (v == null) return;
                  store
                    ..unfoldOpens = v
                    ..panelSettingsChanged();
                },
              ),
            ),
            heading('Views to offer'),
            for (final v in PanelView.values)
              CheckboxListTile(
                title: Text(v.label),
                subtitle: v == PanelView.matrix
                    ? const Text('Takes half the screen, so the four boxes fit')
                    : v == PanelView.events && !Native.supported
                        ? const Text('Phones and tablets only')
                        : null,
                value: !store.panelHidden.contains(v),
                onChanged: v == store.panelStart
                    ? null
                    : (on) {
                        on == true ? store.panelHidden.remove(v) : store.panelHidden.add(v);
                        store.panelSettingsChanged();
                      },
              ),
            heading('Statistics view shows'),
            for (final p in PanelStat.values)
              CheckboxListTile(
                title: Text(p.label),
                value: store.panelStats.contains(p),
                onChanged: (on) {
                  on == true ? store.panelStats.add(p) : store.panelStats.remove(p);
                  store.panelSettingsChanged();
                },
              ),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }
}
