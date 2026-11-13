import 'models.dart';
import 'pace.dart';
import 'widgets/task_colors.dart';

/// The chips above the main list. Remembered on each device.
enum QuickFilter {
  all('All'),
  today('Today'),
  week('Next 7 days'),
  twoWeeks('Next 2 weeks'),
  month('Next 30 days'),
  overdue('Overdue'),
  behind('Behind'),
  starred('Starred'),
  noDate('No date');

  const QuickFilter(this.label);
  final String label;

  /// Days ahead for the date chips (0 = to the end of today); null for the others.
  int? get days => switch (this) {
        today => 0,
        week => 7,
        twoWeeks => 14,
        month => 30,
        _ => null,
      };
}

/// Names shown in Settings for each sort.
const sortLabels = {
  ListSort.manual: 'Hand-made order (drag)',
  ListSort.due: 'Due date',
  ListSort.age: 'Colour age (reddest first)',
  ListSort.newest: 'Newest first',
  ListSort.categoryDue: 'Category, then due date',
};

/// Whether [t] passes the chip. Overdue tasks always show under the date chips.
bool passesFilter(Task t, QuickFilter f, DateTime now) {
  final due = t.dueAt;
  final days = f.days;
  if (days != null) {
    if (due == null) return false;
    final end = DateTime(now.year, now.month, now.day + days + 1);
    return due.isBefore(end);
  }
  return switch (f) {
    QuickFilter.overdue => due != null && due.isBefore(now),
    // Item 96: overdue, or less done than the time gone says it should be.
    QuickFilter.behind => taskPace(t, now).verdict == Pace.behind,
    QuickFilter.starred => t.starred,
    QuickFilter.noDate => due == null,
    _ => true,
  };
}

/// Whether [t] matches what was typed in the search box: every word must appear somewhere in
/// its name, notes or checklist, ignoring case.
bool matchesSearch(Task t, String query, [AppData? data]) {
  final terms = searchTerms(query);
  if (terms.isEmpty) return true;
  final text = foldText(searchText(t, data));
  return terms.every(text.contains);
}

/// Item 65: the words of a search, lower case without accents. "Quoted phrases" stay whole.
List<String> searchTerms(String query) {
  final out = <String>[];
  for (final m in RegExp(r'"([^"]*)"|(\S+)').allMatches(query)) {
    final w = foldText((m.group(1) ?? m.group(2) ?? '').trim());
    if (w.isNotEmpty && w != '"') out.add(w);
  }
  return out;
}

/// Everything about a task that search looks in: title, notes, steps, category, waiting on,
/// place, and its emails (subject, sender, snippet).
String searchText(Task t, [AppData? data]) => [
      t.title,
      t.notes,
      for (final s in t.steps) s.title,
      if (data?.category(t.categoryId) case final c?) c.name,
      t.waitingOn ?? '',
      t.place ?? '',
      for (final e in t.emails) ...[e.subject, e.from, e.snippet],
    ].join('\n');

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', 'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'œ': 'oe',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
  '\u2018': "'", '\u2019': "'", '\u201c': '"', '\u201d': '"',
};

