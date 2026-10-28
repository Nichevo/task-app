import 'package:flutter/material.dart';

import '../models.dart';

/// Pick how a task repeats.
class RepeatDialog extends StatefulWidget {
  const RepeatDialog({super.key, this.initial});

  final Repeat? initial;

  @override
  State<RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<RepeatDialog> {
  late RepeatUnit unit = widget.initial?.unit ?? RepeatUnit.week;
  late int every = widget.initial?.every ?? 1;
  late final Set<int> weekdays = {...?widget.initial?.weekdays};
  late bool fromCompletion = widget.initial?.fromCompletion ?? false;

  static const _units = {
    RepeatUnit.day: 'day(s)',
    RepeatUnit.week: 'week(s)',
    RepeatUnit.month: 'month(s)',
    RepeatUnit.year: 'year(s)',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Repeat'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Every '),
            DropdownButton<int>(
              value: every,
              items: [for (var i = 1; i <= 30; i++) DropdownMenuItem(value: i, child: Text('$i'))],
              onChanged: (v) => setState(() => every = v ?? 1),
            ),
            const SizedBox(width: 8),
            DropdownButton<RepeatUnit>(
              value: unit,
              items: [for (final e in _units.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => unit = v ?? RepeatUnit.week),
            ),
          ]),
          if (unit == RepeatUnit.week && every == 1) ...[
            const SizedBox(height: 8),
            const Text('On (optional):'),
            Wrap(spacing: 4, children: [
              for (final (i, d) in ['M', 'T', 'W', 'T', 'F', 'S', 'S'].indexed)
                FilterChip(
                  label: Text(d),
                  selected: weekdays.contains(i + 1),
                  onSelected: (on) => setState(() => on ? weekdays.add(i + 1) : weekdays.remove(i + 1)),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          RadioGroup<bool>(
            groupValue: fromCompletion,
            onChanged: (v) => setState(() => fromCompletion = v ?? false),
            child: const Column(children: [
              RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: false,
                title: Text('On a fixed schedule'),
                subtitle: Text('Next due date counts from the last due date'),
              ),
              RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: true,
                title: Text('After I tick it off'),
                subtitle: Text('Next due date counts from when it was done'),
              ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            Repeat(
              unit: unit,
              every: every,
              weekdays: unit == RepeatUnit.week && every == 1 ? weekdays : const {},
              fromCompletion: fromCompletion,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
