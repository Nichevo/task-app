import 'dart:math';

import 'changelog.dart';

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
    this.source,
    this.addedWhere,
    this.doneWhere,
    this.estimate,
    this.seriesId,
    this.place,
    this.placeLeave = false,
    this.kanban = false,
    this.stageId,
    List<StageMove>? moves,
    this.stepsOnBoard = false,
    List<TaskEmail>? emails,
    DateTime? updatedAt,
    Map<String, dynamic>? extra,
  })  : steps = steps ?? [],
        moves = moves ?? [],
        emails = emails ?? [],
        extra = extra ?? {},
        updatedAt = updatedAt ?? createdAt;

  /// Item 62: fields written by a newer version of the app that this one doesn't know. Kept
  /// and written back unchanged, so an older device never drops newer data when it syncs.
  final Map<String, dynamic> extra;

  static const _known = {
    'id', 'title', 'notes', 'createdAt', 'dueAt', 'closedAt', 'updatedAt', 'categoryId', 'starred',
    'snoozedUntil', 'afterTaskId', 'readyAt', 'repeat', 'remindBefore', 'steps', 'eventId', 'source',
    'addedWhere', 'doneWhere', 'estimate', 'series', 'place', 'placeLeave', 'kanban', 'stage', 'moves',
    'stepsBoard', 'emails',
  };

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

  /// How the task got into the app: one of the [TaskSource] names, or another name sent by an
  /// outside tool. Null for tasks made before sources were recorded ("Unknown").
  String? source;

  /// Where the phone was when the task was added and when it was ticked off (if location
  /// recording is on in Settings). Kept for place-based reminders later.
  GeoPoint? addedWhere;
  GeoPoint? doneWhere;

  /// About how long it takes, in minutes; null if not given.
  int? estimate;

  /// The first task of a repeating series; every repeat carries it so the series can be
  /// counted together. Null on the first one (its own id is the series).
  String? seriesId;

  String get series => seriesId ?? id;

  /// Name of a saved place (Settings, Places) to be reminded at; places themselves stay on the
  /// phone, so only the name travels with the task.
  String? place;

  /// Remind when leaving [place] instead of arriving.
  bool placeLeave;

  /// On the Kanban board (item 52).
  bool kanban;

  /// The [KanbanStage] it is in. Kept when taken off the board, so it goes back there.
  String? stageId;

  /// Every move between stages, oldest first. Never rewritten; synced by joining both copies.
  final List<StageMove> moves;

  /// Item 56: its checklist steps are cards on the board too, each moving through the stages
  /// on its own.
  bool stepsOnBoard;

  /// Item 55: emails attached to it (or that it was made from), newest last.
  final List<TaskEmail> emails;

  /// The steps showing on the board: none unless the task is on it with [stepsOnBoard] on.
  List<TaskStep> get boardSteps => kanban && stepsOnBoard ? steps : const [];

  /// When it went into its current stage (null when not on the board or never moved).
  DateTime? get stageSince => kanban && moves.isNotEmpty ? moves.last.at : null;

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
      ..remindBefore = remindBefore
      ..estimate = estimate
      ..place = place
      ..placeLeave = placeLeave
      ..seriesId = series
      ..stepsOnBoard = stepsOnBoard
      ..source = TaskSource.repeat;
    // Each repeat starts with the checklist unticked.
    next.steps.addAll([for (final st in steps) TaskStep.create(st.title)]);
    next.dueAt = r.nextDue(due: dueAt, completedAt: completedAt);
    return next;
  }

  factory Task.create(String title, {String source = TaskSource.typed}) => Task(
        id: '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}',
        title: title,
        createdAt: DateTime.now(),
        source: source,
      );

  Map<String, dynamic> toJson() => {
        ...extra,
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
        if (source != null) 'source': source,
        if (addedWhere != null) 'addedWhere': addedWhere!.toJson(),
        if (doneWhere != null) 'doneWhere': doneWhere!.toJson(),
        if (estimate != null) 'estimate': estimate,
        if (seriesId != null) 'series': seriesId,
        if (place != null) 'place': place,
        if (placeLeave) 'placeLeave': true,
        if (kanban) 'kanban': true,
        if (stageId != null) 'stage': stageId,
        if (moves.isNotEmpty) 'moves': moves.map((m) => m.toJson()).toList(),
        if (stepsOnBoard) 'stepsBoard': true,
        if (emails.isNotEmpty) 'emails': emails.map((e) => e.toJson()).toList(),
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
        // Older calendar tasks are known to be from the calendar even without a source.
        source: j['source'] as String? ?? (j['eventId'] != null ? TaskSource.calendar : null),
        addedWhere: GeoPoint.tryParse(j['addedWhere']),
        doneWhere: GeoPoint.tryParse(j['doneWhere']),
        estimate: (j['estimate'] as num?)?.toInt(),
        seriesId: j['series'] as String?,
        place: j['place'] as String?,
        placeLeave: j['placeLeave'] as bool? ?? false,
        kanban: j['kanban'] as bool? ?? false,
        stageId: j['stage'] as String?,
        moves: [for (final m in j['moves'] as List? ?? []) StageMove.fromJson(m as Map<String, dynamic>)],
        stepsOnBoard: j['stepsBoard'] as bool? ?? false,
        emails: [for (final e in j['emails'] as List? ?? []) TaskEmail.fromJson(e as Map<String, dynamic>)],
        extra: unknownFields(j, _known),
      );

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
}

