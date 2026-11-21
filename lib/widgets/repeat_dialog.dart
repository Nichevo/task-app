import 'package:flutter/material.dart';

import '../models.dart';

/// Pick how a task repeats.
class RepeatDialog extends StatefulWidget {
  const RepeatDialog({super.key, this.initial, this.due});

  final Repeat? initial;

  /// The task's due date, for "the 19th" or "the third Friday" (item 114 F).
  final DateTime? due;

  @override
  State<RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends State<RepeatDialog> {
  late RepeatUnit unit = widget.initial?.unit ?? RepeatUnit.week;
  late int every = widget.initial?.every ?? 1;
  late final Set<int> weekdays = {...?widget.initial?.weekdays};
  late bool fromCompletion = widget.initial?.fromCompletion ?? false;

  // Item 114 F: which day of the month, weekends, and when it ends.
  late String monthly = widget.initial?.lastWorkday ?? false
      ? 'lastWorkday'
      : widget.initial?.nth != null
          ? 'nth'
          : 'date';
  late bool skipWeekends = widget.initial?.skipWeekends ?? false;
  late String ends = widget.initial?.until != null
      ? 'until'
      : widget.initial?.left != null
          ? 'times'
          : 'never';
  late DateTime until = widget.initial?.until ?? DateTime.now().add(const Duration(days: 182));
  late int times = (widget.initial?.left ?? 9) + 1;

  DateTime get _due => widget.due ?? DateTime.now();

  /// The due date's place in its month: 1 to 4, or -1 when it is the last such weekday.
  int get _nth {
    final d = _due;
    if (widget.initial?.nth != null && widget.due == null) return widget.initial!.nth!;
    final last = DateTime(d.year, d.month + 1, 0).day;
    if (d.day + 7 > last) return -1;
    return (d.day - 1) ~/ 7 + 1;
  }

  int get _nthDay => widget.due == null ? widget.initial?.nthWeekday ?? _due.weekday : _due.weekday;

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  String _ordinal(int n) => '$n${n % 100 >= 11 && n % 100 <= 13 ? 'th' : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' }}';

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
          if (unit == RepeatUnit.week) ...[
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
          if (unit == RepeatUnit.month) ...[
            const SizedBox(height: 8),
            const Text('On'),
            RadioGroup<String>(
              groupValue: monthly,
              onChanged: (v) => setState(() => monthly = v ?? 'date'),
              child: Column(children: [
                RadioListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: 'date',
                  title: Text('The ${_ordinal(_due.day)} of each month'),
                ),
                RadioListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: 'nth',
                  title: Text('The ${Repeat.nthName(_nth)} ${_days[_nthDay - 1]}'),
                ),
                const RadioListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: 'lastWorkday',
                  title: Text('The last working day'),
                ),
              ]),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Skip weekends'),
            subtitle: const Text('A date on Saturday or Sunday moves to the Monday'),
            value: skipWeekends,
            onChanged: (v) => setState(() => skipWeekends = v),
          ),
          const SizedBox(height: 4),
          const Text('Ends'),
          Wrap(spacing: 6, children: [
            ChoiceChip(label: const Text('Never'), selected: ends == 'never', onSelected: (_) => setState(() => ends = 'never')),
            ChoiceChip(
              label: Text(ends == 'until' ? 'On ${until.day}/${until.month}/${until.year}' : 'On a date'),
              selected: ends == 'until',
              onSelected: (_) async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: until,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                );
                if (d != null) {
                  setState(() {
                    until = d;
                    ends = 'until';
                  });
                }
              },
            ),
            ChoiceChip(
              label: Text(ends == 'times' ? 'After $times times' : 'After N times'),
              selected: ends == 'times',
              onSelected: (_) => setState(() => ends = 'times'),
            ),
          ]),
          if (ends == 'times')
            Row(children: [
              const Text('Times, counting this one: '),
              DropdownButton<int>(
                value: times.clamp(1, 60),
                items: [for (var i = 1; i <= 60; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                onChanged: (v) => setState(() => times = v ?? 10),
              ),
            ]),
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
              weekdays: unit == RepeatUnit.week ? weekdays : const {},
              fromCompletion: fromCompletion,
              nth: unit == RepeatUnit.month && monthly == 'nth' ? _nth : null,
              nthWeekday: unit == RepeatUnit.month && monthly == 'nth' ? _nthDay : null,
              lastWorkday: unit == RepeatUnit.month && monthly == 'lastWorkday',
              skipWeekends: skipWeekends,
              until: ends == 'until' ? until : null,
              left: ends == 'times' ? times - 1 : null,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
