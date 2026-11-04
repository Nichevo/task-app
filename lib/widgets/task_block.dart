import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../task_list.dart';
import 'link_text.dart';

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
    this.selected = false,
    this.lockedBy,
    this.categoryName,
    this.onStep,
    this.onSkip,
    this.stageName,
    this.boxName,
    this.onBoard,
    this.onWorked,
  });

  final Task task;
  final Color color;
  final bool expanded;
  final bool archived;

  /// Outlined when it is the task open in the side pane.
  final bool selected;

  /// Title of the earlier task this one is waiting for; shown greyed with a lock.
  final String? lockedBy;

  /// Shown in the expanded details.
  final String? categoryName;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final VoidCallback? onCheck;
  final Widget? trailing;

  /// Ticks a checklist step from the expanded block.
  final ValueChanged<TaskStep>? onStep;

  /// Moves a repeating task to its next date without ticking it off.
  final VoidCallback? onSkip;

  /// The Kanban stage it is in, shown as a small label; null when not on the board.
  final String? stageName;

  /// Item 60: the matrix box it is in, shown as a small label; null when not on the matrix.
  final String? boxName;

  /// Puts it on the Kanban board (offered in the expanded block).
  final VoidCallback? onBoard;

  /// Item 75: ticks today as a day worked on it, without finishing it.
  final VoidCallback? onWorked;

  /// One-line notes preview on the thin block, only when there are notes.
  bool get preview => !expanded && task.notes.trim().isNotEmpty;

  Widget _badge(IconData icon, String tip, Color color) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Tooltip(message: tip, child: Icon(icon, size: 16, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xDD000000);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: selected ? const BorderSide(color: Color(0xDD000000), width: 2.5) : BorderSide.none,
        ),
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
                    height: preview ? 54 : 42,
                    child: Row(children: [
                      if (lockedBy != null)
                        Tooltip(
                          message: 'Waiting for "$lockedBy"',
                          child: const SizedBox(width: 48, child: Icon(Icons.lock_outline, color: ink)),
                        )
                      else if (onCheck != null)
                        IconButton(
                          tooltip: 'Tick off',
                          icon: const Icon(Icons.check_box_outline_blank, color: ink),
                          onPressed: onCheck,
                        )
                      else
                        const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(task.title,
                                    maxLines: expanded ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              ),
                              if (task.starred) _badge(Icons.star, 'Starred', const Color(0xFF8D6E00)),
                              if (task.steps.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text('${task.stepsDone}/${task.steps.length}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                                ),
                              if (task.emails.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: '${task.emails.length} email${task.emails.length == 1 ? '' : 's'} attached',
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.mail_outline, size: 14, color: Color(0xAA000000)),
                                      if (task.emails.length > 1)
                                        Text('${task.emails.length}',
                                            style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                                    ]),
                                  ),
                                ),
                              if (task.estimate != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: 'About ${describeMinutes(task.estimate!)}',
                                    child: Text(shortMinutes(task.estimate!),
                                        style: const TextStyle(fontSize: 12, color: Color(0xAA000000))),
                                  ),
                                ),
                              if (stageName != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: 'On the Kanban board',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: const Color(0x88000000)),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(stageName!, style: const TextStyle(fontSize: 11, color: ink)),
                                    ),
                                  ),
                                ),
                              if (boxName != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Tooltip(
                                    message: 'On the matrix',
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.grid_view, size: 12, color: ink),
                                      const SizedBox(width: 2),
                                      Text(boxName!, style: const TextStyle(fontSize: 11, color: ink)),
                                    ]),
                                  ),
                                ),
                              if (task.repeat != null) _badge(Icons.repeat, task.repeat!.describe(), ink),
                              if (task.isSnoozed(DateTime.now())) _badge(Icons.snooze, 'Snoozed', ink),
                            ]),
                            if (preview)
                              Text(task.notes.split('\n').first,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, color: Color(0xAA000000))),
                          ],
                        ),
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
        if (categoryName != null) _line('Category', categoryName!),
        if (task.repeat != null) _line('Repeats', task.repeat!.describe()),
        if (task.estimate != null) _line('Takes', 'about ${describeMinutes(task.estimate!)}'),
        if (stageName != null) _line('Board', stageName!),
        if (boxName != null) _line('Matrix', boxName!),
        if ((task.waitingOn ?? '').isNotEmpty) _line('Waiting on', task.waitingOn!),
        if (task.place != null) _line('Place', '${task.placeLeave ? 'Leaving' : 'Arriving at'} ${task.place}'),
        if (lockedBy != null) _line('After', lockedBy!),
        if (task.isSnoozed(DateTime.now())) _line('Snoozed', 'until ${dateTimeFmt.format(task.snoozedUntil!)}'),
        if (task.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinkText(task.notes, linkColor: const Color(0xFF0D47A1)),
          ),
        if (task.steps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(children: [
              for (final s in task.steps)
                InkWell(
                  onTap: onStep == null || archived ? null : () => onStep!(s),
                  child: Row(children: [
                    Icon(s.done ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.title,
                          style: TextStyle(
                              decoration: s.done ? TextDecoration.lineThrough : null,
                              color: s.done ? const Color(0x88000000) : ink)),
                    ),
                    if (s.taskId != null) const Icon(Icons.link, size: 16, color: Color(0x88000000)),
                  ]),
                ),
            ]),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(children: [
            if (onSkip != null && task.repeat != null && !archived)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: ink),
                onPressed: onSkip,
                icon: const Icon(Icons.skip_next, size: 18),
                label: const Text('Skip'),
              ),
            if (onWorked != null && !archived)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: ink),
                onPressed: onWorked,
                icon: Icon(task.workedOn(DateTime.now()) ? Icons.check_circle : Icons.radio_button_unchecked, size: 18),
                label: const Text('Worked on it today'),
              ),
            if (onBoard != null && !archived)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: ink),
                onPressed: onBoard,
                icon: const Icon(Icons.view_kanban_outlined, size: 18),
                label: const Text('Add to board'),
              ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: ink),
              onPressed: onOpen,
              icon: const Icon(Icons.edit, size: 18),
              label: Text(archived ? 'Details' : 'Edit / set due date'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          SizedBox(width: 72, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600))),
        ]),
      );
}