/// The ways a task can get into the app. Stored as plain names so new ones (another app pushing
/// tasks in, email, ...) can be added later without changing older copies of the app; a name the
/// app doesn't know is shown as it is.
abstract final class TaskSource {
  static const typed = 'typed';
  static const widget = 'widget';
  static const voice = 'voice';
  static const share = 'share';
  static const paste = 'paste';
  static const photo = 'photo';
  static const inbox = 'inbox';
  static const calendar = 'calendar';
  static const csv = 'csv';
  static const repeat = 'repeat';
  static const step = 'step';
  static const kanban = 'kanban';
  static const starredEmail = 'starredEmail';

  static const labels = {
    typed: 'Typed in the app',
    widget: 'Home screen widget',
    voice: 'Voice',
    share: 'Shared from another app',
    paste: 'Pasted list',
    photo: 'Photo of a list',
    inbox: 'Dropbox inbox',
    calendar: 'Calendar',
    csv: 'CSV import',
    repeat: 'Repeat of an earlier task',
    step: 'Checklist step',
    kanban: 'Kanban board',
    starredEmail: 'Starred email',
  };

  /// A name for showing; [source] null is a task from before sources were recorded.
  static String label(String? source) {
    if (source == null || source.isEmpty) return 'Unknown';
    return labels[source] ?? source[0].toUpperCase() + source.substring(1);
  }
}

/// Item 55: an email kept on a task. Only these few details are stored, never the whole email,
/// because tasks sync through Dropbox.
class TaskEmail {
  TaskEmail({
    required this.id,
    this.threadId,
    this.subject = '',
    this.from = '',
    this.date,
    this.snippet = '',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  /// Gmail's message id.
  final String id;
  final String? threadId;
  final String subject;

  /// The From line as Gmail shows it ("Name <address>").
  final String from;
  final DateTime? date;

  /// The first part of the text, as Gmail gives it.
  final String snippet;

  /// Item 62: fields from a newer version, kept as they are.
  final Map<String, dynamic> extra;

  static const _known = {'id', 'thread', 'subject', 'from', 'date', 'snippet'};

  /// Opens the email in Gmail (the app on a phone, the browser on a computer).
  Uri get link => Uri.parse('https://mail.google.com/mail/u/0/#all/${threadId ?? id}');

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        if (threadId != null) 'thread': threadId,
        'subject': subject,
        'from': from,
        if (date != null) 'date': date!.toUtc().toIso8601String(),
        if (snippet.isNotEmpty) 'snippet': snippet,
      };

  factory TaskEmail.fromJson(Map<String, dynamic> j) => TaskEmail(
        id: j['id'] as String,
        threadId: j['thread'] as String?,
        subject: j['subject'] as String? ?? '',
        from: j['from'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '')?.toLocal(),
        snippet: j['snippet'] as String? ?? '',
        extra: unknownFields(j, _known),
      );
}

/// A location fix: latitude and longitude in degrees, accuracy in metres, and when it was taken.
class GeoPoint {
  const GeoPoint({required this.lat, required this.lng, this.accuracy, required this.at});

  final double lat;
  final double lng;
  final double? accuracy;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'acc': accuracy!.roundToDouble(),
        'at': at.toUtc().toIso8601String(),
      };

