import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/places.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/task_list.dart';

import 'older_copies_test.dart' show FakeDropbox;

void main() {
  final path = AppStore.deviceBackupPath(AppStore.deviceName);

  AppStore configured(FakeDropbox db) => AppStore()
    ..dropbox = db
    ..deviceBackupChecked = true
    ..recordLocation = true
    ..quickFilter = QuickFilter.week
    ..boardLanes = true
    ..googleClientId = 'id.apps.googleusercontent.com'
    ..googleClientSecret = 'shh'
    ..places.add(Place.create('Home', 51.5, -0.1));

  test('sync saves this device\'s own settings, without sign-ins', () async {
    final db = FakeDropbox({});
    final s = configured(db);
    await s.sync();
    final saved = jsonDecode(db.files[path]!) as Map;
    expect(saved['device'], AppStore.deviceName);
    final settings = saved['settings'] as Map;
    expect(settings['quickFilter'], 'week');
    expect(settings['googleClientId'], 'id.apps.googleusercontent.com');
    expect((settings['places'] as List).single['name'], 'Home');
    expect(jsonEncode(saved), isNot(contains('Token')));
  });

  test('a fresh install offers the saved settings and never saves over them first', () async {
    final db = FakeDropbox({});
    await configured(db).sync();
    final before = db.files[path];

    final fresh = AppStore()..dropbox = db;
    await fresh.sync();
    expect(fresh.restoreOffer, isNotNull);
    expect(fresh.restoreOffer!.describe(), contains('1 place'));
    expect(db.files[path], before, reason: 'the offer is kept until answered');
    await fresh.sync();
    expect(db.files[path], before);

    await fresh.restoreDeviceSettings(fresh.restoreOffer!);
    expect(fresh.restoreOffer, isNull);
    expect(fresh.quickFilter, QuickFilter.week);
    expect(fresh.recordLocation, isTrue);
    expect(fresh.boardLanes, isTrue);
    expect(fresh.places.single.name, 'Home');
    expect(fresh.googleClientId, 'id.apps.googleusercontent.com');
    expect(fresh.google, isNull, reason: 'sign in again');
  });

  test('"Not now" keeps this device\'s settings and saves them from then on', () async {
    final db = FakeDropbox({});
    await configured(db).sync();
    final fresh = AppStore()..dropbox = db;
    await fresh.sync();
    await fresh.dismissRestoreOffer();
    await fresh.sync();
    expect((jsonDecode(db.files[path]!)['settings'] as Map).containsKey('places'), isFalse);
  });

  test('no offer when nothing was saved, or it matches; restore never replaces a Google client', () async {
    final db = FakeDropbox({});
    final s = AppStore()..dropbox = db;
    await s.sync();
    expect(s.restoreOffer, isNull);
    expect(s.deviceBackupChecked, isTrue);
    expect(db.files[path], isNotNull);

    final other = configured(FakeDropbox({}))..googleClientId = 'mine';
    final backups = await configured(db).deviceBackups();
    await other.restoreDeviceSettings(backups.single);
    expect(other.googleClientId, 'mine');
  });

  test('device backups from every kind of device are listed, newest first', () async {
    final db = FakeDropbox({
      AppStore.deviceBackupPath('Mac'):
          jsonEncode({'device': 'Mac', 'savedAt': '2026-11-01T10:00:00Z', 'settings': {'boardLanes': true}}),
      AppStore.deviceBackupPath('Windows'):
          jsonEncode({'device': 'Windows', 'savedAt': '2026-11-02T10:00:00Z', 'settings': {}}),
      AppStore.deviceBackupPath('Android'): 'not json',
    });
    final list = await (AppStore()..dropbox = db).deviceBackups();
    expect([for (final b in list) b.device], ['Windows', 'Mac']);
  });
}
