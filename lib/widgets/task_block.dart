import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

final dateTimeFmt = DateFormat('EEE d MMM yyyy, HH:mm');

/// Short "time added": just the time today, weekday this week, date otherwise.
String shortTime(DateTime d, [DateTime? now]) {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (!d.isBefore(today)) return DateFormat('HH:mm').format(d);
  if (today.difference(d).inDays < 6) return DateFormat('EEE HH:mm').format(d);
  return DateFormat('d MMM').format(d);
}

/// A full-width coloured block. Thin by default (name + time); tap to expand.
class TaskBlock extends StatelessWidget {
  const TaskBlock({
    super.key,
    required this.task,
    required this.color,
    required this.expanded,
    required this.onTap,
    required this.onOpen,
    this.onCheck,
    this.trailing,
    this.archived = false,
  });

  final Task task;
  final Color color;
  final bool expanded;
  final bool archived;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback? onCheck;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xDD000000);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(3),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: DefaultTextStyle(
              style: textTheme.bodyMedium!.copyWith(color: ink),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 42,
                    child: Row(children: [
                      if (onCheck != null)
                        IconButton(
                          tooltip: 'Tick off',
                          icon: const Icon(Icons.check_box_outline_blank, color: ink),
                          onPressed: onCheck,
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: Text(task.title,
                            maxLines: expanded ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      const SizedBox(width: 8),
                      Text(shortTime(archived ? task.closedAt! : task.createdAt),
                          style: const TextStyle(fontSize: 13)),
                      trailing ?? const SizedBox(width: 12),
                    ]),
                  ),
                  if (expanded) _details(context, ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context, Color ink) {
    final due = task.dueAt;
    final overdue = !archived && due != null && due.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _line('Created', dateTimeFmt.format(task.createdAt)),
        _line('Due', due == null ? 'No due date' : dateTimeFmt.format(due) + (overdue ? '  (overdue)' : ''),
            bold: overdue),
        if (archived) _line('Closed', dateTimeFmt.format(task.closedAt!)),
        if (task.notes.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(task.notes)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: ink),
            onPressed: onOpen,
            icon: const Icon(Icons.edit, size: 18),
            label: Text(archived ? 'Details' : 'Edit / set due date'),
          ),
        ),
      ]),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          SizedBox(width: 64, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w500))),
        ]),
      );
}