  static GeoPoint? tryParse(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'];
    if (lat is! num || lng is! num) return null;
    return GeoPoint(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      accuracy: (j['acc'] as num?)?.toDouble(),
      at: DateTime.tryParse(j['at'] as String? ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  String toString() => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
}

/// One line of a task's checklist. [taskId] is set when it was made into a full task.
class TaskStep {
  TaskStep(
      {required this.id,
      required this.title,
      this.done = false,
      this.taskId,
      this.stageId,
      List<StageMove>? moves,
      Map<String, dynamic>? extra})
      : moves = moves ?? [],
        extra = extra ?? {};

  /// Item 62: fields written by a newer version of the app that this one doesn't know. Kept
  /// and written back unchanged, so an older device never drops newer data when it syncs.
  final Map<String, dynamic> extra;

  static const _known = {'id', 'title', 'done', 'taskId', 'stage', 'moves'};

  final String id;
  String title;
  bool done;
  String? taskId;

  /// Item 56: the Kanban stage it is in when its task has steps on the board. Kept while they
  /// are off the board, so it goes back there.
  String? stageId;

  /// Its own moves between stages, oldest first; synced by joining both copies like a task's.
  final List<StageMove> moves;

  /// On the board right now: its last move went into a stage.
  bool get placed => moves.isNotEmpty && moves.last.toId != null;

  /// When it went into its current stage.
  DateTime? get stageSince => moves.isNotEmpty && moves.last.toId != null ? moves.last.at : null;

  factory TaskStep.create(String title) =>
      TaskStep(id: 's${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}', title: title.trim());

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'title': title,
        if (done) 'done': true,
        if (taskId != null) 'taskId': taskId,
        if (stageId != null) 'stage': stageId,
        if (moves.isNotEmpty) 'moves': moves.map((m) => m.toJson()).toList(),
      };

  factory TaskStep.fromJson(Map<String, dynamic> j) => TaskStep(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        done: j['done'] as bool? ?? false,
        taskId: j['taskId'] as String?,
        stageId: j['stage'] as String?,
        moves: [for (final m in j['moves'] as List? ?? []) StageMove.fromJson(m as Map<String, dynamic>)],
        extra: unknownFields(j, _known),
      );
}

/// A saved checklist that can be added to any task.
class ChecklistTemplate {
  ChecklistTemplate({required this.id, required this.name, List<String>? steps, Map<String, dynamic>? extra})
      : steps = steps ?? [],
        extra = extra ?? {};

  /// Item 62: fields written by a newer version of the app that this one doesn't know. Kept
  /// and written back unchanged, so an older device never drops newer data when it syncs.
  final Map<String, dynamic> extra;

  static const _known = {'id', 'name', 'steps'};

  final String id;
  String name;
  final List<String> steps;

  factory ChecklistTemplate.create(String name, List<String> steps) => ChecklistTemplate(
      id: 'tpl${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}', name: name.trim(), steps: steps);

  Map<String, dynamic> toJson() => {...extra, 'id': id, 'name': name, 'steps': steps};

  factory ChecklistTemplate.fromJson(Map<String, dynamic> j) => ChecklistTemplate(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        steps: [for (final s in j['steps'] as List? ?? []) s as String],
        extra: unknownFields(j, _known),
      );
}

/// A note that a task was ticked off, kept for the statistics after the archive is cleaned up.
class DoneRecord {
  const DoneRecord({
    required this.at,
    required this.tookMinutes,
    this.onTime,
    this.categoryId,
    this.source,
    this.title,
    this.series,
    this.lateMinutes,
    this.missed = 0,
    this.stageMinutes,
    this.extra = const {},
  });

  /// Item 62: fields written by a newer version of the app that this one doesn't know. Kept
  /// and written back unchanged, so an older device never drops newer data when it syncs.
  final Map<String, dynamic> extra;

  static const _known = {'at', 'took', 'onTime', 'cat', 'src', 'title', 'series', 'late', 'missed', 'stages'};

  final DateTime at;

  /// From when it was added to when it was ticked off.
  final int tookMinutes;

  /// Null when it had no due date.
  final bool? onTime;
  final String? categoryId;

  /// How the task got into the app ([Task.source]); null on records from before 1.4.
  final String? source;

  /// The task's name, so a repeating series can still be named after its tasks are cleaned up.
  final String? title;

  /// [Task.series] when the task repeats.
  final String? series;

  /// How long after the due time it was ticked off, in minutes; negative = early. Null without
  /// a due date, and on records from before 1.4.
  final int? lateMinutes;

  /// Whole repeat cycles that went by without a tick before this one was done (fixed schedules).
  final int missed;

  /// Minutes spent in each Kanban stage (by stage id) for a board task, so the Kanban
  /// statistics survive the archive clean-up. Null for other tasks.
  final Map<String, int>? stageMinutes;

  /// When the task was added.
  DateTime get createdAt => at.subtract(Duration(minutes: tookMinutes));

  /// The due time, when it had one and the record is new enough to know it.
  DateTime? get due => lateMinutes == null ? null : at.subtract(Duration(minutes: lateMinutes!));

  factory DoneRecord.of(Task t, DateTime at) => DoneRecord(
        at: at,
        tookMinutes: at.difference(t.createdAt).inMinutes,
        onTime: t.dueAt == null ? null : !at.isAfter(t.dueAt!),
        categoryId: t.categoryId,
        source: t.source,
        title: t.title,
        series: t.repeat != null || t.seriesId != null ? t.series : null,
        lateMinutes: t.dueAt == null ? null : at.difference(t.dueAt!).inMinutes,
        missed: missedCycles(t, at),
        stageMinutes: t.moves.isEmpty ? null : minutesPerStage(t, at),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'at': at.toUtc().toIso8601String(),
        'took': tookMinutes,
        if (onTime != null) 'onTime': onTime,
        if (categoryId != null) 'cat': categoryId,
        if (source != null) 'src': source,
        if (title != null) 'title': title,
        if (series != null) 'series': series,
        if (lateMinutes != null) 'late': lateMinutes,
        if (missed > 0) 'missed': missed,
        if (stageMinutes != null) 'stages': stageMinutes,
      };

  factory DoneRecord.fromJson(Map<String, dynamic> j) => DoneRecord(
        at: DateTime.parse(j['at'] as String).toLocal(),
        tookMinutes: (j['took'] as num?)?.toInt() ?? 0,
        onTime: j['onTime'] as bool?,
        categoryId: j['cat'] as String?,
        source: j['src'] as String?,
        title: j['title'] as String?,
        series: j['series'] as String?,
        lateMinutes: (j['late'] as num?)?.toInt(),
        missed: (j['missed'] as num?)?.toInt() ?? 0,
        stageMinutes: j['stages'] is Map
            ? {for (final e in (j['stages'] as Map).entries) e.key as String: (e.value as num).toInt()}
            : null,
        extra: unknownFields(j, _known),
      );
}

/// How many whole cycles of a fixed-schedule repeating task went by, unticked, between its
/// due date and [at] (not counting the one it is due for). 0 for other tasks.
int missedCycles(Task t, DateTime at) {
  final r = t.repeat, due = t.dueAt;
  if (r == null || r.fromCompletion || due == null) return 0;
  var n = 0;
  var d = due;
  while (n < 1000) {
    final next = r.nextDue(due: d, completedAt: d);
    if (next.isAfter(at)) break;
    n++;
    d = next;
  }
  return n;
}

/// A column of the Kanban board.
class KanbanStage {
  KanbanStage({required this.id, required this.name, this.colour, this.limit, Map<String, dynamic>? extra})
      : extra = extra ?? {};

  /// Item 62: fields written by a newer version of the app that this one doesn't know. Kept
  /// and written back unchanged, so an older device never drops newer data when it syncs.
  final Map<String, dynamic> extra;

  static const _known = {'id', 'name', 'colour', 'limit'};

  final String id;
  String name;

  /// ARGB colour for the column heading; null for none.
  int? colour;

  /// Most tasks it should hold; the heading turns amber above it. Null for no limit.
  int? limit;

  factory KanbanStage.create(String name) =>
      KanbanStage(id: 'k${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}', name: name.trim());

  /// Fixed ids, so two devices set up separately share the same stages.
  static List<KanbanStage> defaults() => [
        KanbanStage(id: 'backlog', name: 'Backlog'),
        KanbanStage(id: 'next', name: 'Up next'),
        KanbanStage(id: 'doing', name: 'In progress'),
        KanbanStage(id: 'blocked', name: 'Blocked'),
        KanbanStage(id: 'done', name: 'Done'),
      ];

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'name': name,
        if (colour != null) 'colour': colour,
        if (limit != null) 'limit': limit,
      };

  factory KanbanStage.fromJson(Map<String, dynamic> j) => KanbanStage(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        colour: (j['colour'] as num?)?.toInt(),
        limit: (j['limit'] as num?)?.toInt(),
        extra: unknownFields(j, _known),
      );
}

/// How a task was moved between stages. Plain names, like [TaskSource].
abstract final class MoveHow {
  static const added = 'added';
  static const dragged = 'dragged';
  static const swiped = 'swiped';
  static const menu = 'menu';
  static const taskPage = 'task';
  static const done = 'done';
  static const reopened = 'reopened';
  static const removed = 'removed';
  static const stageRemoved = 'stageRemoved';
  static const repeat = 'repeat';

