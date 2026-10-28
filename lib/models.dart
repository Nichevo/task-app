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
    this.categoryId,
    this.starred = false,
    this.snoozedUntil,
    this.afterTaskId,
    this.readyAt,
    this.repeat,
    this.remindBefore,
    List<TaskStep>? steps,
    this.eventId,
    DateTime? updatedAt,
  })  : steps = steps ?? [],
        updatedAt = updatedAt ?? createdAt;

  final String id;
  String title;
  String notes;
  final DateTime createdAt;
  DateTime? dueAt;
  DateTime? closedAt;

  /// The [TaskCategory] it belongs to; null for none.
  String? categoryId;

  /// Starred tasks are kept at the top of their list or category.
  bool starred;

  /// Hidden from the main list until this time.
  DateTime? snoozedUntil;

  /// This task waits for that one to be ticked off ("comes after").
  String? afterTaskId;

  /// When it stopped waiting for [afterTaskId]; its colour starts green again from here.
  DateTime? readyAt;

  /// How it comes back after being ticked off; null if it doesn't repeat.
  Repeat? repeat;

  /// Extra reminder this many minutes before the due time; null uses the default from Settings.
  int? remindBefore;

  /// Checklist of steps inside this task.
  final List<TaskStep> steps;

  /// The calendar event this task was made from, so it isn't offered twice.
  String? eventId;

  int get stepsDone => steps.where((s) => s.done).length;

  /// Last time anything about this task changed; the newer copy wins when syncing.
  DateTime updatedAt;

  void touch() => updatedAt = DateTime.now().toUtc();

  bool isSnoozed(DateTime now) => snoozedUntil != null && snoozedUntil!.isAfter(now);

  /// When the colour clock started: creation, or later if it was waiting or snoozed.
  DateTime colourStart(DateTime now) {
    var start = createdAt;
    for (final d in [readyAt, snoozedUntil]) {
      if (d != null && d.isAfter(start) && !d.isAfter(now)) start = d;
    }
    return start;
  }

  /// A fresh copy for the next time a repeating task comes round.
  Task nextRepeat(DateTime completedAt) {
    final r = repeat!;
    final next = Task.create(title)
      ..notes = notes
      ..categoryId = categoryId
      ..starred = starred
      ..repeat = r
      ..remindBefore = remindBefore;
    // Each repeat starts with the checklist unticked.
    next.steps.addAll([for (final st in steps) TaskStep.create(st.title)]);
    next.dueAt = r.nextDue(due: dueAt, completedAt: completedAt);
    return next;
  }

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
        if (categoryId != null) 'categoryId': categoryId,
        if (starred) 'starred': true,
        if (snoozedUntil != null) 'snoozedUntil': snoozedUntil!.toIso8601String(),
        if (afterTaskId != null) 'afterTaskId': afterTaskId,
        if (readyAt != null) 'readyAt': readyAt!.toIso8601String(),
        if (repeat != null) 'repeat': repeat!.toJson(),
        if (remindBefore != null) 'remindBefore': remindBefore,
        if (steps.isNotEmpty) 'steps': steps.map((s) => s.toJson()).toList(),
        if (eventId != null) 'eventId': eventId,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
        dueAt: _date(j['dueAt']),
        closedAt: _date(j['closedAt']),
        updatedAt: _date(j['updatedAt']),
        categoryId: j['categoryId'] as String?,
        starred: j['starred'] as bool? ?? false,
        snoozedUntil: _date(j['snoozedUntil']),
        afterTaskId: j['afterTaskId'] as String?,
        readyAt: _date(j['readyAt']),
        repeat: j['repeat'] is Map ? Repeat.fromJson(j['repeat'] as Map<String, dynamic>) : null,
        remindBefore: (j['remindBefore'] as num?)?.toInt(),
        steps: [for (final st in j['steps'] as List? ?? []) TaskStep.fromJson(st as Map<String, dynamic>)],
        eventId: j['eventId'] as String?,
      );

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
}

/// One line of a task's checklist. [taskId] is set when it was made into a full task.
class TaskStep {
  TaskStep({required this.id, required this.title, this.done = false, this.taskId});

  final String id;
  String title;
  bool done;
  String? taskId;

  factory TaskStep.create(String title) =>
      TaskStep(id: 's${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}', title: title.trim());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (done) 'done': true,
        if (taskId != null) 'taskId': taskId,
      };

  factory TaskStep.fromJson(Map<String, dynamic> j) => TaskStep(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        done: j['done'] as bool? ?? false,
        taskId: j['taskId'] as String?,
      );
}

