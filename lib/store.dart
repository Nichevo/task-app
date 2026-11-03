import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'dropbox.dart';
import 'google.dart';
import 'home_widgets.dart';
import 'inbox_files.dart';
import 'input_parse.dart';
import 'location.dart';
import 'models.dart';
import 'places.dart';
import 'reminders.dart';
import 'task_list.dart';

/// Holds the app's data, saves it to disk on every change and syncs it with Dropbox.
class AppStore extends ChangeNotifier {
  AppStore({this.reminders, this.widgets, this.location});

  AppData data = AppData();

  /// Due-date notifications; null in tests.
  final Reminders? reminders;

  /// Android home screen widgets; null in tests.
  final HomeWidgets? widgets;

  /// Location fixes for tasks; null in tests.
  final LocationRecorder? location;

  /// Save where tasks are added and ticked off (device-only: each phone allows location itself).
  bool recordLocation = false;

  /// Device-only settings (not synced): Dropbox app key and sign-in.
  String dropboxAppKey = '';
  DropboxClient? dropbox;
  String syncStatus = 'Not connected';
  bool syncing = false;
  bool _syncAgain = false;
  DateTime? _lastSync;

  /// Item 53: Google sign-in on this device (device-only, never synced): the OAuth client's id and
  /// secret, typed in Settings, and the signed-in client.
  String googleClientId = '';
  String googleClientSecret = '';
  GoogleClient? google;

  /// When the app last offered tasks from calendar events on its own (device-only).
  DateTime? eventPromptAt;

  /// The quick filter chip chosen above the list (device-only).
  QuickFilter quickFilter = QuickFilter.all;

  /// Item 60: the Matrix page's last filter on this device (category null = all, '' = none).
  QuickFilter matrixFilter = QuickFilter.all;
  String? matrixCategory;

  /// Kanban board on this device (item 56): every task's steps unfolded, and the lanes view.
  bool boardShowSteps = false;
  bool boardLanes = false;

  /// The app version whose "What's new" was last shown (device-only). Null on a fresh install
  /// until the first load, which counts as seen.
  String? seenVersion;

  /// Saved places for place reminders (device-only; copied to Dropbox's devices folder, item 69).
  final places = <Place>[];

  /// On arriving at a saved place, show one notification with that day's tasks (device-only).
  bool arrivalSummary = false;