  static const labels = {
    added: 'Put on the board',
    dragged: 'Dragged',
    swiped: 'Swiped',
    menu: 'Move to…',
    taskPage: 'On the task page',
    done: 'Ticked off',
    reopened: 'Reopened',
    removed: 'Taken off the board',
    stageRemoved: 'Stage removed',
    repeat: 'Next repeat',
  };

  static String label(String how) => labels[how] ?? how;
}

/// One move of a task on the Kanban board. [toId] is null when it was taken off the board,
/// [fromId] null when it was put on. Stage names are kept as they were at the time.
class StageMove {
  StageMove({
    required this.id,
    this.fromId,
    this.fromName,
    this.toId,
    this.toName,
    required this.at,
    required this.how,
    this.where,
    this.device,
    this.note,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  /// Item 62: fields written by a newer version of the app that this one doesn't know. Kept
  /// and written back unchanged, so an older device never drops newer data when it syncs.
  final Map<String, dynamic> extra;

  static const _known = {'id', 'from', 'fromName', 'to', 'toName', 'at', 'how', 'where', 'device', 'note'};

  final String id;
  final String? fromId;
  final String? fromName;
  final String? toId;
  final String? toName;
  final DateTime at;

  /// One of the [MoveHow] names.
  final String how;

  /// Where the phone was, when location recording is on. Filled in once the fix arrives.
  GeoPoint? where;

  /// Which device made the move (Android, Windows, Mac, ...).
  final String? device;

  /// Optional words from "Move to…" ("waiting on parts").
  final String? note;

  factory StageMove.create({
    KanbanStage? from,
    KanbanStage? to,
    required DateTime at,
    required String how,
    String? device,
    String? note,
  }) =>
      StageMove(
        id: 'm${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}',
        fromId: from?.id,
        fromName: from?.name,
        toId: to?.id,
        toName: to?.name,
        at: at,
        how: how,
        device: device,
        note: note == null || note.trim().isEmpty ? null : note.trim(),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        if (fromId != null) 'from': fromId,
        if (fromName != null) 'fromName': fromName,
        if (toId != null) 'to': toId,
        if (toName != null) 'toName': toName,
        'at': at.toUtc().toIso8601String(),
        'how': how,
        if (where != null) 'where': where!.toJson(),
        if (device != null) 'device': device,
        if (note != null) 'note': note,
      };

  factory StageMove.fromJson(Map<String, dynamic> j) => StageMove(
        id: j['id'] as String,
        fromId: j['from'] as String?,
        fromName: j['fromName'] as String?,
        toId: j['to'] as String?,
        toName: j['toName'] as String?,
        at: DateTime.parse(j['at'] as String).toLocal(),
        how: j['how'] as String? ?? MoveHow.menu,
        where: GeoPoint.tryParse(j['where']),
        device: j['device'] as String?,
        note: j['note'] as String?,
        extra: unknownFields(j, _known),
      );
}

/// One spell of a task in a stage: from [start] to [end] (null = still there).
typedef StageStint = ({String stageId, DateTime start, DateTime? end});

/// The spells [t] spent in each stage, from its moves. Time off the board isn't counted.
List<StageStint> stageStints(Task t) => moveStints(t.moves);

/// The spells in each stage from a list of moves (a task's or a step's).
List<StageStint> moveStints(List<StageMove> moves) {
  final out = <StageStint>[];
  String? current;
  DateTime? since;
  for (final m in moves) {
    if (current != null && since != null) out.add((stageId: current, start: since, end: m.at));
    current = m.toId;
    since = m.at;
  }
  if (current != null && since != null) out.add((stageId: current, start: since, end: null));
  return out;
}

/// Minutes in each stage up to [until], by stage id.
Map<String, int> minutesPerStage(Task t, DateTime until) {
  final out = <String, int>{};
  for (final s in stageStints(t)) {
    final end = s.end ?? until;
    if (end.isBefore(s.start)) continue;
    out[s.stageId] = (out[s.stageId] ?? 0) + end.difference(s.start).inMinutes;
  }
  return out;
}

/// What happens when a task is moved into the last stage.
enum KanbanDone { ask, always, never }

/// A repeating task moved on to its next date without being done ("Skip").
class SkipRecord {
  const SkipRecord({required this.taskId, required this.series, required this.at, this.due, this.missed = 0});

  final String taskId;

  /// [Task.series] of the repeating task.
  final String series;

  /// When Skip was pressed.
  final DateTime at;

  /// The due date that was skipped, if it had one.
  final DateTime? due;

  /// Whole cycles that had already gone by unticked when it was skipped (see [missedCycles]).
  final int missed;

  /// One record per skipped due date, so the same skip synced from two devices counts once.
  String get key => '$taskId@${(due ?? at).toUtc().toIso8601String()}';

  Map<String, dynamic> toJson() => {
        'task': taskId,
        'series': series,
        'at': at.toUtc().toIso8601String(),
        if (due != null) 'due': due!.toUtc().toIso8601String(),
        if (missed > 0) 'missed': missed,
      };

  factory SkipRecord.fromJson(Map<String, dynamic> j) => SkipRecord(
        taskId: j['task'] as String? ?? '',
        series: j['series'] as String? ?? j['task'] as String? ?? '',
        at: DateTime.parse(j['at'] as String).toLocal(),
        due: DateTime.tryParse(j['due'] as String? ?? '')?.toLocal(),
        missed: (j['missed'] as num?)?.toInt() ?? 0,
      );
}

/// How the main list is ordered (Settings, List).
enum ListSort { manual, due, age, newest, categoryDue }

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
        if (weekdays.isEmpty) return DateTime(d.year, d.month, d.day + 7 * every, d.hour, d.minute);
        // A later chosen day in the same (Monday-first) week, else the first chosen day of the
        // week [every] weeks on.
        for (var i = 1; i <= 7 - d.weekday; i++) {
          final c = DateTime(d.year, d.month, d.day + i, d.hour, d.minute);
          if (weekdays.contains(c.weekday)) return c;
        }
        final monday = d.day - (d.weekday - 1) + 7 * every;
        for (var i = 0; i < 7; i++) {
          final c = DateTime(d.year, d.month, monday + i, d.hour, d.minute);
          if (weekdays.contains(c.weekday)) return c;
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
      RepeatUnit.week => switch ((n, weekdays.isEmpty)) {
          (1, true) => 'Every week',
          (1, false) => 'Every $_dayList',
          (_, true) => 'Every $n weeks',
          (_, false) => 'Every $n weeks on $_dayList',
        },
      RepeatUnit.month => n == 1 ? 'Every month' : 'Every $n months',
      RepeatUnit.year => n == 1 ? 'Every year' : 'Every $n years',
    };
    return fromCompletion ? '$base after done' : base;
  }

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String get _dayList => (weekdays.toList()..sort()).map((d) => _dayNames[d - 1]).join(', ');

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
  TaskCategory({required this.id, required this.name, List<String>? keywords, Map<String, dynamic>? extra})
      : keywords = keywords ?? [],
        extra = extra ?? {};

