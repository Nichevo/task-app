import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dropbox.dart';
import 'home_widgets.dart';
import 'input_parse.dart';
import 'models.dart';
import 'reminders.dart';

/// Holds the app's data, saves it to disk on every change and syncs it with Dropbox.
class AppStore extends ChangeNotifier {
  AppStore({this.reminders, this.widgets});

  AppData data = AppData();

  /// Due-date notifications; null in tests.
  final Reminders? reminders;

  /// Android home screen widgets; null in tests.
  final HomeWidgets? widgets;

  /// Device-only settings (not synced): Dropbox app key and sign-in.
  String dropboxAppKey = '';
  DropboxClient? dropbox;
  String syncStatus = 'Not connected';
  bool syncing = false;
  bool _syncAgain = false;
  DateTime? _lastSync;

  /// When the app last offered tasks from calendar events on its own (device-only).
  DateTime? eventPromptAt;

  Directory? _dir;
  Timer? _uploadTimer;
  Timer? _flushTimer;
  bool _dirty = false;

  Future<void> load() async {
    if (kIsWeb) return;
    _dir = await getApplicationSupportDirectory();
    final dataFile = File('${_dir!.path}/tasks.json');
    if (await dataFile.exists()) {
      data = AppData.fromJson(jsonDecode(await dataFile.readAsString()));
    }
    final settingsFile = File('${_dir!.path}/device_settings.json');
    if (await settingsFile.exists()) {
      final s = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
      dropboxAppKey = s['dropboxAppKey'] as String? ?? '';
      final refresh = s['dropboxRefreshToken'] as String?;
      if (dropboxAppKey.isNotEmpty && refresh != null) {
        dropbox = DropboxClient(dropboxAppKey, refreshToken: refresh);
        syncStatus = 'Connected';
      }
      eventPromptAt = DateTime.tryParse(s['eventPromptAt'] as String? ?? '');
    }
    if (_cleanArchive()) await _writeData();
    notifyListeners();
    await applyPending();
    unawaited(reminders?.schedule(data));
    unawaited(widgets?.push(data));
    unawaited(sync());
  }

  /// Where the app keeps its files; reminders use it to leave notes from the background.
  String? get dirPath => _dir?.path;

  /// Applies what happened while the app wasn't running: ticks, snoozes and new tasks from
  /// the home screen widgets, and Done / Snooze presses on notifications.
  Future<void> applyPending() async {
    var any = false;
    for (final (id, at) in await widgets?.takeCompleted() ?? const <(String, DateTime)>[]) {
      final t = data.task(id);
      if (t == null || t.closedAt != null) continue;
      complete(t, at: at);
      any = true;
    }
    for (final (taskId, stepId) in await widgets?.takeStepTicks() ?? const <(String, String)>[]) {
      final step = data.task(taskId)?.steps.where((s) => s.id == stepId).firstOrNull;
      if (step == null || step.done) continue;
      step.done = true;
      changed(task: data.task(taskId));
      any = true;
    }
    for (final a in await reminders?.takeActions(dirPath) ?? const <PendingAction>[]) {
      final t = data.task(a.taskId);
      if (t == null || t.closedAt != null) continue;
      if (a.action == 'done') {
        complete(t, at: a.at);
      } else {
        snooze(t, a.snoozeUntil!);
      }
      any = true;
    }
    for (final (id, until) in await widgets?.takeSnoozes() ?? const <(String, DateTime)>[]) {
      final t = data.task(id);
      if (t == null || t.closedAt != null) continue;
      snooze(t, until);
      any = true;
    }
    if (any) notifyListeners();
  }

  Future<void> _writeData() async {
    final dir = _dir;
    if (dir == null) return;
    // Write to a temporary file first so a crash mid-write can't corrupt the saved list.
    final tmp = File('${dir.path}/tasks.json.tmp');
    await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
    await tmp.rename('${dir.path}/tasks.json');
  }

