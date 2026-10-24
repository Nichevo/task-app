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
  });

  final String id;
  String title;
  String notes;
  final DateTime createdAt;
  DateTime? dueAt;
  DateTime? closedAt;

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
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
        dueAt: _date(j['dueAt']),
        closedAt: _date(j['closedAt']),
      );

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
}

/// Everything that gets saved locally and synced to Dropbox.
class AppData {
  AppData({
    List<Task>? active,
    List<Task>? archived,
    this.hoursToRed = 72,
    DateTime? updatedAt,
  })  : active = active ?? [],
        archived = archived ?? [],
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// In the order the user has dragged them into.
  final List<Task> active;

  /// Most recently closed first.
  final List<Task> archived;

  /// How many hours a task takes to go from green to red.
  double hoursToRed;

  /// When this data was last changed on any device; newest copy wins on sync.
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'hoursToRed': hoursToRed,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'active': active.map((t) => t.toJson()).toList(),
        'archived': archived.map((t) => t.toJson()).toList(),
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        hoursToRed: (j['hoursToRed'] as num?)?.toDouble() ?? 72,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        active: [for (final t in j['active'] as List? ?? []) Task.fromJson(t)],
        archived: [for (final t in j['archived'] as List? ?? []) Task.fromJson(t)],
      );
}