  /// Item 62: fields written by a newer version of the app that this one doesn't know. Kept
  /// and written back unchanged, so an older device never drops newer data when it syncs.
  final Map<String, dynamic> extra;

  static const _known = {'id', 'name', 'keywords'};

  final String id;
  String name;

  /// Words that always put a new task in this category.
  final List<String> keywords;

  factory TaskCategory.create(String name) =>
      TaskCategory(id: 'c${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}', name: name);

  Map<String, dynamic> toJson() => {...extra, 'id': id, 'name': name, if (keywords.isNotEmpty) 'keywords': keywords};

  factory TaskCategory.fromJson(Map<String, dynamic> j) => TaskCategory(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        keywords: [for (final k in j['keywords'] as List? ?? []) k as String],
        extra: unknownFields(j, _known),
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
    this.eventDays = 14,
    this.overdueMode = OverdueMode.off,
    this.overdueAt = 8 * 60,
    this.nudgeHours = 3,
    this.quietStart = 22 * 60,
    this.quietEnd = 7 * 60,
    this.weeklyReview = false,
    this.weeklyDay = DateTime.sunday,
    this.weeklyAt = 18 * 60,
    this.sort = ListSort.due,
    this.starredTop = true,
    this.showQuickFilters = true,
    List<KanbanStage>? stages,
    this.kanbanDone = KanbanDone.ask,
    this.kanbanHideFromList = false,
    Map<String, SkipRecord>? skips,
    DateTime? updatedAt,
    DateTime? orderUpdatedAt,
    DateTime? settingsUpdatedAt,
    Map<String, DateTime>? deleted,
    this.newestApp,
    Map<String, dynamic>? extra,
    Set<String>? hiddenEmails,
    this.starredDays = 30,
    this.starredAfter = StarredAfter.keep,
    this.starredLine = false,
  })  : active = active ?? [],
        hiddenEmails = hiddenEmails ?? {},
        extra = extra ?? {},
        archived = archived ?? [],
        deleted = deleted ?? {},
        categories = categories ?? [],
        collapsed = collapsed ?? {},
        templates = templates ?? [],
        done = done ?? {},
        skips = skips ?? {},
        stages = stages ?? KanbanStage.defaults(),
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

