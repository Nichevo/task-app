import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:task_blocks/dropbox.dart';
import 'package:task_blocks/store.dart';

import 'older_copies_test.dart' show FakeDropbox;
import 'package:task_blocks/models.dart';
import 'package:task_blocks/reminders.dart';

void main() {
  group('reminders (review fixes)', () {
    final now = DateTime(2026, 11, 12, 10);

    test('H1: a task snoozed after its due time is reminded again when the snooze ends', () {
      final t = Task.create('Call the bank')
        ..dueAt = DateTime(2026, 11, 12, 9)
        ..snoozedUntil = DateTime(2026, 11, 12, 11);
      final plan = Reminders.plan(AppData()..active.add(t), now);
      expect(plan.map((r) => (r.title, r.when)), [('Snoozed task', DateTime(2026, 11, 12, 11))]);
      expect(plan.single.task, t, reason: 'it keeps the Done and Snooze buttons');
    });

    test('H1: snoozed before it is due, the due reminder waits for the snooze to end', () {
      final t = Task.create('Pay rent')
        ..dueAt = DateTime(2026, 11, 12, 12)
        ..snoozedUntil = DateTime(2026, 11, 12, 15);
      final plan = Reminders.plan(AppData()..active.add(t), now);
      expect(plan.map((r) => r.when), [DateTime(2026, 11, 12, 15)]);
    });

    test('a task not snoozed is reminded at its due time only', () {
      final t = Task.create('Gym')..dueAt = DateTime(2026, 11, 12, 18);
      final plan = Reminders.plan(AppData()..active.add(t), now);
      expect(plan.map((r) => (r.title, r.when)), [('Task due', DateTime(2026, 11, 12, 18))]);
    });

    test('nudges start after a snooze ends', () {
      final t = Task.create('Reply to email')
        ..dueAt = DateTime(2026, 11, 12, 9)
        ..snoozedUntil = DateTime(2026, 11, 12, 11);
      final d = AppData(overdueMode: OverdueMode.nudge, nudgeHours: 3)..active.add(t);
      final nudges = Reminders.plan(d, now).where((r) => r.title == 'Still to do').toList();
      expect(nudges.first.when, DateTime(2026, 11, 12, 14));
    });

    test('M2: tapping a task reminder names its task; buttons and summaries do not', () {
      expect(Reminders.tappedTask(null), isNull);
    });

    test('L3: the daily summary is worked out for each of the next days', () {
      final a = Task.create('Overdue already')..dueAt = DateTime(2026, 11, 10, 9);
      final b = Task.create('Due tomorrow noon')..dueAt = DateTime(2026, 11, 13, 12);
      final d = AppData(overdueMode: OverdueMode.daily, overdueAt: 8 * 60)..active.addAll([a, b]);
      final days = Reminders.dailySummaries(d, now);
      expect(days.length, 7);
      expect(days[0].when, DateTime(2026, 11, 13, 8));
      expect(days[0].title, '1 task overdue');
      expect(days[1].title, '2 tasks overdue');
      expect({for (final r in days) r.id}.length, 7, reason: 'each day has its own notification');
    });
  });

  group('saving safety (review fixes)', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('tb');
      PathProviderPlatform.instance = _Paths(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('H2: one unreadable task is kept as it was, the rest load', () {
      final j = AppData().toJson();
      j['active'] = [Task.create('fine').toJson(), {'id': 'x', 'title': 'no created time'}];
      final d = AppData.fromJson(j);
      expect(d.active.map((t) => t.title), ['fine']);
      expect(d.unreadable, [{'id': 'x', 'title': 'no created time'}]);
      expect(d.toJson()['unreadable'], d.unreadable, reason: 'saved back unchanged');
    });

    test('H2: a file that cannot be read is put aside and the newest backup opens', () async {
      final good = AppData()..active.add(Task.create('from the backup'));
      Directory('${dir.path}/backups').createSync();
      File('${dir.path}/backups/tasks-2026-11-11.json').writeAsStringSync(jsonEncode(good.toJson()));
      File('${dir.path}/tasks.json').writeAsStringSync('{"active": [oops');
      final s = AppStore();
      await s.load();
      expect(s.data.active.map((t) => t.title), ['from the backup']);
      expect(s.loadProblem, contains('2026-11-11'));
      expect(dir.listSync().map((f) => f.uri.pathSegments.last), contains(startsWith('tasks-unreadable-')));
      expect(File('${dir.path}/tasks.json').existsSync(), isFalse, reason: 'nothing saved over it');
    });

    test('M3: quick settings saves never leave a broken file', () async {
      final s = AppStore();
      await s.load();
      await Future.wait([for (var i = 0; i < 20; i++) s.saveDeviceSettings()]);
      expect(jsonDecode(File('${dir.path}/device_settings.json').readAsStringSync()), isA<Map>());
    });
  });

  group('sync (review fixes)', () {
    AppData copy(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);

    test('H3: a category added on one device survives a newer settings change on another', () {
      final phone = AppData()..categories.add(TaskCategory(id: 'work', name: 'Work'));
      final pc = copy(phone);
      phone.categories.add(TaskCategory(id: 'garden', name: 'Garden'));
      phone.settingsUpdatedAt = DateTime.utc(2026, 11, 1, 10);
      pc.hoursToRed = 24;
      pc.settingsUpdatedAt = DateTime.utc(2026, 11, 1, 11);
      final m = mergeData(phone, pc);
      expect(m.categories.map((c) => c.name), ['Work', 'Garden']);
      expect(m.hoursToRed, 24, reason: 'other settings still come from the newer copy');
    });

    test('H3: a category deleted on one device stays deleted', () {
      final s = AppStore();
      final work = s.addCategory('Work');
      final other = copy(s.data);
      s.deleteCategory(work);
      other.settingsUpdatedAt = DateTime.now().toUtc().add(const Duration(minutes: 1));
      expect(mergeData(s.data, other).categories, isEmpty);
    });

    test('H3: collapsing a heading or grouping is not a settings change', () {
      final s = AppStore();
      final before = s.data.settingsUpdatedAt;
      s.toggleCollapsed('');
      s.toggleGroupByCategory();
      s.hideEmail('m1');
      s.dismissEvent('e1');
      expect(s.data.settingsUpdatedAt, before);
    });

    test('M7: a save is refused when another device saved first, and the sync merges again', () async {
      final elsewhere = AppData()..active.add(Task.create('from the PC'));
      final files = {DropboxClient.filePath: jsonEncode(elsewhere.toJson())};
      var first = true;
      final db = _RacingDropbox(files, () {
        if (!first) return;
        first = false;
        // The PC saves again between this phone's download and upload.
        elsewhere.active.add(Task.create('also from the PC'));
        files[DropboxClient.filePath] = jsonEncode(elsewhere.toJson());
      });
      final s = AppStore()..dropbox = db;
      s.addTask('from the phone');
      await s.sync();
      final saved = AppData.fromJson(jsonDecode(files[DropboxClient.filePath]!) as Map<String, dynamic>);
      expect(saved.active.map((t) => t.title).toSet(), {'from the PC', 'also from the PC', 'from the phone'});
    });
  });
}

/// Runs [beforeUpload] just before each save of the main file, to act like another device.
class _RacingDropbox extends FakeDropbox {
  _RacingDropbox(super.files, this.beforeUpload);
  final void Function() beforeUpload;

  @override
  Future<bool> uploadIfUnchanged(String path, String contents, String? rev) {
    if (path == DropboxClient.filePath) beforeUpload();
    return super.uploadIfUnchanged(path, contents, rev);
  }
}

class _Paths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
