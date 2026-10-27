import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dropbox.dart';
import 'models.dart';
import 'reminders.dart';

/// Holds the app's data, saves it to disk on every change and syncs it with Dropbox.
class AppStore extends ChangeNotifier {
  AppStore({this.reminders});

  AppData data = AppData();

  /// Due-date notifications; null in tests.
  final Reminders? reminders;

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
    unawaited(reminders?.schedule(data.active));
    unawaited(sync());
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
    unawaited(reminders?.schedule(data.active));
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
          unawaited(reminders?.schedule(data.active));
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

  void addTask(String title) {
    data.active.add(Task.create(title.trim()));
    changed(order: true);
  }

  /// [newIndex] is the position after the item has been removed.
  void reorder(int oldIndex, int newIndex) {
    data.active.insert(newIndex, data.active.removeAt(oldIndex));
    changed(order: true);
  }

  void complete(Task t) {
    data.active.remove(t);
    t.closedAt = DateTime.now();
    data.archived.insert(0, t);
    changed(task: t, order: true);
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
}