  /// Only show tasks with no due date or due within the next 30 days. Replaced by the
  /// "Next 30 days" quick filter in 1.4; still read so a device that had it on starts there.
  bool focusNext30;

  /// A notification once a week with last week's numbers and what's coming up.
  bool weeklyReview;

  /// Day of the week for it (DateTime.monday..sunday) and minutes after midnight.
  int weeklyDay;
  int weeklyAt;

  /// How the main list is ordered. A fresh install sorts by due date; older data keeps the
  /// hand-made order it had.
  ListSort sort;

  /// Starred tasks go first, whatever the sort.
  bool starredTop;

  /// Show the row of quick filter chips (All, Today, Next 7 days, ...) above the list.
  bool showQuickFilters;

  /// Kanban board columns, in order. The last one is the "done" end.
  final List<KanbanStage> stages;

  /// Whether moving a task into the last stage ticks it off too.
  KanbanDone kanbanDone;

  /// Leave board tasks out of the main list.
  bool kanbanHideFromList;

  KanbanStage? stage(String? id) => stages.where((s) => s.id == id).firstOrNull;

  /// Open tasks on the board.
  Iterable<Task> get boardTasks => active.where((t) => t.kanban);

  /// Repeating tasks moved on without being done, by [SkipRecord.key], for the statistics.
  final Map<String, SkipRecord> skips;

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

  /// How many days ahead to look in the calendar for events to make tasks from.
  int eventDays;

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

  /// Item 55: starred emails the user chose to hide from the Starred emails page.
  final Set<String> hiddenEmails;

  /// How far back the Starred emails page looks, in days; 0 for all of them.
  int starredDays;

  /// What happens to an email's star once it has been made into a task or attached to one.
  StarredAfter starredAfter;

  /// Show "N starred emails not yet tasks" at the top of the list.
  bool starredLine;

  /// The task an email (by Gmail id) was made into or attached to, if any.
  Task? taskForEmail(String id) => allTasks.where((t) => t.emails.any((e) => e.id == id)).firstOrNull;

  /// Item 62: the newest app version that has saved this data (as read; this device's own
  /// version is added when it is written). Newer than [currentAppVersion] means another
  /// device runs a newer Task Blocks and this one should be updated.
  String? newestApp;