  /// Set by [load] when there was saved data from before, so an update (not a fresh install)
  /// shows "What's new".
  bool hadData = false;

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
      hadData = true;
    }
    var filterSaved = false;
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
      recordLocation = s['recordLocation'] as bool? ?? false;
      final f = QuickFilter.values.where((f) => f.name == s['quickFilter']).firstOrNull;
      if (f != null) {
        quickFilter = f;
        filterSaved = true;
      }
      seenVersion = s['seenVersion'] as String?;
      places.addAll([for (final p in s['places'] as List? ?? []) ?Place.tryParse(p)]);
      arrivalSummary = s['arrivalSummary'] as bool? ?? false;
      boardShowSteps = s['boardShowSteps'] as bool? ?? false;
      boardLanes = s['boardLanes'] as bool? ?? false;
      matrixFilter = QuickFilter.values.where((f) => f.name == s['matrixFilter']).firstOrNull ?? QuickFilter.all;
      matrixCategory = s['matrixCategory'] as String?;
      deviceBackupChecked = s['deviceBackupChecked'] as bool? ?? false;
      googleClientId = s['googleClientId'] as String? ?? '';
      googleClientSecret = s['googleClientSecret'] as String? ?? '';
      final gRefresh = s['googleRefreshToken'] as String?;
      if (googleClientId.isNotEmpty && gRefresh != null) {
        google = GoogleClient(googleClientId, googleClientSecret,
            refreshToken: gRefresh, email: s['googleEmail'] as String?);
      }
    }
    // The old "only show the next 30 days" setting becomes the Next 30 days chip.
    if (!filterSaved && data.focusNext30) quickFilter = QuickFilter.month;
    if (_cleanArchive()) await _writeData();
    notifyListeners();
    await applyPending();
    await backupIfDue();
    unawaited(watchPlaces());
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
      _stepTicked(data.task(taskId)!, step);
      changed(task: data.task(taskId));
      any = true;
    }
    for (final a in await reminders?.takeActions(dirPath) ?? const <PendingAction>[]) {
      final t = data.task(a.taskId);
      if (t == null || t.closedAt != null) continue;
      if (a.action == 'done') {
        complete(t, at: a.at);
      } else if (a.action == 'skip') {
        if (t.repeat != null) skip(t, at: a.at);
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
      'recordLocation': recordLocation,
      'quickFilter': quickFilter.name,
      if (seenVersion != null) 'seenVersion': seenVersion,
      if (places.isNotEmpty) 'places': [for (final p in places) p.toJson()],
      if (arrivalSummary) 'arrivalSummary': true,
      if (boardShowSteps) 'boardShowSteps': true,
      if (boardLanes) 'boardLanes': true,
      if (matrixFilter != QuickFilter.all) 'matrixFilter': matrixFilter.name,
      if (matrixCategory != null) 'matrixCategory': matrixCategory,
      if (deviceBackupChecked) 'deviceBackupChecked': true,
      if (googleClientId.isNotEmpty) 'googleClientId': googleClientId,
      if (googleClientSecret.isNotEmpty) 'googleClientSecret': googleClientSecret,
      if (google?.refreshToken != null) 'googleRefreshToken': google!.refreshToken,
      if (google?.email != null) 'googleEmail': google!.email,
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
    unawaited(backupIfDue());
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
        // Item 54: the merge first, so a task another device already made from an email is known.
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
        if (await _takeInboxFolder(db)) await _writeData();
        if (await checkEmailTasks() > 0) await _writeData();
        await _deviceBackup(db);
        final mine = jsonEncode(data.toJson());
        if (remoteText == null || mine != jsonEncode(remote!.toJson())) {
          // Item 62: a newer version wrote the Dropbox copy; keep it before this one saves over it.
          if (remote != null && remote.newerAppElsewhere) await db.backup(remoteText!, DateTime.now());
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

  // --- Device settings backup (item 69) ---

  /// The kinds of device a backup can come from, as [deviceName] names them.
  static const deviceKinds = ['Android', 'iPhone or iPad', 'Mac', 'Windows'];

  static String deviceBackupPath(String kind) =>
      '${DropboxClient.devicesFolder}/${kind.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}.json';

  /// Whether this device has looked for its own backup since Dropbox was connected. Until it has,
  /// it never saves one, so a fresh install can't save its empty settings over the old ones.
  bool deviceBackupChecked = false;

  /// A backup from this kind of device found on the first sync, offered at the top of the list.
  DeviceBackup? restoreOffer;

  String? _lastDeviceBackup;

  /// The settings that stay on this device, as saved to Dropbox. Sign-ins are left out.
  Map<String, dynamic> deviceSettingsBackup() => {
        'recordLocation': recordLocation,
        'quickFilter': quickFilter.name,
        if (places.isNotEmpty) 'places': [for (final p in places) p.toJson()],
        'arrivalSummary': arrivalSummary,
        'boardShowSteps': boardShowSteps,
        'boardLanes': boardLanes,
        'matrixFilter': matrixFilter.name,
        if (matrixCategory != null) 'matrixCategory': matrixCategory,
        if (googleClientId.isNotEmpty) 'googleClientId': googleClientId,
        if (googleClientSecret.isNotEmpty) 'googleClientSecret': googleClientSecret,
      };

  /// On each sync: the first time, looks for this kind of device's backup and offers it; after
  /// that, saves this device's settings when they changed.
  Future<void> _deviceBackup(DropboxClient db) async {
    final path = deviceBackupPath(deviceName);
    if (!deviceBackupChecked) {
      final found = DeviceBackup.tryParse(await db.downloadPath(path));
      deviceBackupChecked = true;
      if (found != null && jsonEncode(found.settings) != jsonEncode(deviceSettingsBackup())) {
        restoreOffer = found;
        // Not saved yet: the offer must not be overwritten before it is answered.
        deviceBackupChecked = false;
        notifyListeners();
        return;
      }
      await saveDeviceSettings();
    }
    if (restoreOffer != null) return;
    final settings = deviceSettingsBackup();
    final text = jsonEncode(settings);
    if (text == _lastDeviceBackup) return;
    await db.uploadPath(
        path,
        jsonEncode({
          'device': deviceName,
          'app': currentAppVersion,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'settings': settings,
        }));
    _lastDeviceBackup = text;
  }

  /// The device backups in Dropbox, newest first, for Settings → Restore.
  Future<List<DeviceBackup>> deviceBackups() async {
    final db = dropbox;
    if (db == null) return [];
    final out = <DeviceBackup>[];
    for (final kind in {...deviceKinds, deviceName}) {
      final b = DeviceBackup.tryParse(await db.downloadPath(deviceBackupPath(kind)));
      if (b != null) out.add(b);
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  /// Puts [b]'s settings on this device. The Google client is only taken when this device has
  /// none, so restoring never breaks a working sign-in.
  Future<void> restoreDeviceSettings(DeviceBackup b) async {
    final s = b.settings;
    recordLocation = s['recordLocation'] as bool? ?? recordLocation;
    quickFilter = QuickFilter.values.where((f) => f.name == s['quickFilter']).firstOrNull ?? quickFilter;
    if (s['places'] is List) {
      places
        ..clear()
        ..addAll([for (final p in s['places'] as List) ?Place.tryParse(p)]);
    }
    arrivalSummary = s['arrivalSummary'] as bool? ?? arrivalSummary;
    boardShowSteps = s['boardShowSteps'] as bool? ?? boardShowSteps;
    boardLanes = s['boardLanes'] as bool? ?? boardLanes;
    matrixFilter = QuickFilter.values.where((f) => f.name == s['matrixFilter']).firstOrNull ?? matrixFilter;
    matrixCategory = s['matrixCategory'] as String? ?? matrixCategory;
    if (googleClientId.isEmpty && google == null) {
      googleClientId = s['googleClientId'] as String? ?? '';
      googleClientSecret = s['googleClientSecret'] as String? ?? '';
    }
    restoreOffer = null;
    deviceBackupChecked = true;
    await saveDeviceSettings();
    notifyListeners();
    unawaited(watchPlaces());
    final db = dropbox;
    if (db != null) {
      try {
        await _deviceBackup(db);
      } catch (_) {
        // Saved on the next sync.
      }
    }
  }

  /// "Not now" on the offer: this device's own settings are saved from the next sync on.
  Future<void> dismissRestoreOffer() async {
    restoreOffer = null;
    deviceBackupChecked = true;
    await saveDeviceSettings();
    notifyListeners();
  }

  /// Item 48A: why the inbox folder can't be read (a Dropbox permission missing), or null.
  String? inboxFolderNote;

  /// Adds the tasks in each .json file in Dropbox's inbox/ folder, then deletes just those files.
  /// A file that isn't a task file goes to inbox/failed. Returns whether anything was added.
  Future<bool> _takeInboxFolder(DropboxClient db) async {
    List<String> files;
    try {
      files = await db.inboxFiles();
      inboxFolderNote = null;
    } on DropboxException catch (e) {
      if (!'$e'.contains('missing_scope')) rethrow;
      inboxFolderNote = 'To use the inbox folder, tick files.metadata.read on the Dropbox app\'s Permissions tab, '
          'then disconnect and connect Dropbox again.';
      return false;
    }
    var any = false;
    for (final path in files) {
      final text = await db.downloadPath(path);
      if (text == null) continue;
      List<Task> added;
      try {
        added = addInboxFile(data, text, DateTime.now());
        added.forEach(_boardByCategory);
      } catch (e) {
        // Not a task file (bad JSON, no title, wrong types): set it aside, don't retry forever.
        debugPrint('inbox $path: $e');
        await db.moveToFailed(path);
        continue;
      }
      any = any || added.isNotEmpty;
      await db.delete(path);
    }
    if (any) {
      notifyListeners();
      unawaited(reminders?.schedule(data));
      unawaited(widgets?.push(data));
    }
    return any;
  }

  /// Adds any lines written to the inbox file in Dropbox as tasks, then empties it.
  Future<bool> _takeInbox(DropboxClient db) async {
    final text = await db.downloadInbox();
    if (text == null) return false;
    final lines = splitLines(text);
    if (lines.isEmpty) return false;
    for (final line in lines) {
      final p = parseInput(line, data, DateTime.now());
      final t = Task.create(p.title, source: TaskSource.inbox)
        ..dueAt = p.due
        ..categoryId = p.categoryId;
      data.active.add(t);
      _applyNew(t, box: p.box, board: p.board, star: p.star);
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
    deviceBackupChecked = false;
    restoreOffer = null;
    _lastDeviceBackup = null;
    _setStatus('Not connected');
    await saveDeviceSettings();
  }

  /// Item 53: signs in to Google with the client id and secret from Settings.
  Future<void> connectGoogle(Future<void> Function(Uri url) open, {GoogleClient? client}) async {
    final g = client ?? GoogleClient(googleClientId.trim(), googleClientSecret.trim());
    await g.signIn(open);
    google = g;
    await saveDeviceSettings();
    notifyListeners();
  }

  Future<void> disconnectGoogle() async {
    final g = google;
    google = null;
    await saveDeviceSettings();
    notifyListeners();
    await g?.signOut();
  }

  /// Google stopped accepting this device's sign-in; forget it so Settings offers Sign in.
  Future<void> googleSignedOut() async {
    google = null;
    await saveDeviceSettings();
    notifyListeners();
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

  /// [source] says how it got here (a [TaskSource] name).
  Task addTask(String title,
      {DateTime? due,
      String? categoryId,
      String notes = '',
      String? eventId,
      String source = TaskSource.typed,
      MatrixBox? box,
      bool board = false,
      bool star = false,
      KanbanStage? stage}) {
    final t = Task.create(title.trim(), source: source)
      ..dueAt = due
      ..categoryId = categoryId
      ..notes = notes
      ..eventId = eventId;
    data.active.add(t);
    _applyNew(t, box: box, board: board, star: star, stage: stage);
    changed(order: true);
    _locate([t]);
    return t;
  }

  /// A new task from a typed or sent line: what the quick-add words asked for (item 64), and the
  /// board if its category goes there by default (item 67).
  /// [stage] puts it straight into that stage (the + on a board column).
  void _applyNew(Task t, {MatrixBox? box, bool board = false, bool star = false, KanbanStage? stage}) {
    if (box != null) t.matrixBox = box.id;
    if (star) t.starred = true;
    if (stage != null || board) {
      setOnBoard(t, true, stage: stage ?? data.stages.firstOrNull);
    } else {
      _boardByCategory(t);
    }
  }

  /// Item 67: puts [t] on the board when its category says so (it never takes it off).
  void _boardByCategory(Task t) {
    final c = data.category(t.categoryId);
    if (c == null || !c.boardByDefault || t.kanban || t.closedAt != null) return;
    if (c.stepsOnBoard) t.stepsOnBoard = true;
    setOnBoard(t, true, stage: data.stage(c.boardStage) ?? data.stages.firstOrNull);
  }

  /// Changes a task's category, putting it on the board if the new category goes there (item 67).
  void setCategory(Task t, String? categoryId) {
    t.categoryId = categoryId;
    _boardByCategory(t);
    changed(task: t);
  }

  /// Item 67: the open tasks in [c] not on the board yet, for "Put them on the board now?".
  List<Task> offBoardIn(TaskCategory c) => [for (final t in data.active) if (t.categoryId == c.id && !t.kanban) t];

  /// Puts every open task in [c] on the board (when its default is first turned on).
  void boardAllIn(TaskCategory c) {
    for (final t in offBoardIn(c)) {
      _boardByCategory(t);
    }
  }

  /// Adds one task per line, reading dates and categories out of each line.
  List<Task> addMany(Iterable<String> lines, {String source = TaskSource.paste}) {
    final added = <Task>[];
    for (final line in lines) {
      final p = parseInput(line, data, DateTime.now());
      if (p.title.isEmpty) continue;
      final t = Task.create(p.title, source: source)
        ..dueAt = p.due
        ..categoryId = p.categoryId;
      data.active.add(t);
      _applyNew(t, box: p.box, board: p.board, star: p.star);
      added.add(t);
    }
    changed(order: true);
    _locate(added);
    return added;
  }

  /// Turns location recording on or off; turning it on asks for access. False if refused.
  Future<bool> setRecordLocation(bool on) async {
    if (on && !(await location?.requestAccess() ?? false)) return false;
    recordLocation = on;
    notifyListeners();
    await saveDeviceSettings();
    return true;
  }

  /// Saves the current location on [tasks] as where they were added, or ([done]) ticked off.
  /// Runs in the background; the task is saved again once the fix arrives.
  Future<void> _locate(List<Task> tasks, {bool done = false}) async {
    final loc = location;
    if (!recordLocation || loc == null || tasks.isEmpty) return;
    final point = await loc.current();
    if (point == null) return;
    for (final t in tasks) {
      // Skip if it was deleted, or reopened, in the meantime.
      if (data.task(t.id) == null || done != (t.closedAt != null)) continue;
      if (done) {
        t.doneWhere = point;
      } else {
        t.addedWhere = point;
      }
      changed(task: t);
    }
  }

  /// Saves the current location on a board move, when location recording is on.
  Future<void> _locateMove(Task t, StageMove m, [List<StageMove>? list]) async {
    final loc = location;
    if (!recordLocation || loc == null) return;
    final point = await loc.current();
    if (point == null || data.task(t.id) == null || !(list ?? t.moves).contains(m)) return;
    m.where = point;
    changed(task: t);
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
    // A board task ticked off from anywhere ends in the last stage.
    final last = data.stages.lastOrNull;
    if (t.kanban && last != null && t.stageId != last.id) _move(t, last, MoveHow.done, at: now, locate: false);
    t.closedAt = now;
    data.archived.insert(0, t);
    data.done[t.id] = DoneRecord.of(t, now);
    _release(t.id, now);
    for (final other in data.active) {
      for (final s in other.steps.where((s) => s.taskId == t.id && !s.done)) {
        s.done = true;
        _stepTicked(other, s);
        other.touch();
      }
    }
    Task? next;
    if (t.repeat != null) {
      next = t.nextRepeat(now);
      // The next one goes back on the board at the start.
      if (t.kanban && data.stages.isNotEmpty) {
        _move(next, data.stages.first, MoveHow.repeat, at: now, locate: false);
        if (next.stepsOnBoard) _stepsOn(next, MoveHow.repeat, at: now);
      }
      data.active.insert(index.clamp(0, data.active.length), next);
    }
    changed(task: t, order: true);
    // Only when ticked off just now: a tick made earlier on a widget or notification and picked
    // up later would get the wrong place.
    if (at == null || DateTime.now().difference(at).inMinutes < 2) _locate([t], done: true);
    return next;
  }

  /// Moves a repeating task on to its next due date without ticking it off: same task, checklist
  /// unticked, snooze cleared. The skip is recorded for the statistics. Returns how to undo it.
  VoidCallback skip(Task t, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final oldDue = t.dueAt, oldSnooze = t.snoozedUntil;
    final oldSteps = {for (final st in t.steps) st.id: st.done};
    final oldMoves = {for (final st in t.steps) st.id: st.moves.length};
    final record = SkipRecord(taskId: t.id, series: t.series, at: now, due: oldDue, missed: missedCycles(t, now));
    data.skips[record.key] = record;
    t.dueAt = t.repeat!.nextDue(due: oldDue, completedAt: now);
    t.snoozedUntil = null;
    final first = data.stages.firstOrNull;
    for (final st in t.steps) {
      st.done = false;
      // Steps on the board start again in the first stage, like a new repeat.
      if (first != null && t.boardSteps.contains(st) && st.stageId != first.id) {
        _moveStep(t, st, first, MoveHow.repeat, at: now, locate: false);
      }
    }
    changed(task: t);
    return () {
      data.skips.remove(record.key);
      t.dueAt = oldDue;
      t.snoozedUntil = oldSnooze;
      for (final st in t.steps) {
        st.done = oldSteps[st.id] ?? st.done;
        final n = oldMoves[st.id];
        if (n != null && st.moves.length > n) {
          st.moves.removeRange(n, st.moves.length);
          st.stageId = st.moves.lastOrNull?.toId ?? st.stageId;
        }
      }
      changed(task: t);
    };
  }

  // --- Places (item 33) ---

  /// Hands the saved places to Android to watch. False when Android refused (no "all the time"
  /// location access yet).
  Future<bool> watchPlaces() => PlaceReminders.watch(places, arrivalSummary: arrivalSummary, dir: dirPath);

  /// Saves the current location as a place. Null when the location can't be had.
  Future<Place?> addPlaceHere(String name, {int radius = 150}) async {
    final loc = location;
    if (loc == null || !await loc.requestAccess()) return null;
    final here = await loc.current();
    if (here == null) return null;
    final p = Place.create(name, here.lat, here.lng, radius: radius);
    places.add(p);
    await _placesChanged();
    return p;
  }

  /// Renames a place; tasks reminding at it follow the new name.
  Future<void> updatePlace(Place p, {String? name, int? radius}) async {
    if (name != null && name.trim().isNotEmpty && name.trim() != p.name) {
      for (final t in data.active.where((t) => t.place == p.name)) {
        t.place = name.trim();
        changed(task: t);
      }
      p.name = name.trim();
    }
    if (radius != null) p.radius = radius;
    await _placesChanged();
  }

  /// Removes a place from this phone. Tasks keep the name (another phone may have the place).
  Future<void> deletePlace(Place p) async {
    places.remove(p);
    await _placesChanged();
  }

  Future<void> setArrivalSummary(bool on) async {
    arrivalSummary = on;
    await _placesChanged();
  }

  Future<void> _placesChanged() async {
    notifyListeners();
    await saveDeviceSettings();
    await watchPlaces();
  }

  // --- Backups (item 46) ---

  static const backupDays = 7;

  Directory? get _backupDir => _dir == null ? null : Directory('${_dir!.path}/backups');

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Saved backups, newest first.
  Future<List<File>> backups() async {
    final dir = _backupDir;
    if (dir == null || !await dir.exists()) return [];
    final files = await dir.list().where((f) => f is File && f.path.endsWith('.json')).cast<File>().toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Writes today's backup if there isn't one yet, and deletes those older than [backupDays].
  Future<void> backupIfDue() async {
    final dir = _backupDir;
    if (dir == null) return;
    try {
      await dir.create(recursive: true);
      final today = File('${dir.path}/tasks-${_day(DateTime.now())}.json');
      if (!await today.exists()) await today.writeAsString(jsonEncode(data.toJson()), flush: true);
      final cutoff = 'tasks-${_day(DateTime.now().subtract(const Duration(days: backupDays)))}';
      for (final f in await backups()) {
        final name = f.uri.pathSegments.last;
        if (name.compareTo(cutoff) < 0) await f.delete();
      }
    } catch (e) {
      debugPrint('backup: $e');
    }
  }

  /// The whole of the current data as backup text (for "Save a backup file").
  String backupText() => jsonEncode(data.toJson());

  /// Replaces everything with a backup ([text] is a saved tasks.json). The current data is kept
  /// as a backup first. So the restore wins over Dropbox, every restored task counts as just
  /// edited and tasks not in the backup count as deleted. Throws if the text isn't a backup.
  Future<void> restoreBackup(String text) async {
    final restored = AppData.fromJson(jsonDecode(text) as Map<String, dynamic>);
    final dir = _backupDir;
    if (dir != null) {
      await dir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().substring(11, 19).replaceAll(':', '');
      await File('${dir.path}/tasks-${_day(DateTime.now())}-before-restore-$stamp.json').writeAsString(backupText());
    }
    final now = DateTime.now().toUtc();
    final keep = {for (final t in restored.allTasks) t.id};
    for (final t in data.allTasks) {
      if (!keep.contains(t.id)) restored.deleted[t.id] = now;
    }
    for (final t in restored.allTasks) {
      restored.deleted.remove(t.id);
      t.updatedAt = now;
    }
    restored.updatedAt = restored.orderUpdatedAt = restored.settingsUpdatedAt = now;
    data = restored;
    _dirty = true;
    notifyListeners();
    await flush();
  }

  // --- Kanban board (item 52) ---

  /// Name of this kind of device, saved with each board move.
  static String get deviceName {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iPhone or iPad';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows';
    return Platform.operatingSystem;
  }

  /// Records a move and puts the task in [to] (off the board when null). Every board change
  /// goes through here.
  StageMove _move(Task t, KanbanStage? to, String how, {DateTime? at, String? note, bool locate = true}) {
    final from = t.kanban ? data.stage(t.stageId) : null;
    final m = StageMove.create(from: from, to: to, at: at ?? DateTime.now(), how: how, device: deviceName, note: note);
    t.moves.add(m);
    t.kanban = to != null;
    if (to != null) t.stageId = to.id;
    if (locate) unawaited(_locateMove(t, m));
    return m;
  }

  /// Moves [t] to [to] and saves. Returns true when it went into the last stage, so the screen
  /// can apply the "tick it off too" rule. Nothing happens if it is already there.
  bool moveToStage(Task t, KanbanStage to, {required String how, String? note}) {
    if (t.kanban && t.stageId == to.id) return false;
    _move(t, to, how, note: note);
    changed(task: t);
    return to.id == data.stages.lastOrNull?.id;
  }

  /// Puts [t] on the board (in the stage it was last in, else the first) or takes it off.
  /// Its history is kept either way.
  void setOnBoard(Task t, bool on, {KanbanStage? stage, String how = MoveHow.added}) {
    if (on == t.kanban || data.stages.isEmpty) return;
    if (on) {
      _move(t, stage ?? data.stage(t.stageId) ?? data.stages.first, how);
      if (t.stepsOnBoard) _stepsOn(t, how);
    } else {
      _move(t, null, MoveHow.removed);
      _stepsOff(t);
    }
    changed(task: t);
  }

  // --- Steps on the board (item 56) ---

  /// Records a move of one checklist step and puts it in [to] (off the board when null).
  StageMove _moveStep(Task t, TaskStep s, KanbanStage? to, String how, {DateTime? at, String? note, bool locate = true}) {
    final from = s.placed ? data.stage(s.stageId) : null;
    final m = StageMove.create(from: from, to: to, at: at ?? DateTime.now(), how: how, device: deviceName, note: note);
    s.moves.add(m);
    if (to != null) s.stageId = to.id;
    if (locate) unawaited(_locateMove(t, m, s.moves));
    return m;
  }

  /// Puts every step of [t] that isn't on the board yet into its stage: where it was before,
  /// the last stage if it is ticked, otherwise the first.
  void _stepsOn(Task t, String how, {DateTime? at}) {
    if (data.stages.isEmpty) return;
    final last = data.stages.last;
    for (final s in t.steps) {
      if (s.placed) continue;
      final before = data.stage(s.stageId);
      final to = s.done ? last : (before == null || before.id == last.id ? data.stages.first : before);
      _moveStep(t, s, to, how, at: at, locate: false);
    }
  }

  void _stepsOff(Task t) {
    for (final s in t.steps.where((s) => s.placed)) {
      _moveStep(t, s, null, MoveHow.removed, locate: false);
    }
  }

  /// The task page's "Steps on the board too" switch.
  void setStepsOnBoard(Task t, bool on) {
    if (t.stepsOnBoard == on) return;
    t.stepsOnBoard = on;
    if (t.kanban) on ? _stepsOn(t, MoveHow.added) : _stepsOff(t);
    changed(task: t);
  }

  /// Moves one step to [to]. Into the last stage ticks it; out of it unticks it. Returns true
  /// when that finished the whole checklist.
  bool moveStepToStage(Task t, TaskStep s, KanbanStage to, {required String how, String? note}) {
    if (s.placed && s.stageId == to.id) return false;
    _moveStep(t, s, to, how, note: note);
    final last = to.id == data.stages.lastOrNull?.id;
    if (last != s.done) s.done = last;
    changed(task: t);
    return last && t.steps.every((x) => x.done);
  }

  /// Keeps a board step's stage in step with its tick box.
  void _stepTicked(Task t, TaskStep s) {
    if (!t.boardSteps.contains(s) || data.stages.isEmpty) return;
    final last = data.stages.last;
    if (s.done && s.stageId != last.id) {
      _moveStep(t, s, last, MoveHow.done, locate: false);
    } else if (!s.done && s.stageId == last.id) {
      final back = s.moves.isEmpty ? null : data.stage(s.moves.last.fromId);
      _moveStep(t, s, back == null || back.id == last.id ? data.stages.first : back, MoveHow.reopened, locate: false);
    }
  }

  /// Ticks every open step of [t] (moving board steps to the last stage).
  void tickAllSteps(Task t) {
    for (final s in t.steps.where((s) => !s.done)) {
      s.done = true;
      _stepTicked(t, s);
    }
    changed(task: t);
  }

  /// A new task straight into [stage] from the + on a board column.
  Task addToStage(String title, KanbanStage stage) {
    final p = parseInput(title, data, DateTime.now());
    return addTask(p.title,
        due: p.due, categoryId: p.categoryId, source: TaskSource.kanban, box: p.box, star: p.star, stage: stage);
  }

  KanbanStage addStage(String name) {
    final s = KanbanStage.create(name);
    data.stages.add(s);
    changed(settings: true);
    return s;
  }

  void updateStage(KanbanStage s, {String? name, int? colour, bool clearColour = false, int? limit, bool clearLimit = false}) {
    if (name != null && name.trim().isNotEmpty) s.name = name.trim();
    if (colour != null || clearColour) s.colour = colour;
    if (limit != null || clearLimit) s.limit = limit;
    changed(settings: true);
  }

  void moveStage(int oldIndex, int newIndex) {
    data.stages.insert(newIndex, data.stages.removeAt(oldIndex));
    changed(settings: true);
  }

  /// Removes a stage. Open board tasks in it are moved to [moveTo] (a recorded move); tasks
  /// taken off the board will go back to [moveTo] instead.
  void deleteStage(KanbanStage s, KanbanStage moveTo) {
    for (final t in data.active.where((t) => t.stageId == s.id).toList()) {
      if (t.kanban) {
        _move(t, moveTo, MoveHow.stageRemoved, locate: false);
      } else {
        t.stageId = moveTo.id;
      }
      changed(task: t);
    }
    for (final t in data.active) {
      for (final st in t.steps.where((st) => st.stageId == s.id)) {
        if (st.placed) {
          _moveStep(t, st, moveTo, MoveHow.stageRemoved, locate: false);
        } else {
          st.stageId = moveTo.id;
        }
        changed(task: t);
      }
    }
    data.stages.remove(s);
    changed(settings: true);
  }

  /// The board's Show steps and Lanes buttons, remembered on this device.
  void setBoardView({bool? showSteps, bool? lanes}) {
    boardShowSteps = showSteps ?? boardShowSteps;
    boardLanes = lanes ?? boardLanes;
    notifyListeners();
    saveDeviceSettings();
  }

  /// Picks a quick filter chip and remembers it on this device.
  void setQuickFilter(QuickFilter f) {
    quickFilter = f;
    notifyListeners();
    saveDeviceSettings();
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
    // Back to the stage it was in before it reached the last one.
    if (t.kanban && t.moves.isNotEmpty && t.stageId == data.stages.lastOrNull?.id) {
      final back = data.stage(t.moves.last.fromId) ?? data.stages.first;
      if (back.id != t.stageId) _move(t, back, MoveHow.reopened, locate: false);
    }
    t.closedAt = null;
    t.doneWhere = null;
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
    if (t.boardSteps.isNotEmpty && data.stages.isNotEmpty) _moveStep(t, s, data.stages.first, MoveHow.added, locate: false);
    changed(task: t);
    return s;
  }

  /// Returns true when this tick finished the whole checklist.
  bool toggleStep(Task t, TaskStep s) {
    s.done = !s.done;
    _stepTicked(t, s);
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
    final linked = Task.create(s.title, source: TaskSource.step)..categoryId = t.categoryId;
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

  // --- Matrix (item 60) ---

  /// Puts [t] in box [b], or takes it off the matrix when null.
  void setBox(Task t, MatrixBox? b) {
    t.matrixBox = b?.id;
    changed(task: t);
  }

  void setWaitingOn(Task t, String? text) {
    t.waitingOn = text == null || text.trim().isEmpty ? null : text.trim();
    changed(task: t);
  }

  /// Item 60 hint: in a not-urgent box but due within the days set in Settings.
  bool looksUrgent(Task t, DateTime now) {
    final b = MatrixBox.byId(t.matrixBox), due = t.dueAt;
    if (b == null || b.urgent || due == null || data.urgentDays <= 0) return false;
    return due.isBefore(DateTime(now.year, now.month, now.day + data.urgentDays + 1));
  }

  // --- Email to tasks (item 54) ---

  /// Emails that asked to be tasks but were left out (sender not allowed, or failed Gmail's
  /// sender check), from the last check. Device-only; rebuilt on each check.
  final ignoredEmails = <IgnoredEmail>[];

  /// Why the last email check didn't work, or null.
  String? emailTasksNote;

  DateTime? _emailCheckedAt;
  bool _checkingEmail = false;

  /// "Task" at the start of a subject, with an optional ":" or "-" after it.
  static final _taskPrefix = RegExp(r'^\s*task\b\s*[:\-–—]?\s*', caseSensitive: false);

  /// Looks in Gmail for emails that should become tasks: from an allowed sender, passing
  /// Gmail's sender check, and with a subject starting "Task" or the label "Task". Each becomes a
  /// task (source Email) and is labelled "Tasked" (the "Task" label comes off). Checked at most
  /// every 2 minutes unless [force]. Returns how many tasks were added.
  Future<int> checkEmailTasks({bool force = false}) async {
    final g = google;
    if (g == null || !data.emailTasks || _checkingEmail) return 0;
    final last = _emailCheckedAt;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 2)) return 0;
    _checkingEmail = true;
    _emailCheckedAt = DateTime.now();
    var added = 0;
    try {
      final tasked = await g.labelId('Tasked');
      final taskLabel = await g.labelId('Task');
      final ids = await g.search('newer_than:14d -label:tasked (subject:task OR label:task)', max: 50);
      final ignored = <IgnoredEmail>[];
      for (final id in ids) {
        if (data.taskForEmail(id) != null || data.allTasks.any((t) => t.sourceRef == id)) continue;
        final m = await g.message(id, checkSender: true);
        final bySubject = _taskPrefix.hasMatch(m.subject);
        if (!bySubject && !m.labels.contains(taskLabel)) continue;
        // Sent from this very account (it's in Sent): Gmail itself is the check.
        final own = m.labels.contains('SENT') && m.address == g.email?.toLowerCase();
        String? why;
        if (!data.senderAllowed(m.address)) {
          why = 'Not on your allowed list';
        } else if (!own && !m.senderVerified) {
          why = "Failed Gmail's sender check";
        }
        if (why != null) {
          ignored.add(IgnoredEmail(m, why));
          continue;
        }
        final subject = m.subject.replaceFirst(_taskPrefix, '').trim();
        final p = parseInput(subject.isEmpty ? '(no subject)' : subject, data, DateTime.now());
        final t = addTask(p.title,
            due: p.due, categoryId: p.categoryId, source: TaskSource.email, box: p.box, board: p.board, star: p.star)
          ..sourceRef = id;
        t.emails.add(emailOf(m));
        changed(task: t);
        added++;
        try {
          await g.modify(id, add: [tasked], remove: [if (m.labels.contains(taskLabel)) taskLabel]);
        } catch (e) {
          debugPrint('label swap: $e');
        }
      }
      ignoredEmails
        ..clear()
        ..addAll(ignored);
      emailTasksNote = null;
    } on GoogleException catch (e) {
      emailTasksNote = '$e';
      if (e.signedOut) await googleSignedOut();
    } catch (e) {
      emailTasksNote = 'Could not check Gmail: $e';
    } finally {
      _checkingEmail = false;
      notifyListeners();
    }
    return added;
  }

  /// "Allow this sender" on an ignored email: adds the address and checks again.
  Future<void> allowSender(String address) async {
    final a = address.trim().toLowerCase();
    if (a.isEmpty || data.senderAllowed(a)) return;
    data.allowedSenders.add(a);
    changed(settings: true);
    await checkEmailTasks(force: true);
  }

  // --- Starred emails (item 55) ---

  /// A new task made from a starred email, with the email kept on it.
  Task addTaskFromEmail(GmailMessage m,
      {required String title,
      DateTime? due,
      String? categoryId,
      String notes = '',
      String source = TaskSource.starredEmail,
      MatrixBox? box,
      bool board = false,
      bool star = false}) {
    final t = addTask(title, due: due, categoryId: categoryId, notes: notes, source: source, box: box, board: board, star: star);
    t.emails.add(emailOf(m));
    changed(task: t);
    unawaited(_afterStarUse(m));
    return t;
  }

  /// Keeps a starred email on an existing task, in its Emails section.
  void attachEmail(Task t, GmailMessage m) {
    if (t.emails.any((e) => e.id == m.id)) return;
    t.emails.add(emailOf(m));
    changed(task: t);
    unawaited(_afterStarUse(m));
  }

  void removeEmail(Task t, TaskEmail e) {
    t.emails.removeWhere((x) => x.id == e.id);
    changed(task: t);
  }

  static TaskEmail emailOf(GmailMessage m) => TaskEmail(
        id: m.id,
        threadId: m.threadId,
        subject: m.subject,
        from: m.from,
        date: m.date,
        // A short snippet only; the whole email never goes into the synced file.
        snippet: m.snippet.length > 300 ? '${m.snippet.substring(0, 300)}…' : m.snippet,
      );

  void hideEmail(String id) {
    data.hiddenEmails.add(id);
    changed(settings: true);
  }

  /// What the Starred emails setting says to do with the star once the email is used.
  Future<void> _afterStarUse(GmailMessage m) async {
    final g = google;
    if (g == null || data.starredAfter == StarredAfter.keep) return;
    try {
      await g.modify(m.id,
          remove: const ['STARRED'],
          add: data.starredAfter == StarredAfter.unstarLabel ? [await g.labelId('Tasked')] : const []);
    } catch (e) {
      debugPrint('star change: $e');
    }
  }

  /// Starred emails not yet used for a task and not hidden; null when not signed in.
  Future<int?> starredWaiting() async {
    final g = google;
    if (g == null) return null;
    final ids = await g.search(
        data.starredDays > 0 ? 'is:starred newer_than:${data.starredDays}d' : 'is:starred',
        max: 100);
    return ids.where((id) => !data.hiddenEmails.contains(id) && data.taskForEmail(id) == null).length;
  }

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

  /// Item 67: whether new tasks in [c] go on the board, which stage, and steps too.
  void setCategoryBoard(TaskCategory c, {required bool on, String? stageId, bool steps = false}) {
    c
      ..boardByDefault = on
      ..boardStage = on ? stageId : null
      ..stepsOnBoard = on && steps;
    changed(settings: true);
  }

  /// Item 60: renames a matrix box; an empty name goes back to the standard one.
  void setBoxName(MatrixBox b, String name) {
    final n = name.trim();
    if (n.isEmpty || n == b.label) {
      data.matrixNames.remove(b.id);
    } else {
      data.matrixNames[b.id] = n;
    }
    changed(settings: true);
  }

  void setUrgentDays(int days) {
    data.urgentDays = days;
    changed(settings: true);
  }

  /// Item 64: sets the word for a quick-add action; null goes back to the standard word and
  /// '' turns it off.
  void setQuickWord(String id, String? word) {
    if (word == null) {
      data.quickWords.remove(id);
    } else {
      data.quickWords[id] = word.trim().toLowerCase().replaceFirst(RegExp(r'^!+'), '');
    }
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

/// Item 54: an email that asked to be a task but wasn't made one, and why.
class IgnoredEmail {
  IgnoredEmail(this.message, this.reason);

  final GmailMessage message;
  final String reason;
}

/// Item 69: one device's settings as saved in Dropbox.
class DeviceBackup {
  DeviceBackup(this.device, this.savedAt, this.settings, {this.app});

  final String device;
  final DateTime savedAt;
  final String? app;
  final Map<String, dynamic> settings;

  /// What it holds, for the offer: "2 places, Google client, view choices".
  String describe() => [
        if ((settings['places'] as List?)?.isNotEmpty ?? false)
          '${(settings['places'] as List).length} place${(settings['places'] as List).length == 1 ? '' : 's'}',
        if ((settings['googleClientId'] as String? ?? '').isNotEmpty) 'Google client ID and secret',
        if (settings['recordLocation'] == true) 'location recording',
        'list and board view choices',
      ].join(', ');

  static DeviceBackup? tryParse(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      final s = j['settings'];
      if (s is! Map) return null;
      return DeviceBackup(j['device'] as String? ?? '?', DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime(2000),
          Map<String, dynamic>.from(s), app: j['app'] as String?);
    } catch (_) {
      return null;
    }
  }
}
