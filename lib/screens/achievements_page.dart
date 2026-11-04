import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../achievements.dart';
import '../gantt.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/burn_down_chart.dart';
import 'task_page.dart';

/// Item 76: what got done in a category over a period.
class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Achievements')),
        body: AchievementsView(store: store),
      );
}

/// The page's contents, also shown in the right-hand panel.
class AchievementsView extends StatefulWidget {
  const AchievementsView({super.key, required this.store, this.onOpen});

  final AppStore store;

  /// Opens a task in the side pane instead of a new page.
  final ValueChanged<Task>? onOpen;

  @override
  State<AchievementsView> createState() => _AchievementsViewState();
}

class _AchievementsViewState extends State<AchievementsView> {
  AchievePeriod _period = AchievePeriod.lastWeek;
  String? _category;

  AppData get data => widget.store.data;

  void _open(Task t) => widget.onOpen != null
      ? widget.onOpen!(t)
      : Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: widget.store, task: t)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final now = DateTime.now();
        if (_category != null && _category!.isNotEmpty && data.category(_category) == null) _category = null;
        final a = Achievements(data, _period, now, categoryId: _category);
        final day = DateFormat('EEE d MMM');
        final theme = Theme.of(context);
        final finished = a.finished;
        final unfinished = a.unfinished;
        final burn = burnDown(burnTasks(data, _category), data, now);
        return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
          Row(children: [
            Expanded(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _category,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All categories')),
                  for (final c in data.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  const DropdownMenuItem(value: '', child: Text('No category')),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
            IconButton(
              tooltip: 'Copy as text',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: a.asText()));
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('Copied. Paste it into a message or a report.')));
              },
            ),
          ]),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final p in AchievePeriod.values)
              ChoiceChip(label: Text(p.label), selected: _period == p, onSelected: (_) => setState(() => _period = p)),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text('${day.format(a.from)} to ${day.format(addDays(a.to, -1))}', style: theme.textTheme.bodySmall),
          ),
          Row(children: [
            _Tile(a.tasksDone, 'tasks done'),
            _Tile(a.stepsTicked, 'steps ticked'),
            _Tile(a.daysWorked, 'days worked'),
          ]),
          if (burn != null && burn.now > 0) ...[
            const SizedBox(height: 12),
            Text('Gantt burn-down', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            BurnDownChart(burn: burn, now: now, height: 100),
            Text(burnSummary(burn), style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Text('Finished (${finished.length})', style: theme.textTheme.titleSmall),
          if (finished.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing ticked off in this period.')),
          for (final f in finished)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(f.task.title),
              subtitle: Text([
                'Done ${day.format(f.done)}',
                if (planLine(f).isNotEmpty) planLine(f),
                if (f.planStart != null || f.actualStart != null)
                  'Started ${f.actualStart == null ? '?' : day.format(f.actualStart!)}'
                      '${f.planStart == null ? '' : ' (planned ${day.format(dayOf(f.planStart!))})'}',
                if (f.task.steps.isNotEmpty) '${f.task.stepsDone} of ${f.task.steps.length} steps',
                if (f.daysWorked > 0) '${f.daysWorked} day${f.daysWorked == 1 ? '' : 's'} worked',
              ].join(' · ')),
              trailing: (f.daysLate ?? 0) > 0 ? Icon(Icons.schedule, color: theme.colorScheme.error) : null,
              onTap: () => _open(f.task),
            ),
          const SizedBox(height: 12),
          Text('Worked on, not finished (${unfinished.length})', style: theme.textTheme.titleSmall),
          if (unfinished.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Tick "Worked on it today" on a task to see it here.'),
            ),
          for (final w in unfinished)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timelapse),
              title: Text(w.task.title),
              subtitle: Text([
                '${w.daysWorked} day${w.daysWorked == 1 ? '' : 's'} worked',
                if (w.stepsTicked > 0) '${w.stepsTicked} step${w.stepsTicked == 1 ? '' : 's'} ticked',
                if (w.task.steps.isNotEmpty) '${w.task.stepsDone} of ${w.task.steps.length} steps in all',
                if (w.task.dueAt != null) 'due ${day.format(w.task.dueAt!)}',
              ].join(' · ')),
              onTap: () => _open(w.task),
            ),
          if (a.habits.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Habits', style: theme.textTheme.titleSmall),
            for (final (t, done, due) in a.habits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.repeat_on_outlined),
                title: Text(t.title),
                subtitle: Text('$done of $due${due == 0 ? '' : ' (${(min(done / due, 1.0) * 100).round()}%)'}'),
                onTap: () => _open(t),
              ),
          ],
        ]);
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.value, this.label);

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: const EdgeInsets.only(right: 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(children: [
            Text('$value', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}
