import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../gantt.dart';
import '../habits.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/worked_week.dart';
import 'settings_page.dart' show askText;
import 'task_page.dart';

/// Item 78: every habit with its week, streak and how this month is going.
class HabitsPage extends StatelessWidget {
  const HabitsPage({super.key, required this.store});

  final AppStore store;

  Future<void> _add(BuildContext context) async {
    final name = await askText(context, 'New habit');
    if (name == null || name.trim().isEmpty) return;
    final t = store.addTask(name.trim());
    store.setHabit(t, true);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskPage(store: store, task: t)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final now = DateTime.now();
        final habits = store.data.habits.toList()..sort((a, b) => (a.habitPaused ? 1 : 0) - (b.habitPaused ? 1 : 0));
        final (done, due) = habitsToday(store.data, now);
        return Scaffold(
          appBar: AppBar(title: const Text('Habits')),
          floatingActionButton: FloatingActionButton(
            tooltip: 'New habit',
            onPressed: () => _add(context),
            child: const Icon(Icons.add),
          ),
          body: habits.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No habits yet.\n\nTap + for a new one, or open a task and turn on "Habit". '
                      'A repeating task keeps its history when it becomes a habit.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 88), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(due == 0 ? 'Nothing due today' : 'Today: $done of $due done',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (final t in habits) _HabitCard(store: store, task: t, now: now),
                ]),
        );
      },
    );
  }
}

class _HabitCard extends StatelessWidget {
  const _HabitCard({required this.store, required this.task, required this.now});

  final AppStore store;
  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = streak(task, now);
    final score = monthScore(task, now, now);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => HabitMonthPage(store: store, task: task))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(task.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: task.habitPaused ? theme.disabledColor : null, fontWeight: FontWeight.w600)),
              ),
              if (task.habitPaused) const Chip(label: Text('Paused'), visualDensity: VisualDensity.compact),
            ]),
            Text(
              [
                goalText(task),
                if (n > 0) 'streak ${streakText(task, n)}',
                if (score != null) '${(score * 100).round()}% this month',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            WorkedWeek(
              task: task,
              now: now,
              size: 34,
              onToggle: task.habitPaused ? null : (d) => store.setWorked(task, d, !task.workedOn(d)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One habit by the month: a calendar of ticks (tap a day so far to change it), the last 12
/// months as a strip, streaks, and pause.
class HabitMonthPage extends StatefulWidget {
  const HabitMonthPage({super.key, required this.store, required this.task});

  final AppStore store;
  final Task task;

  @override
  State<HabitMonthPage> createState() => _HabitMonthPageState();
}

class _HabitMonthPageState extends State<HabitMonthPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Task get task => widget.task;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final now = DateTime.now();
        final today = dayOf(now);
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final first = _month;
        final daysIn = DateTime(first.year, first.month + 1, 0).day;
        final lead = first.weekday - 1;
        final score = monthScore(task, first, now);
        final thisMonth = DateTime(today.year, today.month);
        return Scaffold(
          appBar: AppBar(
            title: Text(task.title),
            actions: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => TaskPage(store: widget.store, task: task))),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Text(
              [
                goalText(task),
                'streak ${streakText(task, streak(task, now))}',
                'best ${streakText(task, bestStreak(task, now))}',
              ].join(' · '),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Row(children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Expanded(
                child: Text(
                  '${DateFormat('MMMM y').format(first)}${score == null ? '' : ' · ${(score * 100).round()}%'}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right),
                onPressed: !first.isBefore(thisMonth)
                    ? null
                    : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ]),
            Row(children: [
              for (final l in WorkedWeek.letters)
                Expanded(child: Center(child: Text(l, style: theme.textTheme.labelSmall))),
            ]),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [
                for (var i = 0; i < lead; i++) const SizedBox(),
                for (var d = 1; d <= daysIn; d++)
                  Builder(builder: (context) {
                    final day = DateTime(first.year, first.month, d);
                    final on = task.workedOn(day);
                    final future = day.isAfter(today);
                    final wanted = scheduledOn(task, day);
                    final paused = pausedOn(task, day);
                    return Semantics(
                      label: '${DateFormat('d MMMM').format(day)}, ${on ? 'done' : paused ? 'paused' : 'not done'}',
                      button: !future,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: future ? null : () => widget.store.setWorked(task, day, !on),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on
                                ? scheme.primary
                                : paused
                                    ? scheme.surfaceContainerHighest
                                    : null,
                            border: day == today
                                ? Border.all(color: scheme.primary, width: 2)
                                : wanted && !future && !on
                                    ? Border.all(color: scheme.outlineVariant)
                                    : null,
                          ),
                          child: Text('$d',
                              style: TextStyle(
                                color: on
                                    ? scheme.onPrimary
                                    : future || !wanted
                                        ? theme.disabledColor
                                        : null,
                              )),
                        ),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 16),
            Text('Last 12 months', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Row(children: [
              for (var i = 11; i >= 0; i--)
                Builder(builder: (context) {
                  final m = DateTime(thisMonth.year, thisMonth.month - i);
                  final s = monthScore(task, m, now);
                  return Expanded(
                    child: Tooltip(
                      message: '${DateFormat('MMM y').format(m)}: ${s == null ? 'nothing yet' : '${(s * 100).round()}%'}',
                      child: InkWell(
                        onTap: () => setState(() => _month = m),
                        child: Column(children: [
                          Container(
                            height: 28,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: s == null
                                  ? scheme.surfaceContainerHighest
                                  : Color.lerp(scheme.surfaceContainerHighest, scheme.primary, s),
                              borderRadius: BorderRadius.circular(4),
                              border: m == _month ? Border.all(color: scheme.onSurface) : null,
                            ),
                          ),
                          Text(DateFormat('MMMMM').format(m), style: theme.textTheme.labelSmall),
                        ]),
                      ),
                    ),
                  );
                }),
            ]),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: Icon(task.habitPaused ? Icons.play_arrow : Icons.pause),
                label: Text(task.habitPaused ? 'Carry on' : 'Pause (keeps the streak)'),
                onPressed: () => widget.store.pauseHabit(task, !task.habitPaused),
              ),
            ),
          ]),
        );
      },
    );
  }
}
