import 'package:flutter/material.dart';

import '../gantt.dart';
import '../models.dart';
import 'burn_down_chart.dart';

/// Item 86: a task's own burn-down, folded until opened, with the steps / days of work switch.
/// Shows nothing for a task without one (see [taskBurnDown]).
class TaskBurnDownTile extends StatefulWidget {
  const TaskBurnDownTile({super.key, required this.task, required this.data, this.padding = EdgeInsets.zero});

  final Task task;
  final AppData data;
  final EdgeInsetsGeometry padding;

  @override
  State<TaskBurnDownTile> createState() => _TaskBurnDownTileState();
}

class _TaskBurnDownTileState extends State<TaskBurnDownTile> {
  BurnUnit _unit = BurnUnit.items;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final burn = taskBurnDown(widget.task, widget.data, now, unit: _unit);
    if (burn == null) return const SizedBox.shrink();
    final late = burn.daysLate;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: widget.padding,
      child: ExpansionTile(
        leading: const Icon(Icons.trending_down),
        tilePadding: const EdgeInsets.only(left: 16, right: 8),
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('Burn-down'),
        subtitle: Text(
          burnSummary(burn),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: late != null && late > 0 && burn.now > 0 ? scheme.error : null),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<BurnUnit>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: BurnUnit.items, label: Text('Steps')),
              ButtonSegment(value: BurnUnit.days, label: Text('Days of work')),
            ],
            selected: {_unit},
            onSelectionChanged: (v) => setState(() => _unit = v.first),
          ),
          const SizedBox(height: 8),
          BurnDownChart(burn: burn, now: now, height: 120),
        ],
      ),
    );
  }
}
