import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'day_plan.dart' show PlanMove;
import 'dropbox.dart';
import 'focus_timer.dart';
import 'gantt.dart';
import 'google.dart';
import 'home_widgets.dart';
import 'inbox_files.dart';
import 'input_parse.dart';
import 'location.dart';
import 'models.dart';
import 'modes.dart';
import 'native.dart';
import 'places.dart';
import 'reminders.dart';
import 'task_list.dart';

/// Holds the app's data, saves it to disk on every change and syncs it with Dropbox.
/// Item 74: the icons the top bar can show, in order. Each can be switched off in Settings.
abstract final class TopIcon {
  static const search = 'search', board = 'board', matrix = 'matrix', gantt = 'gantt', calendar = 'calendar';
  static const dayPlan = 'dayPlan';
  static const all = [search, board, matrix, gantt, calendar, dayPlan];

  /// Item 101: icons that start switched off (the Day plan is also the Calendar's Day mode).
  static const offByDefault = {dayPlan};
  static const labels = {
    search: 'Search',
    board: 'Kanban board (when tasks are on it)',
    matrix: 'Matrix (when tasks are on it)',
    gantt: 'Gantt chart (when tasks are on it)',
    calendar: 'Calendar',
    dayPlan: 'Day plan (also in the Calendar)',
  };
}

/// Item 73: what "Make into a step of..." does with the task's own checklist.
enum OwnSteps {
  /// Kept inside the new step, and back when it is split out.
  keep,

  /// Added to the new parent as steps of their own.
  addToParent,

  /// Each becomes a task of its own first.
  splitOut,
}

class AppStore extends ChangeNotifier {
  AppStore({this.reminders, this.widgets, this.location}) {
    // 1.12.5: the Day plan's driving estimates start from a saved place called Home.
    savedPlaces = places;
  }

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

