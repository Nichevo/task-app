import 'package:intl/intl.dart';

import 'models.dart';

final csvDateFormat = DateFormat('yyyy-MM-dd HH:mm');

const csvHeader = ['Status', 'Position', 'Task', 'Notes', 'Category', 'Created', 'Due', 'Closed', 'Starred', 'Repeats'];

String _cell(String s) =>
    RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

String _date(DateTime? d) => d == null ? '' : csvDateFormat.format(d);

/// All tasks, active (in list order) then archived, with every field.
String buildCsv(AppData data) {
  List<String> row(Task t, String status, String position) => [
        status,
        position,
        t.title,
        t.notes,
        data.category(t.categoryId)?.name ?? '',
        _date(t.createdAt),
        _date(t.dueAt),
        _date(t.closedAt),
        t.starred ? 'Yes' : '',
        t.repeat?.describe() ?? '',
      ];
  final rows = <List<String>>[
    csvHeader,
    for (final (i, t) in data.active.indexed) row(t, 'Open', '${i + 1}'),
    for (final t in data.archived) row(t, 'Closed', ''),
  ];
  return '${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}
