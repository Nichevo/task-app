import 'package:intl/intl.dart';

import 'models.dart';

final csvDateFormat = DateFormat('yyyy-MM-dd HH:mm');

const csvHeader = ['Status', 'Position', 'Task', 'Notes', 'Category', 'Created', 'Due', 'Closed', 'Starred', 'Repeats', 'Steps', 'Source', 'Estimate (min)', 'Stage', 'Emails', 'Matrix box', 'Waiting on', 'Gantt', 'Start', 'Takes (days)', 'Count weekends', 'Milestone', 'Progress (%)', 'Comes after'];

String _cell(String s) =>
    RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

String _date(DateTime? d) => d == null ? '' : csvDateFormat.format(d);

String? _title(AppData data, String id) =>
    (data.task(id) ?? data.archived.where((t) => t.id == id).firstOrNull)?.title;

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
        t.steps
            .map((s) => '${s.done ? '[x]' : '[ ]'} ${s.title}${s.dueAt == null ? '' : ' (due ${_date(s.dueAt)})'}')
            .join('; '),
        t.source == null ? '' : TaskSource.label(t.source),
        t.estimate?.toString() ?? '',
        t.kanban ? data.stage(t.stageId)?.name ?? '' : '',
        t.emails.isEmpty ? '' : '${t.emails.length}',
        MatrixBox.byId(t.matrixBox) == null ? '' : data.boxName(MatrixBox.byId(t.matrixBox)!),
        t.waitingOn ?? '',
        t.gantt ? 'Yes' : '',
        _date(t.startAt),
        t.takesDays?.toString() ?? '',
        t.countWeekends == null ? '' : (t.countWeekends! ? 'Yes' : 'No'),
        t.milestone ? 'Yes' : '',
        t.progress?.toString() ?? '',
        [for (final id in t.afterIds) ?_title(data, id)].join('; '),
      ];
  final rows = <List<String>>[
    csvHeader,
    for (final (i, t) in data.active.indexed) row(t, 'Open', '${i + 1}'),
    for (final t in data.archived) row(t, 'Closed', ''),
  ];
  return '${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}

const emailsHeader = ['Task', 'Task created', 'Email id', 'Thread id', 'Subject', 'From', 'Date', 'Snippet'];

/// emails.csv (item 55/63): one row per email kept on a task. Null when no task has one.
String? buildEmailsCsv(AppData data) {
  final rows = [
    for (final t in data.allTasks)
      for (final e in t.emails)
        [t.title, _date(t.createdAt), e.id, e.threadId ?? '', e.subject, e.from, _date(e.date), e.snippet],
  ];
  if (rows.isEmpty) return null;
  final lines = [emailsHeader, ...rows];
  return '${lines.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}

const movesHeader = ['Task', 'Step', 'Moved from', 'Moved to', 'When', 'Minutes in previous stage', 'How', 'Where', 'Device', 'Note'];

/// kanban_moves.csv: one row per board move of every task, oldest first. Null when nothing
/// has been on the board.
String? buildMovesCsv(AppData data) {
  final rows = <(DateTime, List<String>)>[];
  void add(Task t, TaskStep? step, List<StageMove> moves) {
    DateTime? previous;
    for (final m in moves) {
      rows.add((
        m.at,
        [
          t.title,
          step?.title ?? '',
          m.fromName ?? '',
          m.toName ?? '',
          _date(m.at),
          previous == null || m.fromId == null ? '' : '${m.at.difference(previous).inMinutes}',
          MoveHow.label(m.how),
          m.where?.toString() ?? '',
          m.device ?? '',
          m.note ?? '',
        ]
      ));
      previous = m.at;
    }
  }

  for (final t in data.allTasks) {
    add(t, null, t.moves);
    // Item 56: checklist steps' own moves.
    for (final st in t.steps) {
      add(t, st, st.moves);
    }
  }
  if (rows.isEmpty) return null;
  rows.sort((a, b) => a.$1.compareTo(b.$1));
  final lines = [movesHeader, for (final r in rows) r.$2];
  return '${lines.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}
