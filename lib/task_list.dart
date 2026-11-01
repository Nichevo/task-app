import 'models.dart';
import 'widgets/task_colors.dart';

/// The chips above the main list. Remembered on each device.
enum QuickFilter {
  all('All'),
  today('Today'),
  week('Next 7 days'),
  twoWeeks('Next 2 weeks'),
  month('Next 30 days'),
  overdue('Overdue'),
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
    QuickFilter.starred => t.starred,
    QuickFilter.noDate => due == null,
    _ => true,
  };
}

/// Whether [t] matches what was typed in the search box: every word must appear somewhere in
/// its name, notes or checklist, ignoring case.
bool matchesSearch(Task t, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final text = [t.title, t.notes, for (final s in t.steps) s.title].join('\n').toLowerCase();
  return words.every(text.contains);
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