/// A saved checklist that can be added to any task.
class ChecklistTemplate {
  ChecklistTemplate({required this.id, required this.name, List<String>? steps}) : steps = steps ?? [];

  final String id;
  String name;
  final List<String> steps;

  factory ChecklistTemplate.create(String name, List<String> steps) => ChecklistTemplate(
      id: 'tpl${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}', name: name.trim(), steps: steps);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'steps': steps};

  factory ChecklistTemplate.fromJson(Map<String, dynamic> j) => ChecklistTemplate(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        steps: [for (final s in j['steps'] as List? ?? []) s as String],
      );
}

/// A note that a task was ticked off, kept for the statistics after the archive is cleaned up.
class DoneRecord {
  const DoneRecord({required this.at, required this.tookMinutes, this.onTime, this.categoryId});

  final DateTime at;

  /// From when it was added to when it was ticked off.
  final int tookMinutes;

  /// Null when it had no due date.
  final bool? onTime;
  final String? categoryId;

  factory DoneRecord.of(Task t, DateTime at) => DoneRecord(
        at: at,
        tookMinutes: at.difference(t.createdAt).inMinutes,
        onTime: t.dueAt == null ? null : !at.isAfter(t.dueAt!),
        categoryId: t.categoryId,
      );

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'took': tookMinutes,
        if (onTime != null) 'onTime': onTime,
        if (categoryId != null) 'cat': categoryId,
      };

  factory DoneRecord.fromJson(Map<String, dynamic> j) => DoneRecord(
        at: DateTime.parse(j['at'] as String).toLocal(),
        tookMinutes: (j['took'] as num?)?.toInt() ?? 0,
        onTime: j['onTime'] as bool?,
        categoryId: j['cat'] as String?,
      );
}

/// What happens to the category of a task added without one.
enum AutoCategory { off, suggest, apply }

/// How often the app offers tasks from upcoming calendar events on its own.
enum EventSuggest { off, daily, weekly }

/// Reminders for tasks that are overdue.
enum OverdueMode { off, daily, nudge }

enum RepeatUnit { day, week, month, year }

/// How a task repeats.
class Repeat {
  const Repeat({
    required this.unit,
    this.every = 1,
    this.weekdays = const {},
    this.fromCompletion = false,
  });

  final RepeatUnit unit;

  /// Every this many [unit]s.
  final int every;

  /// For weekly repeats every week: which days (DateTime.monday..sunday). Empty = same weekday.
  final Set<int> weekdays;

  /// Count from when it was ticked off (e.g. "7 days after I last did it") instead of
  /// keeping to a fixed schedule from the previous due date.
  final bool fromCompletion;

  /// The next due date. Fixed schedules step on from the old due date until in the future;
  /// otherwise one step from [completedAt], keeping the old due time of day if there was one.
  DateTime nextDue({DateTime? due, required DateTime completedAt}) {
    if (fromCompletion || due == null) {
      final base = due == null
          ? completedAt
          : DateTime(completedAt.year, completedAt.month, completedAt.day, due.hour, due.minute);
      return _step(base);
    }
    var next = _step(due);
    while (!next.isAfter(completedAt)) {
      next = _step(next);
    }
    return next;
  }

  DateTime _step(DateTime d) {
    switch (unit) {
      case RepeatUnit.day:
        return DateTime(d.year, d.month, d.day + every, d.hour, d.minute);
      case RepeatUnit.week:
        if (every == 1 && weekdays.isNotEmpty) {
          for (var i = 1; i <= 7; i++) {
            final c = DateTime(d.year, d.month, d.day + i, d.hour, d.minute);
            if (weekdays.contains(c.weekday)) return c;
          }
        }
        return DateTime(d.year, d.month, d.day + 7 * every, d.hour, d.minute);
      case RepeatUnit.month:
        return _addMonths(d, every);
      case RepeatUnit.year:
        return _addMonths(d, 12 * every);
    }
  }

  static DateTime _addMonths(DateTime d, int months) {
    final m = d.month - 1 + months;
    final year = d.year + m ~/ 12;
    final month = m % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
  }

