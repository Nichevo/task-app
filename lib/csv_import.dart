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
  final iSteps = col('steps');
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
    final t = Task.create(title)
      ..notes = cell(r, iNotes)
      ..dueAt = _parseDate(cell(r, iDue))
      ..closedAt = closed
      ..categoryId = cat?.id
      ..starred = const {'yes', 'true', '1', 'y'}.contains(cell(r, iStar).toLowerCase());
    for (final part in cell(r, iSteps).split(';')) {
      final m = RegExp(r'^\s*(?:\[([ xX])\])?\s*(.+?)\s*$').firstMatch(part);
      if (m == null || m.group(2)!.isEmpty) continue;
      t.steps.add(TaskStep.create(m.group(2)!)..done = (m.group(1) ?? ' ').toLowerCase() == 'x');
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
    final added = importCsvText(store.data, utf8.decode(bytes, allowMalformed: true));
    store.changed(order: true);
    messenger.showSnackBar(SnackBar(content: Text('Imported $added task${added == 1 ? '' : 's'}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
  }
}