  /// Item 74: top bar icons switched off on this device ([TopIcon] names).
  final Set<String> hiddenTopIcons = {};

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
      hadData = true;
      try {
        data = AppData.fromJson(jsonDecode(await dataFile.readAsString()) as Map<String, dynamic>);
      } catch (e) {
        // H2: never save over a file that couldn't be read. Put it aside and start from the newest
        // backup that can be read.
        debugPrint('tasks.json unreadable: $e');
        final aside = (await _putAside(dataFile)).split('/').last;
        final from = await _loadNewestBackup();
        loadProblem = 'Your saved tasks couldn\'t be read, so ${from == null ? 'the list started empty' : 'the backup from $from was opened'}. '
            'The file was kept as $aside. If you use Dropbox, the next sync brings back anything newer.';
      }
    }
    var filterSaved = false;
    final settingsFile = File('${_dir!.path}/device_settings.json');
    Map<String, dynamic>? s;
    if (await settingsFile.exists()) {
      try {
        s = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('device_settings.json unreadable: $e');
        await _putAside(settingsFile);
        loadProblem = [
          ?loadProblem,
          'This device\'s own settings couldn\'t be read (sign-ins, places, view choices); connect Dropbox to restore them, or set them again.',
        ].join(' ');
      }
    }
    if (s case final s?) {
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
      deviceModeChoice = ModeChoice.tryParse(s['modeChoice']);
      focusNow = FocusTimer.tryParse(s['focusTimer']);
      places.addAll([for (final p in s['places'] as List? ?? []) ?Place.tryParse(p)]);
      arrivalSummary = s['arrivalSummary'] as bool? ?? false;
      boardShowSteps = s['boardShowSteps'] as bool? ?? false;
      boardLanes = s['boardLanes'] as bool? ?? false;
      calendarMode = s['calendarMode'] as String? ?? 'month';
      dayPlanTwoDays = s['dayPlanTwoDays'] as bool? ?? false;
      hiddenTopIcons.addAll([for (final n in s['hiddenTopIcons'] as List? ?? []) ?n as String?]);
      matrixFilter = QuickFilter.values.where((f) => f.name == s['matrixFilter']).firstOrNull ?? QuickFilter.all;
      matrixCategory = s['matrixCategory'] as String?;
      deviceBackupChecked = s['deviceBackupChecked'] as bool? ?? false;
      emailCheckMinutes = (s['emailCheckMinutes'] as num?)?.toInt() ?? 0;
      _readPanel(s);
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
    refreshMode(applyStart: false);
    // Item 102: a focus timer left running moves on to where it would be now.
    if (focusNow != null && !tickFocus()) _focusChanged();
    if (_cleanArchive()) await _writeData();
    notifyListeners();
    await applyPending();
    await backupIfDue();
    unawaited(watchPlaces());
    unawaited(reminders?.schedule(data));
    unawaited(widgets?.push(data));
    _startEmailTimer();
    unawaited(sync());
  }

  /// H2: why start-up couldn't read a saved file, shown once at the top of the list; null when fine.
  String? loadProblem;

  void dismissLoadProblem() {
    loadProblem = null;
    notifyListeners();
  }

  /// Renames an unreadable file so nothing saves over it. Returns the new path.
  Future<String> _putAside(File f) async {
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final path = f.path.replaceFirst(RegExp(r'\.json$'), '-unreadable-$stamp.json');
    try {
      await f.rename(path);
    } catch (e) {
      debugPrint('put aside: $e');
    }
    return path;
  }

  /// Loads the newest backup that can be read; returns its day, or null when there is none.
  Future<String?> _loadNewestBackup() async {
    for (final f in await backups()) {
      try {
        data = AppData.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        return RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(f.uri.pathSegments.last)?.group(0) ?? 'a backup';
      } catch (_) {
        continue;
      }
    }
    return null;
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
    for (final m in await widgets?.takeMoves() ?? const <WidgetMove>[]) {
      any = applyWidgetMove(m) || any;
    }
    for (final (id, day, on) in await widgets?.takeWorked() ?? const <(String, DateTime, bool)>[]) {
      final t = data.task(id);
      if (t == null || t.workedOn(day) == on) continue;
      setWorked(t, day, on);
      any = true;
    }
    final pushed = await widgets?.takePushed() ?? const [];
    if (pushed.isNotEmpty) any = addPushed(pushed).isNotEmpty || any;
    if (any) notifyListeners();
  }

  /// Item 68: a move made with a board widget's arrow or "Next" button. Into the last stage, a
  /// task is ticked off only when the board is set to always do that (a widget can't ask).
  bool applyWidgetMove(WidgetMove m) {
    final t = data.task(m.task);
    final to = data.stage(m.stage);
    if (t == null || t.closedAt != null || to == null) return false;
    if (m.step != null) {
      final s = t.steps.where((s) => s.id == m.step).firstOrNull;
      if (s == null || !t.boardSteps.contains(s)) return false;
      moveStepToStage(t, s, to, how: MoveHow.widget);
      return true;
    }
    if (!t.kanban) return false;
    final last = moveToStage(t, to, how: MoveHow.widget);
    if (last && data.kanbanDone == KanbanDone.always) complete(t, at: m.at);
    return true;
  }

  /// Item 48B: tasks sent by another Android app, in the inbox file format. Bad entries are
  /// dropped one by one so a good one sent with them still arrives.
  List<Task> addPushed(List<dynamic> items) {
    final added = <Task>[];
    for (final item in items) {
      try {
        final ts = addInboxFile(data, jsonEncode(item), DateTime.now());
        ts.forEach(_boardByCategory);
        added.addAll(ts);
      } catch (e) {
        debugPrint('pushed task: $e');
      }
    }
    if (added.isNotEmpty) changed();
    return added;
  }

  Future<void> _writeData() {
    final dir = _dir;
    if (dir == null) return Future.value();
    // One write at a time: two at once (a sync and an edit) would share the temporary file and
    // the second rename would fail.
    return _writing = _writing.catchError((_) {}).then((_) async {
      // Write to a temporary file first so a crash mid-write can't corrupt the saved list.
      final tmp = File('${dir.path}/tasks.json.tmp');
      await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
      await tmp.rename('${dir.path}/tasks.json');
    });
  }

  Future<void> _writing = Future.value();

  /// M3: one write at a time, through a temporary file, so two quick changes (a filter chip and a
  /// pane drag, say) can't leave a half-written file that loses the sign-ins.
  Future<void> saveDeviceSettings() {
    final dir = _dir;
    if (dir == null) return Future.value();
    return _settingsWriting = _settingsWriting.catchError((_) {}).then((_) async {
      final tmp = File('${dir.path}/device_settings.json.tmp');
      await tmp.writeAsString(_deviceSettingsText(), flush: true);
      await tmp.rename('${dir.path}/device_settings.json');
    });
  }

  Future<void> _settingsWriting = Future.value();

  String _deviceSettingsText() => jsonEncode({
      'dropboxAppKey': dropboxAppKey,
      'dropboxRefreshToken': dropbox?.refreshToken,
      'eventPromptAt': eventPromptAt?.toIso8601String(),
      'recordLocation': recordLocation,
      'quickFilter': quickFilter.name,
      if (seenVersion != null) 'seenVersion': seenVersion,
      if (deviceModeChoice != null) 'modeChoice': deviceModeChoice!.toJson(),
      if (focusNow != null) 'focusTimer': focusNow!.toJson(),
      if (places.isNotEmpty) 'places': [for (final p in places) p.toJson()],
      if (arrivalSummary) 'arrivalSummary': true,
      if (boardShowSteps) 'boardShowSteps': true,
      if (boardLanes) 'boardLanes': true,
      if (calendarMode != 'month') 'calendarMode': calendarMode,
      if (dayPlanTwoDays) 'dayPlanTwoDays': true,
      if (hiddenTopIcons.isNotEmpty) 'hiddenTopIcons': hiddenTopIcons.toList(),
      if (matrixFilter != QuickFilter.all) 'matrixFilter': matrixFilter.name,
      if (matrixCategory != null) 'matrixCategory': matrixCategory,
      if (deviceBackupChecked) 'deviceBackupChecked': true,
      if (emailCheckMinutes > 0) 'emailCheckMinutes': emailCheckMinutes,
      ..._panelJson(),
      if (googleClientId.isNotEmpty) 'googleClientId': googleClientId,
      if (googleClientSecret.isNotEmpty) 'googleClientSecret': googleClientSecret,
      if (google?.refreshToken != null) 'googleRefreshToken': google!.refreshToken,
      if (google?.email != null) 'googleEmail': google!.email,
    });

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
      var tries = 0;
      do {
        _syncAgain = false;
        final got = await db.downloadWithRev(DropboxClient.filePath);
        final remoteText = got?.$1;
        final remote = remoteText == null ? null : AppData.fromJson(jsonDecode(remoteText));
        final merged = remote == null ? data : mergeData(data, remote);
        // Item 54: the merge first, so a task another device already made from an email is known.
        final mergedText = jsonEncode(merged.toJson());
        if (mergedText != jsonEncode(data.toJson())) {
          data = merged;
          refreshMode();
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
          // M7: another device saved in the meantime; read its copy and merge again.
          if (!await db.uploadIfUnchanged(DropboxClient.filePath, mine, got?.$2)) _syncAgain = true;
        }
      } while (_syncAgain && ++tries < 5);
      _lastSync = DateTime.now();
      _setStatus('Synced ${_now()}');
    } catch (e) {
      _setStatus('Sync failed: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  // --- Right-hand panel (item 59), all device-only ---

  /// The view the panel shows when the app starts (Settings), and the one showing now.
  PanelView panelStart = PanelView.agenda;
  PanelView panelView = PanelView.agenda;

  /// Reopen the view used last instead of [panelStart].
  bool panelRemember = false;

  /// Views left out of the panel's chip row.
  final panelHidden = <PanelView>{};

  /// What the Statistics view shows.
  final panelStats = <PanelStat>{PanelStat.week, PanelStat.category};

  /// What opens when the Fold is unfolded.
  UnfoldOpens unfoldOpens = UnfoldOpens.panel;

  /// Item 81: how much of the width the right-hand pane takes when unfolded, set by dragging the
  /// divider (null = the default, 40%; half for the matrix).
  double? panelFraction;

  /// Sets [panelFraction] while dragging; [save] when the drag ends.
  void setPanelFraction(double? f, {bool save = false}) {
    panelFraction = f?.clamp(panelMinFraction, panelMaxFraction);
    notifyListeners();
    if (save) unawaited(saveDeviceSettings());
  }

  static const panelMinFraction = 0.25;

  /// 1.12.4: the right-hand pane dragged shut (iPad, Fold): the list takes the whole width and a
  /// handle on the right edge brings the pane back. An open task still shows beside the list.
  bool panelClosed = false;

  void setPanelClosed(bool v) {
    if (panelClosed == v) return;
    panelClosed = v;
    notifyListeners();
    unawaited(saveDeviceSettings());
  }
  static const panelMaxFraction = 0.7;

  Map<String, dynamic> _panelJson() => {
        if (panelStart != PanelView.agenda) 'panelStart': panelStart.name,
        if (panelRemember) 'panelRemember': true,
        if (panelRemember) 'panelLast': panelView.name,
        if (panelHidden.isNotEmpty) 'panelHidden': [for (final v in panelHidden) v.name],
        'panelStats': [for (final v in panelStats) v.name],
        if (unfoldOpens != UnfoldOpens.panel) 'unfoldOpens': unfoldOpens.name,
        if (panelFraction != null) 'panelFraction': panelFraction,
        if (panelClosed) 'panelClosed': true,
      };

  void _readPanel(Map<String, dynamic> s) {
    T? byName<T extends Enum>(List<T> values, Object? name) => values.where((v) => v.name == name).firstOrNull;
    panelStart = byName(PanelView.values, s['panelStart']) ?? panelStart;
    panelRemember = s['panelRemember'] as bool? ?? panelRemember;
    if (s['panelHidden'] is List) {
      panelHidden
        ..clear()
        ..addAll([for (final n in s['panelHidden'] as List) ?byName(PanelView.values, n)]);
    }
    if (s['panelStats'] is List) {
      panelStats
        ..clear()
        ..addAll([for (final n in s['panelStats'] as List) ?byName(PanelStat.values, n)]);
    }
    unfoldOpens = byName(UnfoldOpens.values, s['unfoldOpens']) ?? unfoldOpens;
    final f = s['panelFraction'];
    if (f is num) panelFraction = f.toDouble().clamp(panelMinFraction, panelMaxFraction);
    panelClosed = s['panelClosed'] == true;
    panelView = (panelRemember ? byName(PanelView.values, s['panelLast']) : null) ?? panelStart;
    if (panelHidden.contains(panelView)) panelView = shownPanelViews.first;
  }

  /// The chips in the panel, in order. Never empty: Agenda stays when all are hidden.
  List<PanelView> get shownPanelViews {
    // Item 102: a mode's tools that are off leave the panel too.
    bool inMode(PanelView v) => switch (v) {
          PanelView.matrix => modeNow.toolOn(ModeTool.matrix),
          PanelView.board => modeNow.toolOn(ModeTool.board),
          PanelView.timeline => modeNow.toolOn(ModeTool.gantt),
          PanelView.calendar => modeNow.toolOn(ModeTool.calendar),
          PanelView.dayPlan => modeNow.toolOn(ModeTool.dayPlan),
          PanelView.events => modeNow.toolOn(ModeTool.events),
          PanelView.stats => modeNow.toolOn(ModeTool.stats),
          PanelView.achievements => modeNow.toolOn(ModeTool.achievements),
          _ => true,
        };
    final v = [for (final v in PanelView.values) if (!panelHidden.contains(v) && inMode(v)) v];
    return v.isEmpty ? [PanelView.agenda] : v;
  }

  void showPanel(PanelView v) {
    if (panelView == v) return;
    panelView = v;
    notifyListeners();
    if (panelRemember) unawaited(saveDeviceSettings());
  }

  /// Saves a change to the panel settings made in Settings.
  void panelSettingsChanged() {
    if (panelHidden.contains(panelView)) panelView = shownPanelViews.first;
    notifyListeners();
    unawaited(saveDeviceSettings());
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
        'hiddenTopIcons': hiddenTopIcons.toList(),
        'matrixFilter': matrixFilter.name,
        if (matrixCategory != null) 'matrixCategory': matrixCategory,
        if (googleClientId.isNotEmpty) 'googleClientId': googleClientId,
        if (googleClientSecret.isNotEmpty) 'googleClientSecret': googleClientSecret,
        if (emailCheckMinutes > 0) 'emailCheckMinutes': emailCheckMinutes,
        ..._panelJson(),
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
    if (s['hiddenTopIcons'] is List) {
      hiddenTopIcons
        ..clear()
        ..addAll([for (final n in s['hiddenTopIcons'] as List) ?n as String?]);
    }
    matrixFilter = QuickFilter.values.where((f) => f.name == s['matrixFilter']).firstOrNull ?? matrixFilter;
    matrixCategory = s['matrixCategory'] as String? ?? matrixCategory;
    emailCheckMinutes = (s['emailCheckMinutes'] as num?)?.toInt() ?? emailCheckMinutes;
    _readPanel(s);
    _startEmailTimer();
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
      // M6: take the file by deleting it first; when another device already took it, skip it.
      if (await db.delete(path) == null) continue;
      List<Task> added;
      try {
        added = addInboxFile(data, text, DateTime.now());
        added.forEach(_boardByCategory);
      } catch (e) {
        // Not a task file (bad JSON, no title, wrong types): set it aside, don't retry forever.
        debugPrint('inbox $path: $e');
        await db.uploadPath('${DropboxClient.inboxFolder}/failed/${path.split('/').last}', text);
        continue;
      }
      any = any || added.isNotEmpty;
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
    // M6: empty the file first, only if it is still what was read, so a line added meanwhile
    // isn't lost and two devices never both take the same lines.
    String? text;
    for (var i = 0; i < 3 && text == null; i++) {
      final got = await db.downloadWithRev(DropboxClient.inboxPath);
      if (got == null || got.$1.trim().isEmpty) return false;
      if (await db.uploadIfUnchanged(DropboxClient.inboxPath, '', got.$2)) text = got.$1;
    }
    if (text == null) return false;
    final lines = splitLines(text);
    if (lines.isEmpty) return false;
    for (final line in lines) {
      final p = parseInput(line, data, DateTime.now());
      final t = Task.create(p.title, source: TaskSource.inbox)
        ..dueAt = p.due
        ..categoryId = p.categoryId;
      data.active.add(t);
      _applyNew(t, box: p.box, board: p.board, star: p.star, gantt: p.gantt, plan: p.plan);
    }
    data.updatedAt = data.orderUpdatedAt = DateTime.now().toUtc();
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
      bool gantt = false,
      KanbanStage? stage,
      ({DateTime at, int? minutes})? plan}) {
    final t = Task.create(title.trim(), source: source)
      ..dueAt = due
      ..categoryId = categoryId
      ..notes = notes
      ..eventId = eventId;
    data.active.add(t);
    _applyNew(t, box: box, board: board, star: star, gantt: gantt, stage: stage, plan: plan);
    changed(order: true);
    _locate([t]);
    return t;
  }

  /// A new task from a typed or sent line: what the quick-add words asked for (item 64), and the
  /// board if its category goes there by default (item 67).
  /// [stage] puts it straight into that stage (the + on a board column).
  /// [plan] ("@14:00 45m", item 101) gives it a planned time on the Day plan.
  void _applyNew(Task t,
      {MatrixBox? box, bool board = false, bool star = false, bool gantt = false, KanbanStage? stage, ({DateTime at, int? minutes})? plan}) {
    if (box != null) t.matrixBox = box.id;
    if (plan != null) {
      final m = plan.minutes ?? data.dayPlan.length;
      if (plan.minutes != null) t.estimate ??= m;
      t.slots.add(TimeSlot.create(plan.at, m));
      t.dayPlan = true;
    }
    if (gantt) setOnGantt(t, true);
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
      _applyNew(t, box: p.box, board: p.board, star: p.star, gantt: p.gantt, plan: p.plan);
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
    data.done[t.id] = DoneRecord.of(t, now,
        mode: modeNow.mode?.id ?? everythingId,
        outside: modeNow.mode?.showFor(data, t.categoryId) == CatShow.hide);
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

  /// 1.12.5: where [t] happens (null removes it).
  void setWhere(Task t, TaskWhere? w) {
    t.where = w;
    changed(task: t);
  }

  /// 1.12.5: minutes of driving before and after [t]'s planned times (null = suggest, 0 = none).
  void setDrive(Task t, {required int? before, required int? after}) {
    t.driveBefore = before;
    t.driveAfter = after;
    changed(task: t);
  }

  /// Where the phone is now, asking for location access if needed. Null when it can't be had.
  Future<GeoPoint?> whereNow() async {
    final loc = location;
    if (loc == null || !await loc.requestAccess()) return null;
    return loc.current();
  }

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
    // Item 72: starting work on it fills in an empty start date.
    if (to != null &&
        how != MoveHow.repeat &&
        data.ganttStartOnProgress &&
        t.startAt == null &&
        t.closedAt == null &&
        (to.id == 'doing' || to.name.trim().toLowerCase() == 'in progress')) {
      t.startAt = dayOf(m.at);
      _notePlan(t);
    }
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

  // --- Days worked (item 75) ---

  /// Ticks (or unticks) [day] as a day [t] was worked on. It doesn't finish the task or move it on
  /// the board. Item 88: ticking today restarts an undated task's colour from green.
  void setWorked(Task t, DateTime day, bool on) {
    final key = dayKey(day);
    if (on ? !t.worked.add(key) : !t.worked.remove(key)) return;
    final now = DateTime.now();
    if (on && key == dayKey(now)) {
      t.workedAt = now;
    } else if (!on && t.workedAt != null && dayKey(t.workedAt!) == key) {
      t.workedAt = null;
    }
    changed(task: t);
  }

  /// Flips today (or [day]) for [t]. Returns whether it is now ticked.
  bool toggleWorked(Task t, [DateTime? day]) {
    final d = day ?? DateTime.now();
    final on = !t.workedOn(d);
    setWorked(t, d, on);
    return on;
  }

  // --- Habits (item 78) ---

  /// Makes [t] a habit (or an ordinary task again). A habit is never ticked off, so it leaves the
  /// board, the matrix and the Gantt chart and loses its due date. A repeating task keeps its
  /// history: each day one of its series was ticked off becomes a ticked day.
  void setHabit(Task t, bool on) {
    if (on == t.habit) return;
    if (on) {
      if (t.kanban) setOnBoard(t, false);
      t.matrixBox = null;
      t.gantt = false;
      final r = t.repeat;
      if (r != null) {
        for (final rec in data.done.values) {
          if (rec.series == t.series) t.worked.add(dayKey(rec.at));
        }
        for (final old in data.archived) {
          if (old.series == t.series && old.closedAt != null) t.worked.add(dayKey(old.closedAt!));
        }
        if (r.unit == RepeatUnit.week && r.every == 1 && r.weekdays.isNotEmpty) {
          t.habitGoal = HabitGoal.weekdays;
          t.habitDays
            ..clear()
            ..addAll(r.weekdays);
        } else if (r.unit == RepeatUnit.week) {
          t.habitGoal = HabitGoal.perWeek;
          t.habitTimes = 1;
        } else {
          t.habitGoal = HabitGoal.daily;
        }
        if (t.dueAt != null && (t.dueAt!.hour != 0 || t.dueAt!.minute != 0)) t.habitRemind ??= t.dueAt!.hour * 60 + t.dueAt!.minute;
        t.repeat = null;
      }
      t.dueAt = null;
      t.snoozedUntil = null;
    }
    t.habit = on;
    changed(task: t, order: true);
  }

  /// Pauses a habit (its streak is kept and paused days don't count), or carries on.
  void pauseHabit(Task t, bool pause) {
    final today = dayKey(DateTime.now());
    if (pause && !t.habitPaused) {
      t.habitPauses.add('$today/');
    } else if (!pause && t.habitPaused) {
      final last = t.habitPauses.removeLast();
      final from = last.substring(0, last.length - 1);
      // Paused and carried on the same day leaves nothing to skip.
      if (from != today) t.habitPauses.add('$from/${dayKey(DateTime.now().subtract(const Duration(days: 1)))}');
    }
    changed(task: t);
  }

  // --- Day plan (item 101) ---

  /// Puts [t] on the Day plan (into its tray) or takes it off. Taking it off removes its planned
  /// times that aren't ticked yet.
  void setOnDayPlan(Task t, bool on) {
    t.dayPlan = on;
    if (!on) t.slots.removeWhere((s) => s.doneAt == null);
    changed(task: t);
  }

  /// Gives [t] (or its [step]) a planned time.
  TimeSlot planTime(Task t, DateTime start, int minutes, {TaskStep? step, int? gap, bool shared = false}) {
    final s = TimeSlot.create(start, minutes, stepId: step?.id, gapAfter: gap, shared: shared);
    t.slots.add(s);
    t.dayPlan = true;
    changed(task: t);
    return s;
  }

  /// Changes a planned time; [gap] -1 means the default.
  void updateSlot(Task t, TimeSlot s, {DateTime? start, int? minutes, int? gap, bool? shared}) {
    if (start != null) s.start = start;
    if (minutes != null && minutes > 0) s.minutes = minutes;
    if (gap != null) s.gapAfter = gap < 0 ? null : gap;
    if (shared != null) s.shared = shared;
    changed(task: t);
  }

  void removeSlot(Task t, TimeSlot s) {
    t.slots.remove(s);
    changed(task: t);
  }

  /// Puts back a planned time removed by [removeSlot] (undo).
  void restoreSlot(Task t, TimeSlot s) {
    if (!t.slots.contains(s)) t.slots.add(s);
    changed(task: t);
  }

  /// Ticks a block on the Day plan. A step's block ticks the step; a task's block ticks the task
  /// off, unless more of its time is planned later, when it only counts as worked today. Returns
  /// what happened, so the screen can offer to tick the task or undo.
  SlotTick tickSlot(Task t, TimeSlot s, {DateTime? now, void Function(int index, Task? next)? onComplete}) {
    now ??= DateTime.now();
    s.doneAt = now;
    final step = s.stepId == null ? null : t.steps.where((x) => x.id == s.stepId).firstOrNull;
    if (step != null) {
      if (!step.done) {
        step.done = true;
        _stepTicked(t, step);
      }
      if (!t.worked.contains(dayKey(now))) setWorked(t, now, true);
      changed(task: t);
      return t.steps.every((x) => x.done) ? SlotTick.lastStep : SlotTick.step;
    }
    final later = t.ownSlots.any((x) => !identical(x, s) && x.doneAt == null && x.start.isAfter(s.start));
    if (later) {
      setWorked(t, now, true);
      changed(task: t);
      return SlotTick.worked;
    }
    if (t.closedAt == null) {
      final index = data.active.indexOf(t);
      final next = complete(t);
      onComplete?.call(index, next);
    }
    return SlotTick.done;
  }

  /// Unticks a block (and its step). A task ticked off from its block is put back separately.
  void untickSlot(Task t, TimeSlot s) {
    s.doneAt = null;
    final step = s.stepId == null ? null : t.steps.where((x) => x.id == s.stepId).firstOrNull;
    if (step != null && step.done) {
      step.done = false;
      _stepTicked(t, step);
    }
    changed(task: t);
  }

  /// Item 101: a category whose tasks all go on the Day plan.
  void setCategoryDayPlan(TaskCategory c, bool on) {
    c.dayPlan = on;
    changed(settings: true);
  }

  /// Item 101: the Day plan's settings changed.
  void dayPlanChanged() => changed(settings: true);

  /// Moves planned times as [pushAfter] worked out; [back] puts them where they were (undo).
  void applyPlanMoves(List<PlanMove> moves, {bool back = false}) {
    for (final m in moves) {
      m.slot.start = back ? m.from : m.to;
    }
    for (final t in {for (final m in moves) m.task}) {
      changed(task: t);
    }
  }

  /// Plans [t]'s open steps that have no time yet one after another from [start], in order
  /// (a step that comes after another goes after it). Each takes [each] minutes (the default
  /// length when null) with [gap] minutes between (the default gap when null). With [within]
  /// they share that many minutes evenly, back to back, so they fit inside the task's own
  /// block. Returns the new times.
  List<TimeSlot> planStepsInOrder(Task t, DateTime start, {int? each, int? gap, int? within}) {
    final s = data.dayPlan;
    final todo = t.steps.where((x) => !x.done && t.slotsOf(x).every((sl) => sl.doneAt != null)).toList();
    if (todo.isEmpty) return const [];
    // List order, except that a step never goes before one it comes after.
    final ordered = <TaskStep>[];
    final left = [...todo];
    while (left.isNotEmpty) {
      final next = left.firstWhere(
        (x) => !x.afterIds.any((id) => left.any((o) => o.id == id)),
        orElse: () => left.first,
      );
      ordered.add(next);
      left.remove(next);
    }
    var length = each ?? s.length;
    var g = gap ?? s.gapMinutes;
    if (within != null) {
      length = max(s.snap, within ~/ ordered.length ~/ s.snap * s.snap);
      g = 0;
    }
    final out = <TimeSlot>[];
    var at = start;
    for (final st in ordered) {
      final sl = TimeSlot.create(at, length, stepId: st.id, gapAfter: within != null ? 0 : gap);
      t.slots.add(sl);
      out.add(sl);
      at = at.add(Duration(minutes: length + g));
    }
    t.dayPlan = true;
    changed(task: t);
    return out;
  }

  /// Takes away times added by [planStepsInOrder] (undo).
  void removeSlots(Task t, List<TimeSlot> slots) {
    t.slots.removeWhere(slots.contains);
    changed(task: t);
  }

  // --- Gantt chart (item 72) ---

  /// Puts [t] on the Gantt chart (or takes it off). [start] sets its start day.
  void setOnGantt(Task t, bool on, {DateTime? start}) {
    t.gantt = on;
    if (on && start != null) t.startAt = dayOf(start);
    if (on) _notePlan(t);
    changed(task: t);
  }

  /// Remembers the first planned dates of a task on the chart, so slips can be shown.
  void _notePlan(Task t) {
    if (!t.gantt) return;
    final bar = barFor(t, data);
    if (bar == null || bar.guessedStart) return;
    t.planStart ??= bar.start;
    t.planDue ??= bar.end;
  }

  /// Call after the task page changes a Gantt field (start, length, dates).
  void ganttChanged(Task t) {
    _notePlan(t);
    changed(task: t);
  }

  /// Moves [t] on the chart by [days] (start and due together). Returns the tasks after it that
  /// would now start too early, with how far each would move; the screen asks, or applies them
  /// as Settings says.
  Map<Task, int> moveOnGantt(Task t, int days) {
    if (days == 0) return const {};
    if (t.startAt == null) {
      final bar = barFor(t, data);
      if (bar != null) t.startAt = bar.start;
    }
    shiftDates(t, days);
    changed(task: t);
    return pushPlan(t, data);
  }

  /// Drags [t]'s right end to [end]: changes how long it takes when it has a length, otherwise its
  /// due date (keeping the time of day, 5 pm when it had none).
  Map<Task, int> resizeOnGantt(Task t, DateTime end) {
    final bar = barFor(t, data);
    if (bar == null) return const {};
    final day = dayOf(end).isBefore(bar.start) ? bar.start : dayOf(end);
    t.startAt ??= bar.start;
    if (t.takesDays != null) {
      t.takesDays = workDays(bar.start, day, weekends: weekendsFor(t, data));
    } else {
      final old = t.dueAt;
      t.dueAt = DateTime(day.year, day.month, day.day, old?.hour ?? 17, old?.minute ?? 0);
    }
    changed(task: t);
    return pushPlan(t, data);
  }

  /// Applies a push worked out by [moveOnGantt] or [resizeOnGantt].
  void pushLater(Map<Task, int> plan) {
    plan.forEach((f, days) {
      if (f.startAt == null) {
        final bar = barFor(f, data);
        if (bar != null) f.startAt = bar.start;
      }
      shiftDates(f, days);
      changed(task: f);
    });
  }

  /// Makes [t] come after [other] too. False (nothing changed) when that would make a loop.
  bool addAfter(Task t, Task other) {
    if (wouldLoop(t, other, data) || t.afterIds.contains(other.id)) return false;
    if (t.afterTaskId == null) {
      t.afterTaskId = other.id;
    } else {
      t.alsoAfter.add(other.id);
    }
    changed(task: t);
    return true;
  }

  /// Stops [t] coming after the task with [id].
  void removeAfter(Task t, String id) {
    if (t.afterTaskId == id) {
      t.afterTaskId = t.alsoAfter.isEmpty ? null : t.alsoAfter.removeAt(0);
    } else {
      t.alsoAfter.remove(id);
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
    if (s.done) _tickLinkedSteps(s);
    if (!t.boardSteps.contains(s) || data.stages.isEmpty) return;
    final last = data.stages.last;
    if (s.done && s.stageId != last.id) {
      _moveStep(t, s, last, MoveHow.done, locate: false);
    } else if (!s.done && s.stageId == last.id) {
      final back = s.moves.isEmpty ? null : data.stage(s.moves.last.fromId);
      _moveStep(t, s, back == null || back.id == last.id ? data.stages.first : back, MoveHow.reopened, locate: false);
    }
  }

  /// Item 106: ticks the open steps linked to [s] (in any open task), and the steps linked to
  /// those in turn. Unticking [s] leaves them ticked, as a linked task does.
  void _tickLinkedSteps(TaskStep s) {
    for (final x in data.active) {
      for (final st in x.steps.where((st) => st.linkStepId == s.id && !st.done).toList()) {
        st.done = true;
        x.touch();
        _stepTicked(x, st);
      }
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
        due: p.due, categoryId: p.categoryId, source: TaskSource.kanban, box: p.box, star: p.star, gantt: p.gantt, stage: stage, plan: p.plan);
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
    data.deleted[s.id] = DateTime.now().toUtc();
    changed(settings: true);
  }

  /// The board's Show steps and Lanes buttons, remembered on this device.
  void setBoardView({bool? showSteps, bool? lanes}) {
    boardShowSteps = showSteps ?? boardShowSteps;
    boardLanes = lanes ?? boardLanes;
    notifyListeners();
    saveDeviceSettings();
  }

  // --- Item 102, part 4: the focus timer ---

  Timer? _focusTick;

  /// Starts a focus round on [t] (and [stepId]), replacing any timer running.
  void startFocus(Task t, {String? stepId}) {
    final now = DateTime.now();
    final old = focusNow;
    if (old != null) _creditFocus(old, now);
    final len = data.focusSettings.lengthOf(FocusPhase.focus);
    focusNow = FocusTimer(taskId: t.id, stepId: stepId, length: len, end: now.add(len), runFrom: now);
    _focusChanged();
  }

  /// Moves the timer on to what happens at [now]: rounds that ended become breaks, breaks that
  /// ended wait for the next round. Returns whether anything changed. Runs every few seconds
  /// while the app is open and when it opens.
  bool tickFocus([DateTime? at]) {
    final f = focusNow;
    if (f == null) return false;
    final now = at ?? DateTime.now();
    if (!data.active.any((t) => t.id == f.taskId)) {
      // Ticked off or deleted (here or on another device).
      stopFocus();
      return true;
    }
    var changed = false;
    while (f.end != null && !now.isBefore(f.end!)) {
      final end = f.end!;
      changed = true;
      if (f.phase == FocusPhase.focus) {
        _creditFocus(f, end);
        f.phase = f.round % data.focusSettings.every == 0 ? FocusPhase.longBreak : FocusPhase.shortBreak;
        f.length = data.focusSettings.lengthOf(f.phase);
        f.end = end.add(f.length);
        f.runFrom = null;
      } else {
        // The break is over: the next round waits for Start.
        f.phase = FocusPhase.focus;
        f.round++;
        f.length = data.focusSettings.lengthOf(FocusPhase.focus);
        f.end = null;
        f.left = f.length;
        f.heldBreak = true;
      }
    }
    if (changed) _focusChanged();
    return changed;
  }

  void pauseFocus() {
    final f = focusNow;
    if (f == null || f.end == null) return;
    final now = DateTime.now();
    if (f.phase == FocusPhase.focus) _creditFocus(f, now);
    f.left = f.remaining(now);
    f.end = null;
    f.runFrom = null;
    _focusChanged();
  }

  /// Carries on after a pause, or starts the round waiting after a break.
  void resumeFocus() {
    final f = focusNow;
    if (f == null || f.end != null) return;
    final now = DateTime.now();
    f.end = now.add(f.left ?? f.length);
    f.left = null;
    f.heldBreak = false;
    if (f.phase == FocusPhase.focus) f.runFrom = now;
    _focusChanged();
  }

  /// Five more minutes on this round or break.
  void addFocusTime([Duration more = const Duration(minutes: 5)]) {
    final f = focusNow;
    if (f == null) return;
    f.length += more;
    if (f.end != null) {
      f.end = f.end!.add(more);
    } else {
      f.left = (f.left ?? f.length - more) + more;
    }
    _focusChanged();
  }

  /// Ends a break early and starts the next round.
  void skipBreak() {
    final f = focusNow;
    if (f == null) return;
    final now = DateTime.now();
    if (f.phase == FocusPhase.focus && f.end != null) return;
    if (f.phase.isBreak) f.round++;
    f
      ..phase = FocusPhase.focus
      ..length = data.focusSettings.lengthOf(FocusPhase.focus)
      ..left = null
      ..heldBreak = false;
    f
      ..end = now.add(f.length)
      ..runFrom = now;
    _focusChanged();
  }

  void stopFocus() {
    final f = focusNow;
    if (f == null) return;
    _creditFocus(f, DateTime.now());
    focusNow = null;
    _focusChanged();
  }

  /// Moves the session to another step of the same task (null = the task as a whole).
  void setFocusStep(String? stepId) {
    final f = focusNow;
    if (f == null) return;
    f.stepId = stepId;
    _focusChanged();
  }

  /// Saves the focus time since the round started or resumed on the task: whole minutes on
  /// [Task.focus] for the day, and the day counts as worked on.
  void _creditFocus(FocusTimer f, DateTime until) {
    final from = f.runFrom;
    if (from == null || f.phase != FocusPhase.focus) return;
    f.runFrom = until;
    final t = data.task(f.taskId);
    if (t == null) return;
    final midnight = DateTime(from.year, from.month, from.day + 1);
    // Split at midnight, so each day gets its own minutes.
    final parts = until.isAfter(midnight)
        ? {
            dayKey(from): f.carry + midnight.difference(from).inSeconds,
            dayKey(until): until.difference(midnight).inSeconds.clamp(0, 24 * 3600),
          }
        : {dayKey(from): f.carry + until.difference(from).inSeconds.clamp(0, 24 * 3600)};
    var secs = 0;
    var any = false;
    parts.forEach((k, s) {
      final mins = s ~/ 60;
      secs += s % 60;
      if (mins > 0) {
        t.focus[k] = (t.focus[k] ?? 0) + mins;
        any = true;
      }
    });
    f.carry = secs;
    if (any) {
      t.worked.add(dayKey(until));
      changed(task: t);
    }
  }

  void _focusChanged() {
    final f = focusNow;
    _focusTick?.cancel();
    if (f != null) {
      // Wakes up as the phase ends, to move on and reschedule.
      final end = f.end;
      if (end != null) {
        _focusTick = Timer(end.difference(DateTime.now()) + const Duration(milliseconds: 200), () => tickFocus());
      }
    }
    unawaited(_focusDnd(f != null && f.running && f.phase == FocusPhase.focus));
    unawaited(reminders?.showFocus(f, f == null ? null : data.task(f.taskId)));
    unawaited(reminders?.schedule(data));
    unawaited(widgets?.push(data));
    unawaited(saveDeviceSettings());
    notifyListeners();
  }

  bool _dndOn = false;

  /// Do not disturb during focus rounds, when switched on (Android, with access granted).
  Future<void> _focusDnd(bool on) async {
    if (!data.focusSettings.dnd && !_dndOn) return;
    final want = on && data.focusSettings.dnd;
    if (want == _dndOn) return;
    if (await Native.setDoNotDisturb(want)) _dndOn = want;
  }

  // --- Item 102: focus modes ---

  /// A mode picked by hand on this device (device-only; [AppData.modeChoice] is for every device).
  ModeChoice? deviceModeChoice;

  /// The hand choice in force at [now]: the newer of this device's and the shared one, while it
  /// lasts. A choice with an empty mode means "back to the schedule".
  ModeChoice? _choiceAt(DateTime now) {
    final d = deviceModeChoice, s = data.modeChoice;
    final newest = d == null ? s : (s == null || d.at.isAfter(s.at) ? d : s);
    if (newest == null || newest.mode.isEmpty || !newest.activeAt(now)) return null;
    if (newest.mode != everythingId && data.mode(newest.mode) == null) return null;
    return newest;
  }

  /// Item 102: the saved place this device is at (checked while the app is open; null = none or
  /// not known) and the calendar events happening now (id, title, start, end).
  String? placeNow;
  DateTime? _placeAt;
  List<(String, String, DateTime, DateTime)> eventsNow = const [];
  DateTime? _autoChecked;

  /// A switch by place or calendar event waiting for a yes ("Ask before switching").
  AutoMode? pendingAuto;
  final _autoYes = <String>{}, _autoNo = <String>{};

  /// Set after a place or event switched mode by itself, for the list to show once.
  String? autoNote;

  /// What the mode would be without a hand choice: a place or event's, else the schedule's.
  String automaticMode = everythingId;

  bool get _modesByPlace => data.modes.any((m) => m.places.isNotEmpty);
  bool get _modesByEvent => data.modes.any((m) => m.events.isNotEmpty);

  /// Looks at where the phone is and what is on the calendar, for modes that switch by place or
  /// event; at most every 5 minutes unless [force]d.
  Future<void> checkAutoModes({bool force = false}) async {
    final now = DateTime.now();
    if (!_modesByPlace && !_modesByEvent) {
      if (placeNow == null && eventsNow.isEmpty) return;
      placeNow = null;
      eventsNow = const [];
    } else {
      if (!force && _autoChecked != null && now.difference(_autoChecked!) < const Duration(minutes: 5)) return;
      _autoChecked = now;
      if (_modesByPlace && location != null && places.isNotEmpty) {
        final p = await location!.current();
        if (p != null) {
          placeNow = placeAt(places, p.lat, p.lng)?.name;
          _placeAt = now;
        } else if (_placeAt == null || now.difference(_placeAt!) > const Duration(minutes: 30)) {
          // No fix for a while: don't stay "At Office" forever.
          placeNow = null;
        }
      } else {
        placeNow = null;
      }
      if (_modesByEvent && Native.supported) {
        try {
          final evs = await Native.events(
              now.subtract(const Duration(days: 30)), now.add(const Duration(minutes: 1)), data.eventCalendars);
          eventsNow = [
            for (final e in evs)
              (
                e.id,
                e.title,
                e.start,
                // An all-day event (or one from older native code) without a real end lasts the day.
                e.end.isAfter(e.start) ? e.end : DateTime(e.start.year, e.start.month, e.start.day + 1),
              ),
          ];
        } catch (e) {
          debugPrint('mode events: $e');
        }
      } else {
        eventsNow = const [];
      }
    }
    if (!refreshMode()) notifyListeners();
  }

  /// Yes or no to [pendingAuto].
  void answerAutoMode(bool yes) {
    final a = pendingAuto;
    if (a == null) return;
    (yes ? _autoYes : _autoNo).add(a.key);
    pendingAuto = null;
    // Said yes just now: no "Switched to" note as well.
    _noAutoNote = true;
    if (!refreshMode()) notifyListeners();
    _noAutoNote = false;
  }

  /// Undo on "Switched to …": that place or event no longer switches until it changes.
  void answerAutoUndo() {
    final k = _autoUsed;
    if (k == null) return;
    _autoYes.remove(k);
    _autoNo.add(k);
    refreshMode();
  }

  String? _autoUsed;
  bool _noAutoNote = false;

  /// Takes the note left by a switch by place or event, if any.
  String? takeAutoNote() {
    final n = autoNote;
    autoNote = null;
    return n;
  }

  /// Works out the mode in force ([modeNow]) and logs a change for the statistics. With
  /// [applyStart], a change also picks the mode's starting filter chip and panel view.
  /// Order: a hand choice, then a calendar event, then a place, then the weekly schedule.
  /// Returns whether the mode changed.
  bool refreshMode({DateTime? now, bool applyStart = true}) {
    final at = now ?? DateTime.now();
    final choice = _choiceAt(at);
    final scheduled = scheduledAt(data.modeSchedule, at);
    final scheduledId = data.mode(scheduled) == null ? everythingId : scheduled;
    final auto = autoModeAt(data, at, place: placeNow, events: eventsNow);
    AutoMode? use, ask;
    if (auto != null) {
      if (_autoNo.contains(auto.key)) {
        // Said no (or Undo) to this place or event.
      } else if (!data.modeAsk || auto.mode == scheduledId || _autoYes.contains(auto.key)) {
        use = auto;
      } else {
        ask = auto;
      }
    }
    automaticMode = use?.mode ?? scheduledId;
    _autoUsed = use?.key;
    final askBefore = pendingAuto?.key;
    pendingAuto = choice == null ? ask : null;
    final id = choice?.mode ?? automaticMode;
    final mode = data.mode(id);
    final was = modeNow.mode?.id ?? everythingId;
    final byHand = choice != null;
    final byAuto = !byHand && use != null;
    final DateTime? until;
    if (choice != null) {
      until = choice.until;
    } else if (byAuto) {
      until = use.until;
    } else {
      until = nextScheduleChange(data.modeSchedule, at);
    }
    final changed = was != id;
    final dataChanged = !identical(modeNow.data, data);
    modeNow
      ..mode = mode
      ..until = until
      ..byHand = byHand
      ..reason = byAuto ? use.reason : null
      ..reach = byAuto && until == null ? nextScheduleChange(data.modeSchedule, at) : until
      ..data = data;
    if (changed) modeNow.peek = false;
    if (changed && byAuto && mode != null && !_noAutoNote) autoNote = 'Switched to ${mode.name}: ${use.reason}';
    final logged = _logMode(id, byHand ? 'hand' : (byAuto ? 'auto' : (id == everythingId ? 'none' : 'schedule')), at);
    if (logged || dataChanged) modeNow.noonModes = noonModesFrom(data, at);
    if (changed && !shownPanelViews.contains(panelView)) panelView = shownPanelViews.first;
    if (changed && applyStart && mode != null) {
      final f = QuickFilter.values.where((f) => f.name == mode.filter).firstOrNull;
      if (f != null) quickFilter = f;
      final v = PanelView.values.where((v) => v.name == mode.panel).firstOrNull;
      if (v != null && shownPanelViews.contains(v)) panelView = v;
    }
    if (logged) changed ? this.changed() : _markDirty();
    if (!logged && changed) notifyListeners();
    if (!changed && askBefore != pendingAuto?.key) notifyListeners();
    return changed;
  }

  void _markDirty() {
    if (_dir == null && reminders == null && widgets == null) return;
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 400), flush);
  }

  /// Keeps [AppData.modeLog] in step: the open stretch is closed when the mode changes, and time
  /// the app was closed is filled in from the schedule (or the end of a hand choice). Returns
  /// whether the log changed.
  bool _logMode(String id, String how, DateTime now) {
    final open = data.modeLog.where((l) => l.end == null).toList();
    // No modes, no statistics to keep (and nothing written on a plain start-up).
    if (data.modes.isEmpty) {
      for (final l in open) {
        l.end = now;
      }
      return open.isNotEmpty;
    }
    if (open.length == 1 && open.first.mode == id && open.first.how == how) {
      // Still the same, unless the schedule went somewhere else and back while the app was shut.
      final l = open.first;
      if (how == 'hand' || how == 'auto' || scheduleSegments(data.modeSchedule, l.start, now).length <= 1) {
        return false;
      }
    }
    DateTime? from;
    for (final l in open) {
      if (l.how == 'hand') {
        // A hand choice lasted until its end time, if that has gone by.
        final c = [deviceModeChoice, data.modeChoice].where((c) => c != null && c.mode == l.mode).firstOrNull;
        final until = c?.until;
        l.end = until != null && until.isBefore(now) && until.isAfter(l.start) ? until : now;
      } else if (l.how == 'auto') {
        l.end = now;
      } else {
        // A scheduled stretch lasted until the schedule changed.
        final segs = scheduleSegments(data.modeSchedule, l.start, now);
        l.end = segs.isEmpty ? now : segs.first.$3;
      }
      if (from == null || l.end!.isAfter(from)) from = l.end;
    }
    var start = now;
    if (from != null && how != 'hand' && how != 'auto') {
      // Fill in the schedule's changes while the app was closed.
      for (final (m, s, e) in scheduleSegments(data.modeSchedule, from, now)) {
        final mid = data.mode(m) == null ? everythingId : m;
        if (!e.isBefore(now) && mid == id) {
          start = s;
          break;
        }
        final l = ModeLog.open(mid, s, mid == everythingId ? 'none' : 'schedule')..end = e;
        data.modeLog.add(l);
      }
    }
    data.modeLog.add(ModeLog.open(id, start, how));
    final cutoff = now.subtract(const Duration(days: 366));
    data.modeLog.removeWhere((l) => l.end != null && l.end!.isBefore(cutoff));
    return true;
  }

  /// Picks a mode by hand ([everythingId] for Everything) [until] then (null = until changed);
  /// [everywhere] makes the other devices follow. [mode] null goes back to the schedule.
  void chooseMode(String? mode, {DateTime? until, bool everywhere = false}) {
    final c = ModeChoice(mode ?? '', mode == null ? DateTime.now() : until);
    deviceModeChoice = c;
    if (everywhere || data.modeChoice != null) data.modeChoice = everywhere ? c : ModeChoice('', DateTime.now());
    refreshMode();
    changed();
    unawaited(saveDeviceSettings());
  }

  /// "Peek": everything shows until turned off or the mode changes.
  void setPeek(bool on) {
    if (modeNow.peek == on) return;
    modeNow.peek = on;
    if (on) {
      final open = data.modeLog.where((l) => l.end == null).lastOrNull;
      if (open != null) {
        open.peeks++;
        _markDirty();
      }
    }
    notifyListeners();
  }

  void addMode(FocusMode m) {
    data.modes.add(m);
    changed(settings: true);
  }

  /// After a mode is edited in Settings.
  void modeChanged() {
    refreshMode(applyStart: false);
    changed(settings: true);
  }

  void deleteMode(FocusMode m) {
    data.modes.remove(m);
    data.deleted[m.id] = DateTime.now().toUtc();
    data.modeSchedule.removeWhere((s) => s.mode == m.id);
    refreshMode();
    changed(settings: true);
  }

  void moveMode(int from, int to) {
    final m = data.modes.removeAt(from);
    data.modes.insert(to.clamp(0, data.modes.length), m);
    changed(settings: true);
  }

  void setModeSchedule(List<ModeSlot> slots) {
    data.modeSchedule
      ..clear()
      ..addAll(slots);
    refreshMode();
    changed(settings: true);
  }

  /// Makes the starter modes (and, when there is no schedule yet, the starter schedule).
  void addStarterModes() {
    final made = starterModes(data, places: [for (final p in places) p.name]);
    data.modes.addAll(made);
    if (data.modeSchedule.isEmpty) data.modeSchedule.addAll(starterSchedule(data, made));
    refreshMode(applyStart: false);
    changed(settings: true);
  }

  /// Item 74: shows or hides one top bar icon on this device.
  void setTopIcon(String name, bool shown) {
    if (TopIcon.offByDefault.contains(name)) {
      // Kept in the same set as "on:<name>", so older versions just ignore it.
      shown ? hiddenTopIcons.add('on:$name') : hiddenTopIcons.remove('on:$name');
    } else {
      shown ? hiddenTopIcons.remove(name) : hiddenTopIcons.add(name);
    }
    notifyListeners();
    saveDeviceSettings();
  }

  bool topIconShown(String name) =>
      TopIcon.offByDefault.contains(name) ? hiddenTopIcons.contains('on:$name') : !hiddenTopIcons.contains(name);

  /// Item 101: the Calendar page's last view on this device: 'month', 'week' or 'day'.
  String calendarMode = 'month';

  void setCalendarMode(String mode) {
    if (mode == calendarMode) return;
    calendarMode = mode;
    saveDeviceSettings();
  }

  /// Item 101 (1.11.2): the Day plan shows two days side by side on a wide screen (this device).
  bool dayPlanTwoDays = false;

  void setDayPlanTwoDays(bool on) {
    dayPlanTwoDays = on;
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
    // Released once nothing else it waits for is still open (item 72 allows several).
    for (final w in data.active.where((w) => w.afterIds.contains(id) && !data.isLocked(w))) {
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
    // L7: an email that became this task is never made into a task again, even if Gmail's label
    // couldn't be changed.
    if (t.source == TaskSource.email && t.sourceRef != null) data.hiddenEmails.add(t.sourceRef!);
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
    t.slots.removeWhere((x) => x.stepId == s.id);
    tidyStepLinks(t);
    changed(task: t);
  }

  void reorderSteps(Task t, int oldIndex, int newIndex) {
    t.steps.insert(newIndex, t.steps.removeAt(oldIndex));
    changed(task: t);
  }

  /// Turns a step into a full task of its own, placed just after [t] in the list. The step
  /// stays, linked to the new task, and ticks itself when that task is ticked off.
  Task stepToTask(Task t, TaskStep s) {
    final linked = Task.create(s.title, source: TaskSource.step)
      ..categoryId = t.categoryId
      ..dueAt = s.dueAt
      ..remindBefore = s.dueAt == null ? null : s.remindBefore
      ..notes = s.note;
    final at = data.active.indexOf(t);
    data.active.insert(at < 0 ? data.active.length : at + 1, linked);
    s.taskId = linked.id;
    changed(task: t, order: true);
    return linked;
  }

  /// Item 73: rebuilds the task [s] carries (it was made into a step) with everything it had,
  /// plus what changed on the step since: title, date, reminder, note, tick and board stage.
  /// Null if the saved copy can't be read; the caller then splits it out as a plain step.
  Task? _restoreCarried(Task t, TaskStep s) {
    var j = Map<String, dynamic>.from(s.carried!);
    final id = j['id'];
    if (id is! String || data.task(id) != null || data.archived.any((a) => a.id == id)) {
      j = {...j, 'id': Task.create('').id};
    }
    final Task n;
    try {
      n = Task.fromJson(j);
    } catch (_) {
      return null;
    }
    n
      ..title = s.title
      ..dueAt = s.dueAt
      ..remindBefore = s.dueAt == null ? null : s.remindBefore
      ..splitFrom = t.id;
    if (n.notes.trim().isEmpty && s.note.isNotEmpty) n.notes = s.note;
    n.eventId ??= s.eventId;
    n.startAt ??= s.startAt;
    n.takesDays ??= s.takesDays;
    if (t.boardSteps.contains(s) && s.placed) {
      // It was a card on the board as a step: it keeps that stage and history.
      n
        ..kanban = true
        ..stageId = s.stageId
        ..moves.clear()
        ..moves.addAll(s.moves);
    }
    n.closedAt = s.done ? (s.doneAt ?? DateTime.now()) : null;
    data.deleted.remove(n.id);
    t.steps.remove(s);
    final at = data.active.indexOf(t);
    if (n.closedAt == null) {
      data.active.insert(at < 0 ? data.active.length : at + 1, n);
    } else {
      data.archived.insert(0, n);
    }
    changed(task: t, order: true);
    changed(task: n);
    return n;
  }

  /// Item 73: "Make into a step of...". Turns open task [t] into a step of [parent] without
  /// losing anything: the step keeps the whole task ([TaskStep.carried]) and Split out brings it
  /// back. [own] says what happens to [t]'s own steps. Tasks that came after [t] now come after
  /// [parent]; steps linked to [t] now link to [parent]. Returns the step and how to undo it.
  (TaskStep, void Function()) makeStep(Task t, Task parent, {OwnSteps own = OwnSteps.keep}) {
    assert(t != parent);
    final index = data.active.indexOf(t);
    final undos = <void Function()>[];
    final ownSteps = [...t.steps];
    final added = <TaskStep>[];
    switch (own) {
      case OwnSteps.keep:
        break;
      case OwnSteps.addToParent:
        t.steps.clear();
        for (final st in ownSteps) {
          parent.steps.add(st);
          added.add(st);
          if (parent.kanban && parent.stepsOnBoard && !st.placed && data.stages.isNotEmpty) {
            _moveStep(parent, st, st.done ? data.stages.last : data.stages.first, MoveHow.added, locate: false);
          }
        }
        undos.add(() {
          parent.steps.removeWhere(added.contains);
          t.steps
            ..clear()
            ..addAll(ownSteps);
        });
      case OwnSteps.splitOut:
        for (final st in ownSteps.reversed) {
          undos.add(splitOut(t, st).$2);
        }
    }
    final step = TaskStep.create(t.title)
      ..dueAt = t.dueAt
      ..remindBefore = t.dueAt == null ? null : t.remindBefore
      ..note = t.notes.trim().length > 200 ? '${t.notes.trim().substring(0, 200)}…' : t.notes.trim()
      ..eventId = t.eventId
      ..carried = t.toJson();
    if (parent.kanban && parent.stepsOnBoard && data.stages.isNotEmpty) {
      if (t.kanban && data.stage(t.stageId) != null) {
        step
          ..stageId = t.stageId
          ..moves.addAll(t.moves);
      } else {
        _moveStep(parent, step, data.stages.first, MoveHow.added, locate: false);
      }
    }
    parent.steps.add(step);
    // Whatever pointed at the task now points at its new parent.
    final waiting = <Task, String?>{};
    for (final w in data.active.where((w) => w.afterTaskId == t.id)) {
      waiting[w] = w.afterTaskId;
      w.afterTaskId = w == parent ? null : parent.id;
      w.touch();
    }
    final linked = <(Task, TaskStep)>[];
    for (final x in [...data.active, ...data.archived]) {
      for (final st in x.steps.where((st) => st.taskId == t.id)) {
        linked.add((x, st));
        st.taskId = x == parent ? null : parent.id;
        x.touch();
      }
    }
    data.active.remove(t);
    data.deleted[t.id] = DateTime.now().toUtc();
    changed(task: parent, order: true);
    return (
      step,
      () {
        parent.steps.remove(step);
        waiting.forEach((w, id) {
          w.afterTaskId = id;
          w.touch();
        });
        for (final (x, st) in linked) {
          st.taskId = t.id;
          x.touch();
        }
        data.deleted.remove(t.id);
        data.active.insert(index < 0 ? data.active.length : index.clamp(0, data.active.length), t);
        for (final u in undos.reversed) {
          u();
        }
        changed(task: t, order: true);
        changed(task: parent);
      }
    );
  }

  /// Item 61: a step's own due date and reminder (minutes before; null = the default).
  void setStepDue(Task t, TaskStep s, DateTime? due, {int? remindBefore}) {
    s.dueAt = due;
    s.remindBefore = due == null ? null : remindBefore;
    keepStepOrder(t);
    changed(task: t);
  }

  /// Item 72: a step's start day and days of work on the Gantt chart (null clears).
  void setStepPlan(Task t, TaskStep s, {DateTime? start, int? takes, int? progress}) {
    s.startAt = start == null ? null : dayOf(start);
    s.takesDays = takes == null || takes < 1 ? null : takes;
    s.progress = progress == null || progress <= 0 ? null : progress.clamp(0, 100);
    keepStepOrder(t);
    changed(task: t);
  }

  /// Item 85: moves steps that come after others later where they would start too early, unless
  /// Settings, Gantt chart, "When a task moves later" says never. Returns how many moved.
  int keepStepOrder(Task t) => data.ganttPush == GanttPush.never ? 0 : pushSteps(t, data);

  /// Item 85: sets which steps [s] comes after (others of the same task), then keeps the order.
  int setStepAfter(Task t, TaskStep s, Iterable<String> ids) {
    s.afterIds
      ..clear()
      ..addAll(ids.where((id) => id != s.id));
    final moved = keepStepOrder(t);
    changed(task: t);
    return moved;
  }

  /// Item 85: links [s] to a task that already exists, so ticking that task off ticks the step.
  /// Linked to one that is already ticked off, the step is ticked now.
  void linkStep(Task t, TaskStep s, Task other) {
    s.taskId = other.id;
    s.linkStepId = null;
    if (other.closedAt != null && !s.done) {
      s.done = true;
      _stepTicked(t, s);
    }
    changed(task: t);
  }

  /// Item 106: links [s] to another step [other] (of this task or another), so ticking [other]
  /// ticks [s]. Linked to one that is already ticked, [s] is ticked now.
  void linkStepToStep(Task t, TaskStep s, TaskStep other) {
    if (other.id == s.id) return;
    s.linkStepId = other.id;
    s.taskId = null;
    if (other.done && !s.done) {
      s.done = true;
      _stepTicked(t, s);
    }
    changed(task: t);
  }

  /// Takes away [s]'s link to a task or to another step.
  void unlinkStep(Task t, TaskStep s) {
    s.taskId = null;
    s.linkStepId = null;
    changed(task: t);
  }

  void setStepNote(Task t, TaskStep s, String note) {
    s.note = note.trim();
    changed(task: t);
  }

  /// Item 61: "Split out". Turns [s] into a task of its own that no longer belongs to [t]. It
  /// takes [t]'s category, star, place, estimate and matrix box, the step's date (or [t]'s when
  /// it has none) and reminder, its stage on the board (the step's own when steps are on the
  /// board) and the step's board history. Not the repeat, checklist or notes. A step already
  /// made into a linked task frees that task instead. Returns the task and how to undo it.
  (Task, void Function()) splitOut(Task t, TaskStep s) {
    final index = t.steps.indexOf(s);
    if (s.carried != null) {
      final restored = _restoreCarried(t, s);
      if (restored != null) {
        return (
          restored,
          () {
            data.active.remove(restored);
            data.archived.remove(restored);
            data.deleted[restored.id] = DateTime.now().toUtc();
            t.steps.insert(index.clamp(0, t.steps.length), s);
            changed(task: t, order: true);
          }
        );
      }
    }
    final linked = data.task(s.taskId);
    if (linked != null) {
      linked.splitFrom = t.id;
      t.steps.remove(s);
      changed(task: t);
      changed(task: linked);
      return (
        linked,
        () {
          linked.splitFrom = null;
          t.steps.insert(index.clamp(0, t.steps.length), s);
          changed(task: t);
          changed(task: linked);
        }
      );
    }
    final n = Task.create(s.title, source: TaskSource.step)
      ..categoryId = t.categoryId
      ..starred = t.starred
      ..place = t.place
      ..placeLeave = t.placeLeave
      ..where = t.where
      ..estimate = t.estimate
      ..matrixBox = t.matrixBox
      ..waitingOn = t.waitingOn
      ..notes = s.note
      ..eventId = s.eventId
      ..startAt = s.startAt
      ..takesDays = s.takesDays
      ..splitFrom = t.id
      ..dueAt = s.dueAt ?? t.dueAt
      ..remindBefore = s.dueAt != null ? s.remindBefore : t.remindBefore;
    final onBoardAsStep = t.boardSteps.contains(s) && s.placed;
    if (onBoardAsStep) {
      // Its own card already: it keeps its stage and history.
      n
        ..kanban = true
        ..stageId = s.stageId
        ..moves.addAll(s.moves);
    } else if (t.kanban) {
      setOnBoard(n, true, stage: data.stage(t.stageId) ?? data.stages.firstOrNull, how: MoveHow.added);
    }
    if (s.done) n.closedAt = s.doneAt ?? DateTime.now();
    t.steps.remove(s);
    final at = data.active.indexOf(t);
    if (n.closedAt == null) {
      data.active.insert(at < 0 ? data.active.length : at + 1, n);
    } else {
      data.archived.insert(0, n);
    }
    changed(task: t, order: true);
    return (
      n,
      () {
        data.active.remove(n);
        data.archived.remove(n);
        data.deleted[n.id] = DateTime.now().toUtc();
        t.steps.insert(index.clamp(0, t.steps.length), s);
        changed(task: t, order: true);
      }
    );
  }

  /// Item 58: adds a calendar event as a step of [t], with the event's date as the step's due
  /// date (so it gets a reminder and shows in the calendar). The event isn't offered again.
  TaskStep addEventAsStep(Task t, CalendarEvent e) {
    final fmt = e.allDay ? DateFormat('EEE d MMM') : DateFormat('EEE d MMM, HH:mm');
    final s = addStep(t, '${e.title} (${fmt.format(e.start)})')
      ..dueAt = e.allDay ? DateTime(e.start.year, e.start.month, e.start.day, 9) : e.start
      ..eventId = e.id
      ..note = e.location == null || e.location!.isEmpty ? '' : 'At ${e.location}';
    changed(task: t);
    return s;
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
    data.deleted[tpl.id] = DateTime.now().toUtc();
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

  /// Saves Gmail calls on each check: label ids, emails already found not to be tasks, and
  /// ignored emails (kept until their sender is allowed). Reset when the app starts.
  final _labels = <String, String>{};
  final _notTasks = <String>{};
  final _ignoredMessages = <String, GmailMessage>{};

  /// Item 70: also check every this many minutes while the app is open on this device; 0 = only
  /// on open, resume and sync.
  int emailCheckMinutes = 0;
  Timer? _emailTimer;

  void setEmailCheckMinutes(int minutes) {
    emailCheckMinutes = minutes;
    _startEmailTimer();
    unawaited(saveDeviceSettings());
    notifyListeners();
  }

  void _startEmailTimer() {
    _emailTimer?.cancel();
    _emailTimer = null;
    if (emailCheckMinutes <= 0) return;
    _emailTimer = Timer.periodic(Duration(minutes: emailCheckMinutes), (_) {
      // Only while the app is on screen; opening it again checks anyway.
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed && state != AppLifecycleState.inactive) return;
      if (dropbox?.isConnected ?? false) {
        unawaited(sync());
      } else {
        unawaited(checkEmailTasks());
      }
    });
  }

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
      final tasked = _labels['Tasked'] ??= await g.labelId('Tasked');
      final taskLabel = _labels['Task'] ??= await g.labelId('Task');
      final ids = await g.search('newer_than:14d -label:tasked (subject:task OR label:task)', max: 50);
      final ignored = <IgnoredEmail>[];
      for (final id in ids) {
        if (data.hiddenEmails.contains(id) || data.taskForEmail(id) != null || data.allTasks.any((t) => t.sourceRef == id)) continue;
        // Already looked at and not a task: don't fetch it again on every check.
        if (_notTasks.contains(id)) continue;
        final m = _ignoredMessages[id] ?? await g.message(id, checkSender: true);
        final bySubject = _taskPrefix.hasMatch(m.subject);
        if (!bySubject && !m.labels.contains(taskLabel)) {
          _notTasks.add(id);
          continue;
        }
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
          // Kept, so the next check only looks again at whether the sender is now allowed.
          _ignoredMessages[id] = m;
          continue;
        }
        _ignoredMessages.remove(id);
        final subject = m.subject.replaceFirst(_taskPrefix, '').trim();
        final p = parseInput(subject.isEmpty ? '(no subject)' : subject, data, DateTime.now());
        final t = addTask(p.title,
            due: p.due, categoryId: p.categoryId, source: TaskSource.email, box: p.box, board: p.board, star: p.star, gantt: p.gantt, plan: p.plan)
          ..sourceRef = id;
        t.emails.add(emailOf(m));
        changed(task: t);
        added++;
        try {
          await g.modify(id, add: [tasked], remove: [if (m.labels.contains(taskLabel)) taskLabel]);
        } catch (e) {
          debugPrint('label swap: $e');
          _labels.clear(); // The label may have been deleted in Gmail; look it up again next time.
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
      bool star = false,
      bool gantt = false}) {
    final t = addTask(title,
        due: due, categoryId: categoryId, notes: notes, source: source, box: box, board: board, star: star, gantt: gantt);
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
    changed(); // Joined from both copies on sync, so not a settings change (H3).
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
    changed(); // Joined from both copies on sync, so not a settings change (H3).
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
    data.deleted[c.id] = DateTime.now().toUtc();
    for (final t in data.allTasks.where((t) => t.categoryId == c.id)) {
      t.categoryId = null;
      t.touch();
    }
    changed(settings: true);
  }

  /// A view choice: saved and synced, but it doesn't count as a settings change, so it can't make
  /// this device's older settings win over another's on sync (H3).
  void toggleGroupByCategory() {
    data.groupByCategory = !data.groupByCategory;
    changed();
  }

  void toggleCollapsed(String categoryKey) {
    if (!data.collapsed.remove(categoryKey)) data.collapsed.add(categoryKey);
    changed();
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

/// Item 59: what the right-hand panel on a wide screen shows when no task is open.
/// Item 101: what ticking a block on the Day plan did.
enum SlotTick { step, lastStep, worked, done }

enum PanelView {
  agenda('Agenda'),
  matrix('Matrix'),
  board('Board'),
  timeline('Gantt'), // Named "Timeline" before 1.11.2; the stored name stays.
  calendar('Calendar'),
  dayPlan('Day plan'), // Item 101 (1.11.2).
  events('Events'),
  stats('Statistics'),
  achievements('Achievements'),
  archive('Archive');

  const PanelView(this.label);
  final String label;
}

/// Item 59: the parts of the panel's Statistics view.
enum PanelStat {
  week('This week: done, streak, open, overdue'),
  addedDone('Added and done, last 7 days'),
  category('By category'),
  source('By source'),
  board('Time in each board stage');

  const PanelStat(this.label);
  final String label;
}

/// Item 59: what opens when the phone is unfolded.
enum UnfoldOpens {
  panel('The list and the panel'),
  board('The whole Kanban board'),
  matrix('The whole matrix');

  const UnfoldOpens(this.label);
  final String label;
}