/// Lower case with common accents taken off, so "cafe" finds "Café". Each character maps to
/// one or more, so use [foldMap] to find where a match sits in the original text.
String foldText(String s) {
  final lower = s.toLowerCase();
  if (!lower.runes.any((r) => r > 127)) return lower;
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

/// Where each search term sits in [text], as (start, end) ranges of the original text, merged
/// and in order. Used to highlight matches.
List<(int, int)> matchRanges(String text, List<String> terms) {
  if (terms.isEmpty || text.isEmpty) return const [];
  // Folded text and a map from each folded character back to its original index.
  final folded = StringBuffer();
  final back = <int>[];
  final lower = text.toLowerCase();
  // toLowerCase can change length for a few characters; fall back to no highlight then.
  if (lower.length != text.length) return const [];
  for (var i = 0; i < lower.length; i++) {
    final f = _accents[lower[i]] ?? lower[i];
    folded.write(f);
    for (var k = 0; k < f.length; k++) {
      back.add(i);
    }
  }
  final fs = folded.toString();
  final raw = <(int, int)>[];
  for (final term in terms) {
    var at = fs.indexOf(term);
    while (at >= 0) {
      raw.add((back[at], back[at + term.length - 1] + 1));
      at = fs.indexOf(term, at + term.length);
    }
  }
  raw.sort((a, b) => a.$1.compareTo(b.$1));
  final out = <(int, int)>[];
  for (final r in raw) {
    if (out.isNotEmpty && r.$1 <= out.last.$2) {
      final last = out.removeLast();
      out.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      out.add(r);
    }
  }
  return out;
}

/// [tasks] in the order chosen in Settings. Sorting keeps the hand-made order between equals,
/// so it is stable and predictable.
List<Task> sortTasks(List<Task> tasks, AppData data, DateTime now) {
  final position = {for (final (i, t) in data.active.indexed) t.id: i};
  int byHand(Task a, Task b) => (position[a.id] ?? 1 << 30).compareTo(position[b.id] ?? 1 << 30);
  int byDue(Task a, Task b) {
    final x = a.dueAt, y = b.dueAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1; // no date last
    if (y == null) return -1;
    return x.compareTo(y);
  }

  final catOrder = {for (final (i, c) in data.categories.indexed) c.id: i};
  int catIndex(Task t) => catOrder[t.categoryId] ?? data.categories.length; // none last
  final redness = {for (final t in tasks) t.id: ageProgress(t, data.hoursToRed, byDue: data.colourByDue, now: now)};

  int compare(Task a, Task b) {
    final c = switch (data.sort) {
      ListSort.manual => 0,
      ListSort.due => byDue(a, b),
      ListSort.age => redness[b.id]!.compareTo(redness[a.id]!),
      ListSort.newest => b.createdAt.compareTo(a.createdAt),
      ListSort.categoryDue => catIndex(a) != catIndex(b) ? catIndex(a).compareTo(catIndex(b)) : byDue(a, b),
    };
    return c != 0 ? c : byHand(a, b);
  }

  final sorted = [...tasks]..sort(compare);
  if (!data.starredTop) return sorted;
  return [...sorted.where((t) => t.starred), ...sorted.where((t) => !t.starred)];
}

/// Total of the time estimates, e.g. "about 2 h 30 min"; null when none of [tasks] has one.
String? describeEstimates(Iterable<Task> tasks) {
  final withEst = tasks.where((t) => t.estimate != null).toList();
  if (withEst.isEmpty) return null;
  final total = withEst.fold<int>(0, (sum, t) => sum + t.estimate!);
  return describeMinutes(total);
}

/// "15 min", "1 h", "2 h 30 min", "1 day 3 h" (a day being 8 working hours is confusing, so
/// days are only used past 24 h).
String describeMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes < 24 * 60) {
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }
  final d = minutes ~/ (24 * 60), h = (minutes % (24 * 60)) / 60;
  return h == 0 ? '$d day${d == 1 ? '' : 's'}' : '$d day${d == 1 ? '' : 's'} ${h.round()} h';
}

/// Short form for the block: "15m", "1h", "1h30", "2d".
String shortMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  if (minutes < 24 * 60) {
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }
  return '${(minutes / (24 * 60)).round()}d';
}

/// Quick choices for a task's time estimate, in minutes.
const estimateOptions = [15, 30, 60, 120, 240, 480];

/// Reads "45", "45m", "1.5h", "2 h", "1h30" as minutes; null if it can't.
int? parseEstimate(String text) {
  final t = text.trim().toLowerCase().replaceAll(' ', '');
  if (t.isEmpty) return null;
  final hm = RegExp(r'^(\d+(?:\.\d+)?)h(?:(\d+)m?)?$').firstMatch(t);
  if (hm != null) {
    final m = (double.parse(hm.group(1)!) * 60).round() + int.parse(hm.group(2) ?? '0');
    return m > 0 ? m : null;
  }
  final d = RegExp(r'^(\d+(?:\.\d+)?)d$').firstMatch(t);
  if (d != null) return (double.parse(d.group(1)!) * 24 * 60).round();
  final m = RegExp(r'^(\d+)(?:m|min|mins)?$').firstMatch(t);
  final v = m == null ? null : int.parse(m.group(1)!);
  return v != null && v > 0 ? v : null;
}
