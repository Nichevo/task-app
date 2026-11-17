import 'models.dart';

/// Item 107: free-form tags on tasks ("meeting", "brainstorming", "coding").
///
/// Tags are kept as typed (without the "#") but compared without case, so "Coding" and
/// "coding" are one tag; a new tag that matches an old one takes the old spelling.

/// "#Deep work " -> "Deep work"; empty when nothing is left.
String cleanTag(String raw) => raw.trim().replaceFirst(_hashes, '').replaceAll(_spaces, ' ').trim();

final _hashes = RegExp(r'^#+'), _spaces = RegExp(r'\s+');

/// The key two tags are compared by.
String tagKey(String tag) => cleanTag(tag).toLowerCase();

/// Whether [t] has [tag] (any case).
bool hasTag(Task t, String tag) {
  final k = tagKey(tag);
  return t.tags.any((x) => tagKey(x) == k);
}

/// The value the tag filter uses for "tasks with no tag".
const untaggedFilter = '';

/// Whether [t] passes the tag filter: an empty filter lets everything through; otherwise the
/// task needs at least one of the picked tags ([untaggedFilter] picks tasks with none).
/// Item 112: an open step with a picked tag lets its task through too.
bool passesTagFilter(Task t, Set<String> filter) {
  if (filter.isEmpty) return true;
  if (filter.contains(untaggedFilter) && t.tags.isEmpty) return true;
  final keys = _filterKeys(filter);
  if (keys.isEmpty) return false;
  if (t.tags.any((x) => keys.contains(tagKey(x)))) return true;
  return t.steps.any((st) => !st.done && st.tags.any((x) => keys.contains(tagKey(x))));
}

/// Item 112: whether step [st] of [t] passes the tag filter. A step counts as having its own
/// tags and its task's, so a step of a "coding" task shows under #coding; "No tag" picks steps
/// with no tag of their own in a task with none.
bool stepPassesTagFilter(Task t, TaskStep st, Set<String> filter) {
  if (filter.isEmpty) return true;
  if (filter.contains(untaggedFilter) && t.tags.isEmpty && st.tags.isEmpty) return true;
  final keys = _filterKeys(filter);
  return keys.isNotEmpty && [...t.tags, ...st.tags].any((x) => keys.contains(tagKey(x)));
}

Set<String> _filterKeys(Set<String> filter) => {
      for (final f in filter)
        if (f != untaggedFilter) tagKey(f),
    };

/// Item 112: whether step [st] has [tag] (any case).
bool stepHasTag(TaskStep st, String tag) {
  final k = tagKey(tag);
  return st.tags.any((x) => tagKey(x) == k);
}

/// Item 112: the tags typed as "#word" in a new step's name, taken out of it. Plain numbers
/// ("#2") stay in the name; a tag already in use keeps its spelling. When nothing but tags was
/// typed the name stays as typed.
({String title, List<String> tags}) takeStepTags(AppData data, String text) {
  final known = {for (final x in tagsInUse(data)) tagKey(x.tag): x.tag};
  final tags = <String>[];
  final title = text.replaceAllMapped(RegExp(r'(^|\s)#([\w-]+)(?=\s|$)'), (m) {
    final word = m.group(2)!;
    if (RegExp(r'^\d+$').hasMatch(word)) return m.group(0)!;
    final k = word.toLowerCase();
    if (!tags.any((x) => tagKey(x) == k)) tags.add(known[k] ?? word);
    return m.group(1)!;
  }).replaceAll(RegExp(r'\s+'), ' ').trim();
  return title.isEmpty ? (title: text.trim(), tags: const <String>[]) : (title: title, tags: tags);
}

/// Every tag in use on open and ticked-off tasks and their steps, A to Z, with how many open
/// tasks have it (on the task or one of its open steps).
List<({String tag, int open, int all})> tagsInUse(AppData data) {
  final spelling = <String, String>{};
  final open = <String, int>{};
  final all = <String, int>{};
  void count(Task t, bool isOpen) {
    final keys = <String>{}, openKeys = <String>{};
    void see(String x, bool live) {
      final k = tagKey(x);
      spelling.putIfAbsent(k, () => x);
      if (keys.add(k)) all[k] = (all[k] ?? 0) + 1;
      if (isOpen && live && openKeys.add(k)) open[k] = (open[k] ?? 0) + 1;
    }

    for (final x in t.tags) {
      see(x, true);
    }
    for (final st in t.steps) {
      for (final x in st.tags) {
        see(x, !st.done);
      }
    }
  }

  for (final t in data.active) {
    count(t, true);
  }
  for (final t in data.archived) {
    count(t, false);
  }
  final keys = spelling.keys.toList()..sort();
  return [for (final k in keys) (tag: spelling[k]!, open: open[k] ?? 0, all: all[k] ?? 0)];
}

/// [raw] as a tag, in the spelling already used if there is one; null if empty.
String? tagSpelling(AppData data, String raw) {
  final clean = cleanTag(raw);
  if (clean.isEmpty) return null;
  final k = clean.toLowerCase();
  for (final t in data.allTasks) {
    for (final x in [...t.tags, for (final st in t.steps) ...st.tags]) {
      if (tagKey(x) == k) return x;
    }
  }
  return clean;
}

/// "#meeting #coding" for a short line.
String tagLine(Iterable<String> tags) => tags.map((t) => '#$t').join(' ');
