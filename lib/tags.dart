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
bool passesTagFilter(Task t, Set<String> filter) {
  if (filter.isEmpty) return true;
  if (filter.contains(untaggedFilter) && t.tags.isEmpty) return true;
  if (t.tags.isEmpty) return false;
  final keys = {
    for (final f in filter)
      if (f != untaggedFilter) tagKey(f),
  };
  return t.tags.any((x) => keys.contains(tagKey(x)));
}

/// Every tag in use on open and ticked-off tasks, A to Z, with how many open tasks have it.
List<({String tag, int open, int all})> tagsInUse(AppData data) {
  final spelling = <String, String>{};
  final open = <String, int>{};
  final all = <String, int>{};
  for (final t in data.active) {
    for (final x in t.tags) {
      final k = tagKey(x);
      spelling.putIfAbsent(k, () => x);
      open[k] = (open[k] ?? 0) + 1;
      all[k] = (all[k] ?? 0) + 1;
    }
  }
  for (final t in data.archived) {
    for (final x in t.tags) {
      final k = tagKey(x);
      spelling.putIfAbsent(k, () => x);
      all[k] = (all[k] ?? 0) + 1;
    }
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
    for (final x in t.tags) {
      if (tagKey(x) == k) return x;
    }
  }
  return clean;
}

/// "#meeting #coding" for a short line.
String tagLine(Iterable<String> tags) => tags.map((t) => '#$t').join(' ');