  /// Item 62: top-level fields from a newer version that this one doesn't know; kept as they are.
  final Map<String, dynamic> extra;

  /// Another device has saved this data with a newer version of the app.
  bool get newerAppElsewhere => newestApp != null && compareVersions(newestApp!, currentAppVersion) > 0;

  static const _known = {
    'version', 'newestApp', 'hoursToRed', 'colourByDue', 'archiveKeepDays', 'categories',
    'groupByCategory', 'collapsed', 'focusNext30', 'weeklyReview', 'weeklyDay', 'weeklyAt', 'sort',
    'starredTop', 'showQuickFilters', 'stages', 'kanbanDone', 'kanbanHideFromList', 'skips',
    'defaultRemindBefore', 'templates', 'done', 'autoCategory', 'eventSuggest', 'eventCalendars',
    'dismissedEvents', 'eventDays', 'overdueMode', 'overdueAt', 'nudgeHours', 'quietStart', 'quietEnd',
    'updatedAt', 'orderUpdatedAt', 'settingsUpdatedAt', 'deleted', 'active', 'archived',
    'hiddenEmails', 'starredDays', 'starredAfter', 'starredLine',
  };

  Map<String, dynamic> toJson() => {
        ...extra,
        'version': 1,
        'newestApp': newerVersion(newestApp, currentAppVersion),
        'hoursToRed': hoursToRed,
        'colourByDue': colourByDue,
        'archiveKeepDays': archiveKeepDays,
        'categories': categories.map((c) => c.toJson()).toList(),
        'groupByCategory': groupByCategory,
        'collapsed': collapsed.toList(),
        'focusNext30': focusNext30,
        'weeklyReview': weeklyReview,
        'weeklyDay': weeklyDay,
        'weeklyAt': weeklyAt,
        'sort': sort.name,
        'starredTop': starredTop,
        'showQuickFilters': showQuickFilters,
        'stages': stages.map((s) => s.toJson()).toList(),
        'kanbanDone': kanbanDone.name,
        if (kanbanHideFromList) 'kanbanHideFromList': true,
        if (skips.isNotEmpty) 'skips': skips.map((k, v) => MapEntry(k, v.toJson())),
        'defaultRemindBefore': defaultRemindBefore,
        'templates': templates.map((t) => t.toJson()).toList(),
        'done': done.map((k, v) => MapEntry(k, v.toJson())),
        'autoCategory': autoCategory.name,
        'eventSuggest': eventSuggest.name,
        'eventCalendars': eventCalendars.toList(),
        'dismissedEvents': dismissedEvents.toList(),
        'eventDays': eventDays,
        'overdueMode': overdueMode.name,
        'overdueAt': overdueAt,
        'nudgeHours': nudgeHours,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        if (hiddenEmails.isNotEmpty) 'hiddenEmails': hiddenEmails.toList(),
        'starredDays': starredDays,
        'starredAfter': starredAfter.name,
        if (starredLine) 'starredLine': true,
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
        // Saved before sorting existed: keep the hand-made order.
        weeklyReview: j['weeklyReview'] as bool? ?? false,
        weeklyDay: (j['weeklyDay'] as num?)?.toInt() ?? DateTime.sunday,
        weeklyAt: (j['weeklyAt'] as num?)?.toInt() ?? 18 * 60,
        sort: _enum(ListSort.values, j['sort'], ListSort.manual),
        starredTop: j['starredTop'] as bool? ?? true,
        showQuickFilters: j['showQuickFilters'] as bool? ?? true,
        stages: j['stages'] is List
            ? [for (final s in j['stages'] as List) KanbanStage.fromJson(s as Map<String, dynamic>)]
            : null,
        kanbanDone: _enum(KanbanDone.values, j['kanbanDone'], KanbanDone.ask),
        kanbanHideFromList: j['kanbanHideFromList'] as bool? ?? false,
        skips: {
          for (final e in (j['skips'] as Map? ?? {}).entries)
            e.key as String: SkipRecord.fromJson(e.value as Map<String, dynamic>),
        },
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
        eventDays: (j['eventDays'] as num?)?.toInt() ?? 14,
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
        newestApp: j['newestApp'] as String?,
        hiddenEmails: {for (final e in j['hiddenEmails'] as List? ?? []) e as String},
        starredDays: (j['starredDays'] as num?)?.toInt() ?? 30,
        starredAfter: _enum(StarredAfter.values, j['starredAfter'], StarredAfter.keep),
        starredLine: j['starredLine'] as bool? ?? false,
        extra: unknownFields(j, _known),
      );
}

/// The version of this copy of the app (the newest entry in the changelog, which a test keeps
/// in step with pubspec.yaml).
String get currentAppVersion => releases.first.version;

/// Compares version names like "1.6.2" part by part: negative when [a] is older than [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('+').first.split('.')) int.tryParse(p.trim()) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < max(x.length, y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// The newer of two version names; null only when both are.
String? newerVersion(String? a, String? b) {
  if (a == null) return b;
  if (b == null) return a;
  return compareVersions(a, b) >= 0 ? a : b;
}

