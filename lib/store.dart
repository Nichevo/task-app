import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dropbox.dart';
import 'models.dart';

/// Holds the app's data, saves it to disk on every change and syncs it with Dropbox.
class AppStore extends ChangeNotifier {
  AppData data = AppData();

  /// Device-only settings (not synced): Dropbox app key and sign-in.
  String dropboxAppKey = '';
  DropboxClient? dropbox;
  String syncStatus = 'Not connected';
  bool syncing = false;

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
    notifyListeners();
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

  /// Call after any change to [data].
  void changed() {
    data.updatedAt = DateTime.now().toUtc();
    notifyListeners();
    _writeData();
    if (dropbox?.isConnected ?? false) {
      _uploadTimer?.cancel();
      _uploadTimer = Timer(const Duration(seconds: 2), _upload);
    }
  }

  Future<void> _upload() async {
    try {
      await dropbox!.upload(jsonEncode(data.toJson()));
      _setStatus('Saved to Dropbox ${_now()}');
    } catch (e) {
      _setStatus('Upload failed: $e');
    }
  }

  /// Pull the Dropbox copy if it is newer than ours, otherwise push ours.
  Future<void> sync() async {
    final db = dropbox;
    if (db == null || !db.isConnected || syncing) return;
    syncing = true;
    _setStatus('Syncing…');
    try {
      final remoteText = await db.download();
      final remote = remoteText == null ? null : AppData.fromJson(jsonDecode(remoteText));
      if (remote != null && remote.updatedAt.isAfter(data.updatedAt)) {
        data = remote;
        await _writeData();
      } else if (remote == null || data.updatedAt.isAfter(remote.updatedAt)) {
        await db.upload(jsonEncode(data.toJson()));
      }
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
    changed();
  }

  /// [newIndex] is the position after the item has been removed.
  void reorder(int oldIndex, int newIndex) {
    data.active.insert(newIndex, data.active.removeAt(oldIndex));
    changed();
  }

  void complete(Task t) {
    data.active.remove(t);
    t.closedAt = DateTime.now();
    data.archived.insert(0, t);
    changed();
  }

  /// Puts an archived task back at [index] in the active list (end if null).
  void restore(Task t, [int? index]) {
    data.archived.remove(t);
    t.closedAt = null;
    data.active.insert(index ?? data.active.length, t);
    changed();
  }

  void delete(Task t) {
    data.active.remove(t);
    data.archived.remove(t);
    changed();
  }
}
