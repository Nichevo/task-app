import 'dart:math';

/// A single task. Active tasks have [closedAt] == null.
class Task {
  Task({
    required this.id,
    required this.title,
    required this.createdAt,
    this.notes = '',
    this.dueAt,
    this.closedAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  String title;
  String notes;
  final DateTime createdAt;
  DateTime? dueAt;
  DateTime? closedAt;

  /// Last time anything about this task changed; the newer copy wins when syncing.
  DateTime updatedAt;

  void touch() => updatedAt = DateTime.now().toUtc();

  factory Task.create(String title) => Task(
        id: '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}',
        title: title,
        createdAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'dueAt': dueAt?.toIso8601String(),
        'closedAt': closedAt?.toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
        dueAt: _date(j['dueAt']),
        closedAt: _date(j['closedAt']),
        updatedAt: _date(j['updatedAt']),
      );

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
}

/// Everything that gets saved locally and synced to Dropbox.
class AppData {
  AppData({
    List<Task>? active,
    List<Task>? archived,
    this.hoursToRed = 72,
    this.colourByDue = true,
    this.archiveKeepDays = 0,
    DateTime? updatedAt,
    DateTime? orderUpdatedAt,
    DateTime? settingsUpdatedAt,
    Map<String, DateTime>? deleted,
  })  : active = active ?? [],
        archived = archived ?? [],
        deleted = deleted ?? {},
        updatedAt = updatedAt ?? _epoch,
        orderUpdatedAt = orderUpdatedAt ?? _epoch,
        settingsUpdatedAt = settingsUpdatedAt ?? _epoch;

  static final _epoch = DateTime.utc(1970);

  /// In the order the user has dragged them into.
  final List<Task> active;

  /// Most recently closed first.
  final List<Task> archived;

  /// How many hours a task takes to go from green to red.
  double hoursToRed;

  /// Tasks with a due date go green to red between creation and the due date instead.
  bool colourByDue;

  /// Archived tasks closed longer ago than this are deleted; 0 keeps them forever.
  int archiveKeepDays;

  /// When anything was last changed.
  DateTime updatedAt;

  /// When a setting above was last changed; the newer copy's settings win on sync.
  DateTime settingsUpdatedAt;

  /// When the order of [active] was last changed (add or drag).
  DateTime orderUpdatedAt;

  /// Ids of deleted tasks and when, so a sync doesn't bring them back.
  final Map<String, DateTime> deleted;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'hoursToRed': hoursToRed,
        'colourByDue': colourByDue,
        'archiveKeepDays': archiveKeepDays,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'orderUpdatedAt': orderUpdatedAt.toUtc().toIso8601String(),
        'settingsUpdatedAt': settingsUpdatedAt.toUtc().toIso8601String(),
        'deleted': deleted.map((k, v) => MapEntry(k, v.toUtc().toIso8601String())),
        'active': active.map((t) => t.toJson()).toList(),
        'archived': archived.map((t) => t.toJson()).toList(),
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        hoursToRed: (j['hoursToRed'] as num?)?.toDouble() ?? 72,
        colourByDue: j['colourByDue'] as bool? ?? true,
        archiveKeepDays: (j['archiveKeepDays'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        orderUpdatedAt: DateTime.tryParse(j['orderUpdatedAt'] as String? ?? ''),
        settingsUpdatedAt: DateTime.tryParse(j['settingsUpdatedAt'] as String? ?? ''),
        deleted: {
          for (final e in (j['deleted'] as Map? ?? {}).entries)
            e.key as String: ?DateTime.tryParse(e.value as String),
        },
        active: [for (final t in j['active'] as List? ?? []) Task.fromJson(t)],
        archived: [for (final t in j['archived'] as List? ?? []) Task.fromJson(t)],
      );
}

/// Combines two copies of the data (this device's and Dropbox's) task by task, so edits
/// made on both devices between syncs are kept. For each task the most recently changed
/// copy wins; a deletion wins over edits made before it.
AppData mergeData(AppData a, AppData b) {
  final settingsFrom = b.settingsUpdatedAt.isAfter(a.settingsUpdatedAt) ? b : a;
  final orderFrom = b.orderUpdatedAt.isAfter(a.orderUpdatedAt) ? b : a;

  final deleted = <String, DateTime>{...a.deleted};
  b.deleted.forEach((id, at) {
    final mine = deleted[id];
    if (mine == null || at.isAfter(mine)) deleted[id] = at;
  });

  final tasks = <String, Task>{};
  for (final t in [...a.active, ...a.archived, ...b.active, ...b.archived]) {
    final seen = tasks[t.id];
    if (seen == null || t.updatedAt.isAfter(seen.updatedAt)) tasks[t.id] = t;
  }
  tasks.removeWhere((id, t) {
    final at = deleted[id];
    return at != null && !t.updatedAt.isAfter(at);
  });
  // Forget deletions after 90 days to keep the file small.
  final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 90));
  deleted.removeWhere((_, at) => at.isBefore(cutoff));

  final open = tasks.values.where((t) => t.closedAt == null).toSet();
  final active = <Task>[
    for (final t in orderFrom.active)
      if (tasks[t.id] case final m? when open.contains(m)) m,
  ];
  final placed = active.toSet();
  active.addAll(open.where((t) => !placed.contains(t)).toList()
    ..sort((x, y) => x.createdAt.compareTo(y.createdAt)));

  final archived = tasks.values.where((t) => t.closedAt != null).toList()
    ..sort((x, y) => y.closedAt!.compareTo(x.closedAt!));

  return AppData(
    active: active,
    archived: archived,
    hoursToRed: settingsFrom.hoursToRed,
    colourByDue: settingsFrom.colourByDue,
    archiveKeepDays: settingsFrom.archiveKeepDays,
    settingsUpdatedAt: settingsFrom.settingsUpdatedAt,
    updatedAt: b.updatedAt.isAfter(a.updatedAt) ? b.updatedAt : a.updatedAt,
    orderUpdatedAt: orderFrom.orderUpdatedAt,
    deleted: deleted,
  );
}