/// Item 62: the entries of [j] whose keys aren't in [known], i.e. what a newer version added.
Map<String, dynamic> unknownFields(Map<String, dynamic> j, Set<String> known) =>
    {for (final e in j.entries) if (!known.contains(e.key)) e.key: e.value};

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
  // Board moves from both copies, so a move made on either device is never lost.
  final moves = <String, Map<String, StageMove>>{};
  // The same for checklist steps on the board (item 56): task id → step id → moves.
  final stepMoves = <String, Map<String, Map<String, StageMove>>>{};
  for (final t in [...a.active, ...a.archived, ...b.active, ...b.archived]) {
    final seen = tasks[t.id];
    if (seen == null || t.updatedAt.isAfter(seen.updatedAt)) tasks[t.id] = t;
    if (t.moves.isNotEmpty) moves.putIfAbsent(t.id, () => {}).addAll({for (final m in t.moves) m.id: m});
    for (final st in t.steps) {
      if (st.moves.isEmpty) continue;
      stepMoves.putIfAbsent(t.id, () => {}).putIfAbsent(st.id, () => {}).addAll({for (final m in st.moves) m.id: m});
    }
  }
  // Copies, so this device's data isn't changed before the merge is accepted.
  final copied = <String>{};
  Task own(String id) {
    if (copied.add(id)) tasks[id] = Task.fromJson(tasks[id]!.toJson());
    return tasks[id]!;
  }

  moves.forEach((id, all) {
    final t = tasks[id]!;
    if (all.length == t.moves.length) return;
    final joined = own(id);
    joined.moves
      ..clear()
      ..addAll(all.values.toList()..sort((x, y) => x.at.compareTo(y.at)));
    final last = joined.moves.last;
    joined.kanban = last.toId != null;
    joined.stageId = last.toId ?? last.fromId ?? joined.stageId;
  });
  stepMoves.forEach((id, bySteps) {
    bySteps.forEach((stepId, all) {
      final st = tasks[id]!.steps.where((s) => s.id == stepId).firstOrNull;
      if (st == null || all.length == st.moves.length) return;
      final joined = own(id).steps.firstWhere((s) => s.id == stepId);
      joined.moves
        ..clear()
        ..addAll(all.values.toList()..sort((x, y) => x.at.compareTo(y.at)));
      final last = joined.moves.last;
      joined.stageId = last.toId ?? last.fromId ?? joined.stageId;
    });
  });
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

  final skips = <String, SkipRecord>{...a.skips, ...b.skips};

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
    weeklyReview: settingsFrom.weeklyReview,
    weeklyDay: settingsFrom.weeklyDay,
    weeklyAt: settingsFrom.weeklyAt,
    sort: settingsFrom.sort,
    starredTop: settingsFrom.starredTop,
    showQuickFilters: settingsFrom.showQuickFilters,
    stages: settingsFrom.stages,
    kanbanDone: settingsFrom.kanbanDone,
    kanbanHideFromList: settingsFrom.kanbanHideFromList,
    skips: skips,
    defaultRemindBefore: settingsFrom.defaultRemindBefore,
    templates: settingsFrom.templates,
    done: done,
    autoCategory: settingsFrom.autoCategory,
    eventSuggest: settingsFrom.eventSuggest,
    eventCalendars: settingsFrom.eventCalendars,
    dismissedEvents: {...a.dismissedEvents, ...b.dismissedEvents},
    eventDays: settingsFrom.eventDays,
    overdueMode: settingsFrom.overdueMode,
    overdueAt: settingsFrom.overdueAt,
    nudgeHours: settingsFrom.nudgeHours,
    quietStart: settingsFrom.quietStart,
    quietEnd: settingsFrom.quietEnd,
    settingsUpdatedAt: settingsFrom.settingsUpdatedAt,
    updatedAt: b.updatedAt.isAfter(a.updatedAt) ? b.updatedAt : a.updatedAt,
    orderUpdatedAt: orderFrom.orderUpdatedAt,
    deleted: deleted,
    newestApp: newerVersion(a.newestApp, b.newestApp),
    hiddenEmails: {...a.hiddenEmails, ...b.hiddenEmails},
    starredDays: settingsFrom.starredDays,
    starredAfter: settingsFrom.starredAfter,
    starredLine: settingsFrom.starredLine,
    // Fields only a newer version understands: keep them from both, the newer copy winning.
    extra: b.updatedAt.isAfter(a.updatedAt) ? {...a.extra, ...b.extra} : {...b.extra, ...a.extra},
  );
}

/// Item 55: what happens to a starred email's star after it is used for a task.
enum StarredAfter {
  keep('Keep the star'),
  unstar('Remove the star'),
  unstarLabel('Remove the star and add the label "Tasked"');

  const StarredAfter(this.label);
  final String label;
}
