import 'package:flutter/material.dart';

import '../gantt.dart';
import '../models.dart';

/// 1.12.10: how long a task or step takes, in days or hours. Hours become the working days they
/// fill on the Gantt chart (a working day is the Day plan's working hours).
typedef Takes = ({int days, int? minutes});

/// Reads "3", "3d", "2 days", "6h", "1.5 h", "90m" or "1h30". [hours] says what a bare number
/// means. Null when it can't be read or is not more than nothing.
Takes? parseTakes(String text, AppData data, {required bool hours}) {
  final t = text.trim().toLowerCase().replaceAll(',', '.');
  final hm = RegExp(r'^(\d+)\s*h(?:ours?|rs?)?\s*(\d+)\s*m?(?:in(?:ute)?s?)?$').firstMatch(t);
  int? minutes;
  if (hm != null) {
    minutes = int.parse(hm.group(1)!) * 60 + int.parse(hm.group(2)!);
  } else {
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-z]*)$').firstMatch(t);
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    final unit = m.group(2)!;
    if (unit.startsWith('d') || (unit.isEmpty && !hours)) {
      final days = n.ceil();
      return days < 1 ? null : (days: days, minutes: null);
    }
    if (unit.startsWith('h') || unit.isEmpty) {
      minutes = (n * 60).round();
    } else if (unit.startsWith('m')) {
      minutes = n.round();
    } else {
      return null;
    }
  }
  if (minutes <= 0) return null;
  return (days: daysForMinutes(minutes, data), minutes: minutes);
}

/// Asks how long it takes. Returns null on Cancel, and days 0 for Clear.
Future<Takes?> askTakes(BuildContext context, AppData data,
    {required String title, int? days, int? minutes, bool canClear = true}) {
  final given = takesHours(days, minutes, data);
  var hours = given != null;
  String show(int m) {
    final h = m / 60;
    return h == h.roundToDouble() ? '${h.round()}' : h.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');
  }

  final text = TextEditingController(text: given != null ? show(given) : days?.toString() ?? '');
  final day = workdayMinutes(data);
  return showDialog<Takes>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final read = parseTakes(text.text, data, hours: hours);
      return AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Days')),
              ButtonSegment(value: true, label: Text('Hours')),
            ],
            selected: {hours},
            onSelectionChanged: (v) => set(() => hours = v.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: hours ? 'Hours' : 'Days',
              hintText: hours ? 'e.g. 6 or 1.5' : 'e.g. 3',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => set(() {}),
            onSubmitted: (_) {
              if (read != null) Navigator.pop(c, read);
            },
          ),
          const SizedBox(height: 8),
          Text(
            hours
                ? 'On the Gantt chart: ${read == null ? '–' : '${read.days} day${read.days == 1 ? '' : 's'}'}. '
                    'A working day is ${day % 60 == 0 ? '${day ~/ 60} h' : '${(day / 60).toStringAsFixed(1)} h'} '
                    '(the Day plan\'s working hours).'
                : 'Type "6h" to give it in hours instead.',
            style: Theme.of(c).textTheme.bodySmall,
          ),
        ]),
        actions: [
          if (canClear && days != null) TextButton(onPressed: () => Navigator.pop(c, (days: 0, minutes: null)), child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: read == null ? null : () => Navigator.pop(c, read), child: const Text('OK')),
        ],
      );
    }),
  );
}
