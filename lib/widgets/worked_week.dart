import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';

/// Item 75: the week (Monday to Sunday) as seven dots, filled on the days [task] was worked on.
/// Tapping a day up to today ticks or unticks it.
class WorkedWeek extends StatelessWidget {
  const WorkedWeek({super.key, required this.task, required this.onToggle, this.now, this.size = 30});

  final Task task;
  final ValueChanged<DateTime>? onToggle;
  final DateTime? now;
  final double size;

  static const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = now ?? DateTime.now();
    final day0 = DateTime(today.year, today.month, today.day);
    final monday = DateTime(day0.year, day0.month, day0.day - (day0.weekday - 1));
    return LayoutBuilder(builder: (context, box) {
      // Shrinks the dots to fit a narrow pane.
      final size = box.maxWidth.isFinite ? min(this.size, box.maxWidth / 7 - 6) : this.size;
      return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 7; i++)
        Builder(builder: (context) {
          final d = DateTime(monday.year, monday.month, monday.day + i);
          final on = task.workedOn(d);
          final future = d.isAfter(day0);
          final isToday = d == day0;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              label: '${letters[i]}, ${on ? 'worked' : 'not worked'}',
              button: !future,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: future || onToggle == null ? null : () => onToggle!(d),
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? scheme.primary : null,
                    border: Border.all(
                      color: future ? scheme.outlineVariant : isToday ? scheme.primary : scheme.outline,
                      width: isToday ? 2 : 1,
                    ),
                  ),
                  child: Text(letters[i],
                      style: TextStyle(
                        fontSize: size * 0.42,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: on ? scheme.onPrimary : future ? scheme.outlineVariant : scheme.onSurface,
                      )),
                ),
              ),
            ),
          );
        }),
      ]);
    });
  }
}
