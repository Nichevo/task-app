import 'package:intl/intl.dart';

import 'models.dart';

final _fmt = DateFormat('yyyy-MM-dd HH:mm');

String _cell(String s) =>
    RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

String _date(DateTime? d) => d == null ? '' : _fmt.format(d);

/// All tasks, active (in list order) then archived, with every field.
String buildCsv(AppData data) {
  final rows = <List<String>>[
    ['Status', 'Position', 'Task', 'Notes', 'Created', 'Due', 'Closed'],
    for (final (i, t) in data.active.indexed)
      ['Open', '${i + 1}', t.title, t.notes, _date(t.createdAt), _date(t.dueAt), ''],
    for (final t in data.archived)
      ['Closed', '', t.title, t.notes, _date(t.createdAt), _date(t.dueAt), _date(t.closedAt)],
  ];
  return '${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}