  String describe() {
    final n = every;
    final base = switch (unit) {
      RepeatUnit.day => n == 1 ? 'Every day' : 'Every $n days',
      RepeatUnit.week => n == 1
          ? (weekdays.isEmpty
              ? 'Every week'
              : 'Every ${(weekdays.toList()..sort()).map((d) => _dayNames[d - 1]).join(', ')}')
          : 'Every $n weeks',
      RepeatUnit.month => n == 1 ? 'Every month' : 'Every $n months',
      RepeatUnit.year => n == 1 ? 'Every year' : 'Every $n years',
    };
    return fromCompletion ? '$base after done' : base;
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Map<String, dynamic> toJson() => {
        'unit': unit.name,
        'every': every,
        if (weekdays.isNotEmpty) 'weekdays': (weekdays.toList()..sort()),
        if (fromCompletion) 'fromCompletion': true,
      };

  factory Repeat.fromJson(Map<String, dynamic> j) => Repeat(
        unit: RepeatUnit.values.firstWhere((u) => u.name == j['unit'], orElse: () => RepeatUnit.day),
        every: (j['every'] as num?)?.toInt() ?? 1,
        weekdays: {for (final d in j['weekdays'] as List? ?? []) (d as num).toInt()},
        fromCompletion: j['fromCompletion'] as bool? ?? false,
      );
}

class TaskCategory {
  TaskCategory({required this.id, required this.name, List<String>? keywords}) : keywords = keywords ?? [];

  final String id;
  String name;

  /// Words that always put a new task in this category.
  final List<String> keywords;

  factory TaskCategory.create(String name) =>
      TaskCategory(id: 'c${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}', name: name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (keywords.isNotEmpty) 'keywords': keywords};

  factory TaskCategory.fromJson(Map<String, dynamic> j) => TaskCategory(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        keywords: [for (final k in j['keywords'] as List? ?? []) k as String],
      );
}

/// Everything that gets saved locally and synced to Dropbox.
class AppData {
  AppData({
    List<Task>? active,
    List<Task>? archived,
    this.hoursToRed = 72,
    this.colourByDue = true,
    this.archiveKeepDays = 0,
    List<TaskCategory>? categories,
    this.groupByCategory = false,
    Set<String>? collapsed,
    this.focusNext30 = false,
    this.defaultRemindBefore = 0,
    List<ChecklistTemplate>? templates,
    Map<String, DoneRecord>? done,
    this.autoCategory = AutoCategory.suggest,
    this.eventSuggest = EventSuggest.off,
    Set<String>? eventCalendars,
    Set<String>? dismissedEvents,
    this.overdueMode = OverdueMode.off,
    this.overdueAt = 8 * 60,
    this.nudgeHours = 3,
    this.quietStart = 22 * 60,
    this.quietEnd = 7 * 60,
    DateTime? updatedAt,
    DateTime? orderUpdatedAt,
    DateTime? settingsUpdatedAt,
    Map<String, DateTime>? deleted,
  })  : active = active ?? [],
        archived = archived ?? [],
        deleted = deleted ?? {},
        categories = categories ?? [],
        collapsed = collapsed ?? {},
        templates = templates ?? [],
        done = done ?? {},
        eventCalendars = eventCalendars ?? {},
        dismissedEvents = dismissedEvents ?? {},
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

  /// In the order their headings are shown.
  final List<TaskCategory> categories;

  /// Show the list under category headings.
  bool groupByCategory;

  /// TaskCategory ids (or '' for "No category") whose headings are collapsed.
  final Set<String> collapsed;

  /// Only show tasks with no due date or due within the next 30 days.
  bool focusNext30;

  /// Default extra reminder before the due time, in minutes (0 = only at the due time).
  int defaultRemindBefore;

  /// Saved checklists.
  final List<ChecklistTemplate> templates;

  /// Every task ever ticked off, by task id, for the statistics.
  final Map<String, DoneRecord> done;

  AutoCategory autoCategory;

  EventSuggest eventSuggest;

  /// Calendars (ids on the phone) to take events from; empty means all.
  final Set<String> eventCalendars;

  /// Calendar events the user chose not to make tasks from.
  final Set<String> dismissedEvents;

  OverdueMode overdueMode;

  /// Minutes after midnight for the daily overdue summary.
  int overdueAt;

  /// Hours between nudges for an overdue task.
  int nudgeHours;

  /// Quiet hours (minutes after midnight) when no overdue reminders are sent.
  int quietStart;
  int quietEnd;

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
        'categories': categories.map((c) => c.toJson()).toList(),
        'groupByCategory': groupByCategory,
        'collapsed': collapsed.toList(),
        'focusNext30': focusNext30,
        'defaultRemindBefore': defaultRemindBefore,
        'templates': templates.map((t) => t.toJson()).toList(),
        'done': done.map((k, v) => MapEntry(k, v.toJson())),
        'autoCategory': autoCategory.name,
        'eventSuggest': eventSuggest.name,
        'eventCalendars': eventCalendars.toList(),
        'dismissedEvents': dismissedEvents.toList(),
        'overdueMode': overdueMode.name,
        'overdueAt': overdueAt,
        'nudgeHours': nudgeHours,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'orderUpdatedAt': orderUpdatedAt.toUtc().toIso8601String(),
        'settingsUpdatedAt': settingsUpdatedAt.toUtc().toIso8601String(),
        'deleted': deleted.map((k, v) => MapEntry(k, v.toUtc().toIso8601String())),
        'active': active.map((t) => t.toJson()).toList(),
        'archived': archived.map((t) => t.toJson()).toList(),
      };