  Future<void> saveDeviceSettings() async {
    if (_dir == null) return;
    await File('${_dir!.path}/device_settings.json').writeAsString(jsonEncode({
      'dropboxAppKey': dropboxAppKey,
      'dropboxRefreshToken': dropbox?.refreshToken,
      'eventPromptAt': eventPromptAt?.toIso8601String(),
    }));
  }

  /// Call after any change to [data]. Pass the [task] that changed, [order] if the
  /// active list's order changed, or [settings] if a setting changed.
  ///
  /// The screen updates at once; saving, reminders, widgets and the upload are done a
  /// moment later so typing in a task doesn't write the file on every key.
  void changed({Task? task, bool order = false, bool settings = false}) {
    final now = DateTime.now().toUtc();
    data.updatedAt = now;
    if (order) data.orderUpdatedAt = now;
    if (settings) data.settingsUpdatedAt = now;
    task?.touch();
    _cleanArchive();
    notifyListeners();
    // Nothing to save or push yet (before load, or in tests).
    if (_dir == null && reminders == null && widgets == null) return;
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), flush);
  }

  /// Saves and pushes any pending change now (e.g. when the app goes to the background).
  Future<void> flush() async {
    _flushTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    await _writeData();
    unawaited(reminders?.schedule(data));
    unawaited(widgets?.push(data));
    if (dropbox?.isConnected ?? false) {
      _uploadTimer?.cancel();
      _uploadTimer = Timer(const Duration(seconds: 2), sync);
    }
  }

  /// Deletes archived tasks older than the chosen limit. Returns whether any went.
  bool _cleanArchive() {
    if (data.archiveKeepDays <= 0) return false;
    final cutoff = DateTime.now().subtract(Duration(days: data.archiveKeepDays));
    final old = data.archived.where((t) => t.closedAt!.isBefore(cutoff)).toList();
    for (final t in old) {
      data.archived.remove(t);
      data.deleted[t.id] = DateTime.now().toUtc();
    }
    return old.isNotEmpty;
  }

  /// Syncs when the app comes to the front, unless it did so very recently.
  Future<void> syncIfStale() async {
    final last = _lastSync;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 30)) return;
    await sync();
  }

  /// Merges this device's tasks with the Dropbox copy and saves the result to both.
  Future<void> sync() async {
    final db = dropbox;
    if (db == null || !db.isConnected) return;
    if (syncing) {
      _syncAgain = true;
      return;
    }
    syncing = true;
    _setStatus('Syncing…');
    try {
      await flush();
      do {
        _syncAgain = false;
        final remoteText = await db.download();
        final remote = remoteText == null ? null : AppData.fromJson(jsonDecode(remoteText));
        final merged = remote == null ? data : mergeData(data, remote);
        final mergedText = jsonEncode(merged.toJson());
        if (mergedText != jsonEncode(data.toJson())) {
          data = merged;
          _cleanArchive();
          await _writeData();
          notifyListeners();
          unawaited(reminders?.schedule(data));
          unawaited(widgets?.push(data));
        }
        if (await _takeInbox(db)) await _writeData();
        final mine = jsonEncode(data.toJson());
        if (remoteText == null || mine != jsonEncode(remote!.toJson())) {
          await db.upload(mine);
        }
      } while (_syncAgain);
      _lastSync = DateTime.now();
      _setStatus('Synced ${_now()}');
    } catch (e) {
      _setStatus('Sync failed: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Adds any lines written to the inbox file in Dropbox as tasks, then empties it.
  Future<bool> _takeInbox(DropboxClient db) async {
    final text = await db.downloadInbox();
    if (text == null) return false;
    final lines = splitLines(text);
    if (lines.isEmpty) return false;
    for (final line in lines) {
      final p = parseInput(line, data, DateTime.now());
      data.active.add(Task.create(p.title)
        ..dueAt = p.due
        ..categoryId = p.categoryId);
    }
    data.updatedAt = data.orderUpdatedAt = DateTime.now().toUtc();
    await db.clearInbox();
    notifyListeners();
    return true;
  }

  Future<void> connectDropbox(DropboxClient client, String code) async {
    await client.finishAuth(code);
    dropbox = client;
    await saveDeviceSettings();
    await sync();
  }

  Future<void> disconnectDropbox() async {
    dropbox = null;
    _setStatus('Not connected');
    await saveDeviceSettings();
  }

  void _setStatus(String s) {
    syncStatus = s;
    notifyListeners();
  }

  static String _now() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // --- Task actions ---

  Task addTask(String title, {DateTime? due, String? categoryId, String notes = '', String? eventId}) {
    final t = Task.create(title.trim())
      ..dueAt = due
      ..categoryId = categoryId
      ..notes = notes
      ..eventId = eventId;
    data.active.add(t);
    changed(order: true);
    return t;
  }

  /// Adds one task per line, reading dates and categories out of each line.
  List<Task> addMany(Iterable<String> lines) {
    final added = <Task>[];
    for (final line in lines) {
      final p = parseInput(line, data, DateTime.now());
      if (p.title.isEmpty) continue;
      added.add(Task.create(p.title)
        ..dueAt = p.due
        ..categoryId = p.categoryId);
    }
    data.active.addAll(added);
    changed(order: true);
    return added;
  }

  /// [newIndex] is the position after the item has been removed.
  void reorder(int oldIndex, int newIndex) {
    data.active.insert(newIndex, data.active.removeAt(oldIndex));
    changed(order: true);
  }

  /// Applies a drag made on a filtered or grouped view: [visible] is the shown tasks in their
  /// new order. Tasks not shown keep their places. [moved] changed category to [categoryId].
  void reorderVisible(List<Task> visible, {Task? moved, String? categoryId}) {
    final shown = visible.toSet();
    final next = visible.iterator;
    final result = <Task>[
      for (final t in data.active)
        if (shown.contains(t)) (next..moveNext()).current else t,
    ];
    data.active
      ..clear()
      ..addAll(result);
    if (moved != null && moved.categoryId != categoryId) {
      moved.categoryId = categoryId;
      moved.touch();
    }
    changed(order: true);
  }

  /// Ticks a task off. A repeating task's next copy takes its place; tasks waiting on it are
  /// released, and a checklist step made from it is ticked. Returns the new copy, if any, so
  /// an undo can remove it.
  Task? complete(Task t, {DateTime? at}) {
    final index = data.active.indexOf(t);
    data.active.remove(t);
    final now = at ?? DateTime.now();
    t.closedAt = now;
    data.archived.insert(0, t);
    data.done[t.id] = DoneRecord.of(t, now);
    _release(t.id, now);
    for (final other in data.active) {
      for (final s in other.steps.where((s) => s.taskId == t.id && !s.done)) {
        s.done = true;
        other.touch();
      }
    }
    Task? next;
    if (t.repeat != null) {
      next = t.nextRepeat(now);
      data.active.insert(index.clamp(0, data.active.length), next);
    }
    changed(task: t, order: true);
    return next;
  }

  /// Undoes [complete].
  void uncomplete(Task t, int index, Task? spawned) {
    if (spawned != null) {
      data.active.remove(spawned);
      data.deleted[spawned.id] = DateTime.now().toUtc();
    }
    restore(t, index);
  }

  void _release(String id, DateTime now) {
    for (final w in data.active.where((w) => w.afterTaskId == id)) {
      w.readyAt = now;
      w.touch();
    }
  }

  /// Puts an archived task back at [index] in the active list (end if null).
  void restore(Task t, [int? index]) {
    data.archived.remove(t);
    t.closedAt = null;
    data.done.remove(t.id);
    data.active.insert((index ?? data.active.length).clamp(0, data.active.length), t);
    changed(task: t, order: true);
  }

  void delete(Task t) {
    data.active.remove(t);
    data.archived.remove(t);
    data.deleted[t.id] = DateTime.now().toUtc();
    _release(t.id, DateTime.now());
    changed(order: true);
  }

  /// Undoes [delete], putting an open task back at [index].
  void undelete(Task t, int index) {
    data.deleted.remove(t.id);
    if (t.closedAt == null) {
      data.active.insert(index.clamp(0, data.active.length), t);
    } else {
      data.archived
        ..add(t)
        ..sort((x, y) => y.closedAt!.compareTo(x.closedAt!));
    }
    changed(task: t, order: true);
  }

  void snooze(Task t, DateTime until) {
    t.snoozedUntil = until;
    changed(task: t);
  }

  void setDue(Task t, DateTime? due) {
    t.dueAt = due;
    changed(task: t);
  }

  // --- Checklists ---

  TaskStep addStep(Task t, String title) {
    final s = TaskStep.create(title);
    t.steps.add(s);
    changed(task: t);
    return s;
  }

  /// Returns true when this tick finished the whole checklist.
  bool toggleStep(Task t, TaskStep s) {
    s.done = !s.done;
    changed(task: t);
    return s.done && t.steps.every((x) => x.done);
  }

  void removeStep(Task t, TaskStep s) {
    t.steps.remove(s);
    changed(task: t);
  }

  void reorderSteps(Task t, int oldIndex, int newIndex) {
    t.steps.insert(newIndex, t.steps.removeAt(oldIndex));
    changed(task: t);
  }

  /// Turns a step into a full task of its own, placed just after [t] in the list. The step
  /// stays, linked to the new task, and ticks itself when that task is ticked off.
  Task stepToTask(Task t, TaskStep s) {
    final linked = Task.create(s.title)..categoryId = t.categoryId;
    final at = data.active.indexOf(t);
    data.active.insert(at < 0 ? data.active.length : at + 1, linked);
    s.taskId = linked.id;
    changed(task: t, order: true);
    return linked;
  }

  ChecklistTemplate saveTemplate(String name, List<String> steps) {
    final tpl = ChecklistTemplate.create(name, [for (final s in steps) s.trim()].where((s) => s.isNotEmpty).toList());
    data.templates.add(tpl);
    changed(settings: true);
    return tpl;
  }

  void applyTemplate(Task t, ChecklistTemplate tpl) {
    t.steps.addAll([for (final s in tpl.steps) TaskStep.create(s)]);
    changed(task: t);
  }

  void updateTemplate(ChecklistTemplate tpl, {String? name, List<String>? steps}) {
    if (name != null) tpl.name = name.trim();
    if (steps != null) {
      tpl.steps
        ..clear()
        ..addAll([for (final s in steps) s.trim()].where((s) => s.isNotEmpty));
    }
    changed(settings: true);
  }

  void deleteTemplate(ChecklistTemplate tpl) {
    data.templates.remove(tpl);
    changed(settings: true);
  }

  // --- Calendar events ---

  void dismissEvent(String eventId) {
    data.dismissedEvents.add(eventId);
    changed(settings: true);
  }

  // --- Categories ---

  TaskCategory addCategory(String name) {
    final c = TaskCategory.create(name.trim());
    data.categories.add(c);
    changed(settings: true);
    return c;
  }

  void renameCategory(TaskCategory c, String name) {
    c.name = name.trim();
    changed(settings: true);
  }

  void setKeywords(TaskCategory c, List<String> keywords) {
    c.keywords
      ..clear()
      ..addAll(keywords.map((k) => k.trim().toLowerCase()).where((k) => k.isNotEmpty));
    changed(settings: true);
  }

  void moveCategory(int oldIndex, int newIndex) {
    data.categories.insert(newIndex, data.categories.removeAt(oldIndex));
    changed(settings: true);
  }

  /// Removes a category; its tasks become uncategorised.
  void deleteCategory(TaskCategory c) {
    data.categories.remove(c);
    for (final t in data.allTasks.where((t) => t.categoryId == c.id)) {
      t.categoryId = null;
      t.touch();
    }
    changed(settings: true);
  }

  void toggleCollapsed(String categoryKey) {
    if (!data.collapsed.remove(categoryKey)) data.collapsed.add(categoryKey);
    changed(settings: true);
  }
}
