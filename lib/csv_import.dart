import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'csv_export.dart';
import 'models.dart';
import 'store.dart';

/// Splits CSV text into rows of cells, handling quotes, commas and line breaks in cells.
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((x) => x.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  row.add(cell.toString());
  if (row.any((x) => x.isNotEmpty)) rows.add(row);
  return rows;
}

final _dateFormats = [
  csvDateFormat,
  DateFormat('d/M/yyyy H:mm'),
  DateFormat('d/M/yyyy'),
  DateFormat('yyyy-MM-dd'),
];

DateTime? _parseDate(String s) {
  s = s.trim();
  if (s.isEmpty) return null;
  for (final f in _dateFormats) {
    try {
      return f.parseStrict(s);
    } catch (_) {}
  }
  return DateTime.tryParse(s);
}

/// A Source cell from an exported file back to its name; anything else counts as a CSV import.
String _source(String cell) {
  if (cell.isEmpty) return TaskSource.csv;
  for (final e in TaskSource.labels.entries) {
    if (e.value.toLowerCase() == cell.toLowerCase() || e.key == cell.toLowerCase()) return e.key;
  }
  return cell.toLowerCase();
}

/// Adds the tasks in [text] (same columns as the export; only "Task" is required) to [data].
/// Categories are matched by name and created if missing. Tasks already in the app (same name
/// and created time) are skipped. Returns how many were added.
int importCsvText(AppData data, String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return 0;
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  int col(String name) => header.indexOf(name);
  final iTask = col('task'), iNotes = col('notes'), iCat = col('category'), iCreated = col('created');
  final iDue = col('due'), iClosed = col('closed'), iStatus = col('status'), iStar = col('starred');
  final iSteps = col('steps'), iSource = col('source'), iEst = col('estimate (min)');
  final iBox = col('matrix box'), iWaiting = col('waiting on');
  if (iTask < 0) throw const FormatException('The file needs a "Task" column.');
  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';

  final existing = {for (final t in [...data.active, ...data.archived]) '${t.title}|${t.createdAt}'};
  var added = 0;
  for (final r in rows.skip(1)) {
    final title = cell(r, iTask);
    if (title.isEmpty) continue;
    final created = _parseDate(cell(r, iCreated)) ?? DateTime.now();
    if (!existing.add('$title|$created')) continue;
    final catName = cell(r, iCat);
    TaskCategory? cat;
    if (catName.isNotEmpty) {
      cat = data.categories.where((c) => c.name.toLowerCase() == catName.toLowerCase()).firstOrNull;
      if (cat == null) {
        cat = TaskCategory.create(catName);
        data.categories.add(cat);
        data.settingsUpdatedAt = DateTime.now().toUtc();
      }
    }
    final closed = _parseDate(cell(r, iClosed)) ??
        (cell(r, iStatus).toLowerCase() == 'closed' ? DateTime.now() : null);
    final t = Task.create(title, source: _source(cell(r, iSource)))
      ..notes = cell(r, iNotes)
      ..dueAt = _parseDate(cell(r, iDue))
      ..closedAt = closed
      ..categoryId = cat?.id
      ..starred = const {'yes', 'true', '1', 'y'}.contains(cell(r, iStar).toLowerCase())
      ..estimate = int.tryParse(cell(r, iEst))
      ..matrixBox = _box(data, cell(r, iBox))?.id
      ..waitingOn = cell(r, iWaiting).isEmpty ? null : cell(r, iWaiting);
    for (final part in cell(r, iSteps).split(';')) {
      final m = RegExp(r'^\s*(?:\[([ xX])\])?\s*(.+?)\s*$').firstMatch(part);
      if (m == null || m.group(2)!.isEmpty) continue;
      // Item 61: "Book hall (due 2026-11-20 09:00)" keeps the step's date.
      var name = m.group(2)!;
      DateTime? due;
      final d = RegExp(r'\s*\(due ([^)]+)\)$').firstMatch(name);
      if (d != null && _parseDate(d.group(1)!) != null) {
        due = _parseDate(d.group(1)!);
        name = name.substring(0, d.start);
      }
      t.steps.add(TaskStep.create(name)
        ..done = (m.group(1) ?? ' ').toLowerCase() == 'x'
        ..dueAt = due);
    }
    final task = Task.fromJson({...t.toJson(), 'createdAt': created.toIso8601String()});
    if (closed == null) {
      data.active.add(task);
    } else {
      data.archived.add(task);
    }
    added++;
  }
  data.archived.sort((x, y) => y.closedAt!.compareTo(x.closedAt!));
  return added;
}

/// A matrix box from its name (as renamed here, or the standard one).
MatrixBox? _box(AppData data, String name) {
  final n = name.toLowerCase();
  if (n.isEmpty) return null;
  return MatrixBox.values
      .where((b) => data.boxName(b).toLowerCase() == n || b.label.toLowerCase() == n || b.id == n)
      .firstOrNull;
}

/// Whether [text] is an emails.csv from the export (item 63) rather than a list of tasks.
bool isEmailsCsv(String text) {
  final rows = parseCsv(text);
  return rows.isNotEmpty && rows.first.any((h) => h.trim().toLowerCase() == 'email id');
}

/// Puts the emails in an emails.csv back on their tasks (matched by name and created time).
/// Emails a task already has are skipped. Returns how many were added.
int importEmailsCsvText(AppData data, String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return 0;
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  int col(String name) => header.indexOf(name);
  final iTask = col('task'), iCreated = col('task created'), iId = col('email id'), iThread = col('thread id');
  final iSubject = col('subject'), iFrom = col('from'), iDate = col('date'), iSnippet = col('snippet');
  String cell(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : '';
  final byKey = <String, Task>{for (final t in data.allTasks) '${t.title}|${_parseDate(csvDateFormat.format(t.createdAt))}': t};
  var added = 0;
  for (final r in rows.skip(1)) {
    final id = cell(r, iId);
    final t = byKey['${cell(r, iTask)}|${_parseDate(cell(r, iCreated))}'];
    if (id.isEmpty || t == null || t.emails.any((e) => e.id == id)) continue;
    t.emails.add(TaskEmail(
      id: id,
      threadId: cell(r, iThread).isEmpty ? null : cell(r, iThread),
      subject: cell(r, iSubject),
      from: cell(r, iFrom),
      date: _parseDate(cell(r, iDate)),
      snippet: cell(r, iSnippet),
    ));
    t.touch();
    added++;
  }
  return added;
}

Future<void> importCsv(BuildContext context, AppStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Import tasks',
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    if (isEmailsCsv(text)) {
      final added = importEmailsCsvText(store.data, text);
      store.changed();
      messenger.showSnackBar(SnackBar(content: Text('Put back $added email${added == 1 ? '' : 's'} on their tasks')));
      return;
    }
    final added = importCsvText(store.data, text);
    store.changed(order: true);
    messenger.showSnackBar(SnackBar(content: Text('Imported $added task${added == 1 ? '' : 's'}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}
