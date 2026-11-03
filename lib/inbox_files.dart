import 'dart:convert';

import 'input_parse.dart';
import 'models.dart';

/// Item 48A: reads one file from the Dropbox `inbox/` folder (format in docs/PUSH_TASKS.md)
/// and adds its tasks to [data]. A file holds one task object or a list of them; only `title`
/// is required. Tasks whose `source` + `ref` the app already has are skipped. Returns the tasks
/// added; throws [FormatException] for a file that isn't a task file.
List<Task> addInboxFile(AppData data, String text, DateTime now) {
  final decoded = jsonDecode(text);
  final items = decoded is List ? decoded : [decoded];
  final known = {
    for (final t in data.allTasks)
      if (t.sourceRef != null) '${t.source}|${t.sourceRef}',
  };
  // Check the whole file first, so a bad entry doesn't leave half of it added.
  for (final item in items) {
    if (item is! Map) throw const FormatException('Each task must be a JSON object');
    if ((item['title'] ?? '').toString().trim().isEmpty) throw const FormatException('A task has no "title"');
    if (item['steps'] != null && item['steps'] is! List) throw const FormatException('"steps" must be a list');
  }
  final added = <Task>[];
  for (final item in items.cast<Map>()) {
    final title = item['title'].toString().trim();
    final source = _sourceName(item['source']);
    final ref = item['ref']?.toString().trim();
    if (ref != null && ref.isNotEmpty && !known.add('$source|$ref')) continue;

    final parsed = parseInput(title, data, now);
    final due = _due(item['due']) ?? parsed.due;
    var notes = (item['notes'] ?? '').toString().trim();
    final url = item['url']?.toString().trim();
    if (url != null && url.isNotEmpty) notes = notes.isEmpty ? url : '$notes\n$url';

    String? categoryId = parsed.categoryId;
    final catName = item['category']?.toString().trim();
    if (catName != null && catName.isNotEmpty) {
      var cat = data.categories.where((c) => c.name.toLowerCase() == catName.toLowerCase()).firstOrNull;
      if (cat == null) {
        cat = TaskCategory.create(catName);
        data.categories.add(cat);
        data.settingsUpdatedAt = now.toUtc();
      }
      categoryId = cat.id;
    }

    final t = Task.create(item['due'] != null ? title : parsed.title, source: source)
      ..notes = notes
      ..dueAt = due
      ..categoryId = categoryId
      ..starred = item['starred'] == true
      ..sourceRef = ref == null || ref.isEmpty ? null : ref;
    for (final st in item['steps'] as List? ?? const []) {
      final name = st.toString().trim();
      if (name.isNotEmpty) t.steps.add(TaskStep.create(name));
    }
    data.active.add(t);
    added.add(t);
  }
  if (added.isNotEmpty) data.updatedAt = data.orderUpdatedAt = now.toUtc();
  return added;
}

/// A tool's name as a source: short and lower case; `inbox` when missing.
String _sourceName(Object? v) {
  final s = v?.toString().trim().toLowerCase() ?? '';
  if (s.isEmpty) return TaskSource.inbox;
  return s.length > 40 ? s.substring(0, 40) : s;
}

/// An ISO date or date-time; a plain date means 9am that day.
DateTime? _due(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  final s = v.trim();
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return DateTime(d.year, d.month, d.day, 9);
  return d.toLocal();
}

/// An example file for Settings, to copy into a tool.
const inboxExample = '''{
  "title": "Renew car insurance",
  "notes": "Quote from the broker",
  "due": "2026-11-20T09:00:00Z",
  "category": "Admin",
  "steps": ["Get quotes", "Pay"],
  "source": "zapier",
  "ref": "zap-7731-msg-1842"
}''';
