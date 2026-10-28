import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dropbox.dart';
import 'home_widgets.dart';
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

  Directory? _dir;
  Timer? _uploadTimer;

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
    }
    if (_cleanArchive()) await _writeData();
    notifyListeners();
    await applyWidgetTicks();
    unawaited(reminders?.schedule(data));
    unawaited(widgets?.push(data));
    unawaited(sync());
  }

  /// Archives tasks that were ticked off on a home screen widget.
  Future<void> applyWidgetTicks() async {
    final ticks = await widgets?.takeCompleted() ?? const [];
    var any = false;
    for (final (id, at) in ticks) {
      final t = data.active.where((t) => t.id == id).firstOrNull;
      if (t == null) continue;
      complete(t, at: at);
      any = true;
    }
    if (any) notifyListeners();
  }

  Future<void> _writeData() async {
    if (_dir == null) return;
    await File('${_dir!.path}/tasks.json').writeAsString(jsonEncode(data.toJson()));
  }

  Future<void> saveDeviceSettings() async {
    if (_dir == null) return;
    await File('${_dir!.path}/device_settings.json').writeAsString(jsonEncode({
      'dropboxAppKey': dropboxAppKey,
      'dropboxRefreshToken': dropbox?.refreshToken,
    }));
  }

  /// Call after any change to [data]. Pass the [task] that changed, [order] if the
  /// active list's order changed, or [settings] if a setting changed.
  void changed({Task? task, bool order = false, bool settings = false}) {
    final now = DateTime.now().toUtc();
    data.updatedAt = now;
    if (order) data.orderUpdatedAt = now;
    if (settings) data.settingsUpdatedAt = now;
    task?.touch();
    _cleanArchive();
    notifyListeners();
    _writeData();
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
        if (remoteText == null || jsonEncode(data.toJson()) != jsonEncode(remote!.toJson())) {
          await db.upload(jsonEncode(data.toJson()));
        }
      } while (_syncAgain);
      _setStatus('Synced ${_now()}');
    } catch (e) {
      _setStatus('Sync failed: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
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

  void addTask(String title, {DateTime? due, String? categoryId}) {
    data.active.add(Task.create(title.trim())
      ..dueAt = due
      ..categoryId = categoryId);
    changed(order: true);
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
  /// released. Returns the new copy, if any, so an undo can remove it.
  Task? complete(Task t, {DateTime? at}) {
    final index = data.active.indexOf(t);
    data.active.remove(t);
    final now = at ?? DateTime.now();
    t.closedAt = now;
    data.archived.insert(0, t);
    _release(t.id, now);
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

  void moveCategory(int oldIndex, int newIndex) {
    data.categories.insert(newIndex, data.categories.removeAt(oldIndex));
    changed(settings: true);
  }

  /// Removes a category; its tasks become uncategorised.
  void deleteCategory(TaskCategory c) {
    data.categories.remove(c);
    for (final t in [...data.active, ...data.archived].where((t) => t.categoryId == c.id)) {
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