  TaskCategory? category(String? id) => categories.where((c) => c.id == id).firstOrNull;

  Task? task(String? id) => id == null
      ? null
      : active.where((t) => t.id == id).firstOrNull ?? archived.where((t) => t.id == id).firstOrNull;

  /// Waiting for an earlier task that is still open.
  bool isLocked(Task t) => t.afterTaskId != null && active.any((a) => a.id == t.afterTaskId);

  /// Open and archived tasks together.
  Iterable<Task> get allTasks => active.followedBy(archived);

  /// The task made from a calendar event, if any.
  Task? taskForEvent(String eventId) => allTasks.where((t) => t.eventId == eventId).firstOrNull;

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        hoursToRed: (j['hoursToRed'] as num?)?.toDouble() ?? 72,
        colourByDue: j['colourByDue'] as bool? ?? true,
        archiveKeepDays: (j['archiveKeepDays'] as num?)?.toInt() ?? 0,
        categories: [for (final c in j['categories'] as List? ?? []) TaskCategory.fromJson(c)],
        groupByCategory: j['groupByCategory'] as bool? ?? false,
        collapsed: {for (final c in j['collapsed'] as List? ?? []) c as String},
        focusNext30: j['focusNext30'] as bool? ?? false,
        defaultRemindBefore: (j['defaultRemindBefore'] as num?)?.toInt() ?? 0,
        templates: [for (final t in j['templates'] as List? ?? []) ChecklistTemplate.fromJson(t)],
        done: {
          for (final e in (j['done'] as Map? ?? {}).entries)
            e.key as String: DoneRecord.fromJson(e.value as Map<String, dynamic>),
        },
        autoCategory: _enum(AutoCategory.values, j['autoCategory'], AutoCategory.suggest),
        eventSuggest: _enum(EventSuggest.values, j['eventSuggest'], EventSuggest.off),
        eventCalendars: {for (final c in j['eventCalendars'] as List? ?? []) c as String},
        dismissedEvents: {for (final c in j['dismissedEvents'] as List? ?? []) c as String},
        overdueMode: _enum(OverdueMode.values, j['overdueMode'], OverdueMode.off),
        overdueAt: (j['overdueAt'] as num?)?.toInt() ?? 8 * 60,
        nudgeHours: (j['nudgeHours'] as num?)?.toInt() ?? 3,
        quietStart: (j['quietStart'] as num?)?.toInt() ?? 22 * 60,
        quietEnd: (j['quietEnd'] as num?)?.toInt() ?? 7 * 60,
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

  // Completion records: keep every one from either side (newest if both have it).
  final done = <String, DoneRecord>{...a.done};
  b.done.forEach((id, r) {
    final mine = done[id];
    if (mine == null || r.at.isAfter(mine.at)) done[id] = r;
  });

  return AppData(
    active: active,
    archived: archived,
    hoursToRed: settingsFrom.hoursToRed,
    colourByDue: settingsFrom.colourByDue,
    archiveKeepDays: settingsFrom.archiveKeepDays,
    categories: settingsFrom.categories,
    groupByCategory: settingsFrom.groupByCategory,
    collapsed: settingsFrom.collapsed,
    focusNext30: settingsFrom.focusNext30,
    defaultRemindBefore: settingsFrom.defaultRemindBefore,
    templates: settingsFrom.templates,
    done: done,
    autoCategory: settingsFrom.autoCategory,
    eventSuggest: settingsFrom.eventSuggest,
    eventCalendars: settingsFrom.eventCalendars,
    dismissedEvents: {...a.dismissedEvents, ...b.dismissedEvents},
    overdueMode: settingsFrom.overdueMode,
    overdueAt: settingsFrom.overdueAt,
    nudgeHours: settingsFrom.nudgeHours,
    quietStart: settingsFrom.quietStart,
    quietEnd: settingsFrom.quietEnd,
    settingsUpdatedAt: settingsFrom.settingsUpdatedAt,
    updatedAt: b.updatedAt.isAfter(a.updatedAt) ? b.updatedAt : a.updatedAt,
    orderUpdatedAt: orderFrom.orderUpdatedAt,
    deleted: deleted,
  );
}
