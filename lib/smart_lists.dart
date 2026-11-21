import 'dart:math';

import 'day_plan.dart' show planLength, describeLength;
import 'models.dart';
import 'pace.dart';
import 'tags.dart';

/// Item 114 (11): saved smart lists. A list is a named mix of filters (category, tag, matrix box,
/// starred, due within, length, behind, waiting, place) kept in [AppData.helperPrefs] so it syncs.
/// Picking one in the ☰ menu narrows the main list (and the board and matrix) until cleared.
class SmartList {
  SmartList({
    required this.id,
    required this.name,
    this.emoji = '📋',
    Set<String>? categoryIds,
    Set<String>? tags,
    this.box,
    this.starred = false,
    this.due,
    this.maxMinutes,
    this.behind = false,
    this.waiting,
    this.place,
    this.opens = 'list',
  })  : categoryIds = categoryIds ?? {},
        tags = tags ?? {};

  factory SmartList.create(String name) =>
      SmartList(id: 'l${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}', name: name.trim());

  final String id;
  String name;
  String emoji;

  /// Any of these categories ('' = no category). Empty = any.
  final Set<String> categoryIds;

  /// Any of these tags (as in the tag filter). Empty = any.
  final Set<String> tags;

  /// A matrix box id, or null for any.
  String? box;
  bool starred;

  /// When it's due: a [SmartDue] name, or null for any.
  String? due;

  /// Only tasks estimated at this many minutes or less.
  int? maxMinutes;

  /// Only tasks behind (overdue, or less done than the time gone says).
  bool behind;

  /// true = only waiting on someone, false = only not waiting, null = either.
  bool? waiting;

  /// The name of a saved place, or null for any.
  String? place;

  /// Where it opens from the ☰ menu: 'list', 'board' or 'matrix'.
  String opens;

  SmartList copy() => SmartList.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        if (categoryIds.isNotEmpty) 'categories': categoryIds.toList(),
        if (tags.isNotEmpty) 'tags': tags.toList(),
        if (box != null) 'box': box,
        if (starred) 'starred': true,
        if (due != null) 'due': due,
        if (maxMinutes != null) 'maxMinutes': maxMinutes,
        if (behind) 'behind': true,
        if (waiting != null) 'waiting': waiting,
        if (place != null) 'place': place,
        if (opens != 'list') 'opens': opens,
      };

  static SmartList? tryParse(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return SmartList.fromJson(j);
  }

  factory SmartList.fromJson(Map j) => SmartList(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'List',
        emoji: j['emoji'] as String? ?? '📋',
        categoryIds: {for (final x in j['categories'] as List? ?? []) ?x as String?},
        tags: {for (final x in j['tags'] as List? ?? []) ?x as String?},
        box: j['box'] as String?,
        starred: j['starred'] as bool? ?? false,
        due: j['due'] as String?,
        maxMinutes: (j['maxMinutes'] as num?)?.toInt(),
        behind: j['behind'] as bool? ?? false,
        waiting: j['waiting'] as bool?,
        place: j['place'] as String?,
        opens: j['opens'] as String? ?? 'list',
      );
}

/// The "due" choices of a smart list.
enum SmartDue {
  overdue('Overdue'),
  today('Today (and overdue)'),
  week('Within 7 days'),
  twoWeeks('Within 2 weeks'),
  month('Within 30 days'),
  noDate('No date');

  const SmartDue(this.label);
  final String label;

  static SmartDue? byName(String? n) => values.where((d) => d.name == n).firstOrNull;
}

/// The lengths offered for "takes at most".
const smartLengths = [15, 30, 60, 120];

extension SmartListPrefs on AppData {
  /// The saved lists, in order.
  List<SmartList> get smartLists => [for (final j in helperPrefs['smartLists'] as List? ?? const []) ?SmartList.tryParse(j)];
  set smartLists(List<SmartList> v) => helperPrefs['smartLists'] = [for (final l in v) l.toJson()];

  SmartList? smartList(String? id) => id == null ? null : smartLists.where((l) => l.id == id).firstOrNull;
}

/// Whether [t] is on list [l].
bool passesSmartList(Task t, SmartList l, AppData data, DateTime now) {
  if (l.categoryIds.isNotEmpty) {
    final known = t.categoryId != null && data.category(t.categoryId) != null;
    if (!l.categoryIds.contains(known ? t.categoryId : '')) return false;
  }
  if (l.tags.isNotEmpty && !passesTagFilter(t, l.tags)) return false;
  if (l.box != null && t.matrixBox != l.box) return false;
  if (l.starred && !t.starred) return false;
  if (l.waiting != null && (t.waitingOn?.trim().isNotEmpty ?? false) != l.waiting) return false;
  if (l.place != null && t.place != l.place) return false;
  if (l.behind && taskPace(t, now).verdict != Pace.behind) return false;
  if (l.maxMinutes != null && planLength(data, t) > l.maxMinutes!) return false;
  final due = t.dueAt;
  final today = DateTime(now.year, now.month, now.day);
  DateTime end(int days) => today.add(Duration(days: days + 1));
  return switch (SmartDue.byName(l.due)) {
    null => true,
    SmartDue.overdue => due != null && due.isBefore(now),
    SmartDue.today => due != null && due.isBefore(end(0)),
    SmartDue.week => due != null && due.isBefore(end(7)),
    SmartDue.twoWeeks => due != null && due.isBefore(end(14)),
    SmartDue.month => due != null && due.isBefore(end(30)),
    SmartDue.noDate => due == null,
  };
}

/// What [l] picks, in a few words ("Work · #client · behind · due within 7 days").
String describeSmartList(SmartList l, AppData data) {
  final parts = <String>[
    if (l.categoryIds.isNotEmpty)
      [for (final c in l.categoryIds) c.isEmpty ? 'No category' : data.category(c)?.name ?? '?'].join(' or '),
    if (l.tags.isNotEmpty) l.tags.map((x) => x == untaggedFilter ? 'no tag' : '#$x').join(' or '),
    if (MatrixBox.byId(l.box) case final b?) '${b.label} box',
    if (l.starred) 'starred',
    if (l.behind) 'behind',
    if (l.waiting == true) 'waiting on someone',
    if (l.waiting == false) 'not waiting',
    if (l.place != null) 'at ${l.place}',
    if (l.maxMinutes != null) '≤ ${describeLength(l.maxMinutes!)}',
    if (SmartDue.byName(l.due) case final d?) d.label.toLowerCase(),
  ];
  return parts.isEmpty ? 'Every open task' : parts.join(' · ');
}

/// A few lists to start from.
List<SmartList> starterSmartLists() => [
      SmartList.create('Quick wins')
        ..emoji = '⚡'
        ..maxMinutes = 15,
      SmartList.create('Waiting on others')
        ..emoji = '⏳'
        ..waiting = true,
      SmartList.create('At risk')
        ..emoji = '🔥'
        ..behind = true,
      SmartList.create('Due this week')
        ..emoji = '📅'
        ..due = SmartDue.week.name,
    ];
