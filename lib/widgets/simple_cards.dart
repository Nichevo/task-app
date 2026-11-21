import 'package:flutter/material.dart';

import '../models.dart';
import 'task_block.dart' show shortWhen;
import 'task_colors.dart';

/// Item 114: one entry of the simple view, either a group heading or a task.
sealed class SimpleEntry {
  const SimpleEntry();
}

class SimpleHeading extends SimpleEntry {
  const SimpleHeading(this.name);
  final String name;
}

class SimpleTask extends SimpleEntry {
  const SimpleTask(this.task);
  final Task task;
}

/// Item 114: the simple card view. Each task is a large plain card (name, due date, category,
/// its colour on the left edge) with its open steps as smaller cards under it. Nothing here can
/// be dragged, ticked or swiped: it is only for looking at.
class SimpleCards extends StatelessWidget {
  const SimpleCards({super.key, required this.entries, required this.data, this.footer});

  final List<SimpleEntry> entries;
  final AppData data;
  final Widget? footer;

  /// At least this wide (an open Fold, an iPad) shows two columns.
  static const twoColumnWidth = 640.0;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return LayoutBuilder(builder: (context, box) {
      final two = box.maxWidth >= twoColumnWidth;
      final groups = _groups();
      final children = <Widget>[];
      for (final (heading, tasks) in groups) {
        if (heading != null) children.add(_heading(context, heading));
        if (two) {
          // Each task goes in the shorter column, so the two stay about the same length.
          final cols = [<Widget>[], <Widget>[]];
          final heights = [0.0, 0.0];
          for (final t in tasks) {
            final i = heights[0] <= heights[1] ? 0 : 1;
            cols[i].add(SimpleTaskCard(task: t, data: data, now: now));
            heights[i] += 1 + 0.6 * t.steps.where((s) => !s.done).length;
          }
          children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in cols) Expanded(child: Column(children: c)),
          ]));
        } else {
          for (final t in tasks) {
            children.add(SimpleTaskCard(task: t, data: data, now: now));
          }
        }
      }
      if (footer case final f?) children.add(f);
      if (children.isEmpty) return const Center(child: Text('No tasks to show.'));
      return ListView(padding: const EdgeInsets.fromLTRB(0, 6, 0, 24), children: children);
    });
  }

  /// The tasks under each heading (a null heading when the list isn't grouped).
  List<(String?, List<Task>)> _groups() {
    final out = <(String?, List<Task>)>[];
    for (final e in entries) {
      switch (e) {
        case SimpleHeading h:
          out.add((h.name, []));
        case SimpleTask t:
          if (out.isEmpty) out.add((null, []));
          out.last.$2.add(t.task);
      }
    }
    return [for (final g in out) if (g.$2.isNotEmpty) g];
  }

  Widget _heading(BuildContext context, String name) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      );
}

/// "Due Fri 27 Nov", "Due today 15:00", "Overdue · was due Tue 18".
String simpleDue(DateTime? due, DateTime now) {
  if (due == null) return 'No date';
  final timed = due.hour != 0 || due.minute != 0;
  final when = shortWhen(due, now, time: timed);
  if (due.isBefore(timed ? now : DateTime(now.year, now.month, now.day))) return 'Overdue · was due $when';
  return 'Due $when';
}

class SimpleTaskCard extends StatelessWidget {
  const SimpleTaskCard({super.key, required this.task, required this.data, required this.now});

  final Task task;
  final AppData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final edge = ageColor(t, data.hoursToRed, byDue: data.colourByDue, now: now);
    final late = t.dueAt != null && simpleDue(t.dueAt, now).startsWith('Overdue');
    final doneSteps = t.steps.where((s) => s.done).length;
    final open = t.steps.where((s) => !s.done).toList();
    final details = [
      if (data.category(t.categoryId)?.name case final c?) c,
      if (t.steps.isNotEmpty) '$doneSteps of ${t.steps.length} steps done',
    ];
    final hint = TextStyle(fontSize: 14, color: scheme.onSurfaceVariant);
    final red = TextStyle(fontSize: 14, color: scheme.error, fontWeight: FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: edge, width: 8)),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Color(0x1A000000), offset: Offset(0, 1))],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title.isEmpty ? '(no name)' : t.title + (t.starred ? '  ★' : ''),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500, height: 1.25)),
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              TextSpan(text: simpleDue(t.dueAt, now), style: late ? red : hint),
              for (final d in details) TextSpan(text: ' · $d', style: hint),
            ])),
          ]),
        ),
        for (final s in open)
          Container(
            margin: const EdgeInsets.only(left: 26, top: 6),
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant, width: 1.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title, style: const TextStyle(fontSize: 15.5)),
              if (s.dueAt != null)
                Text(simpleDue(s.dueAt, now),
                    style: simpleDue(s.dueAt, now).startsWith('Overdue')
                        ? red.copyWith(fontSize: 12.5)
                        : hint.copyWith(fontSize: 12.5)),
            ]),
          ),
      ]),
    );
  }
}
