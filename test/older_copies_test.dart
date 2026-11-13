import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/changelog.dart';
import 'package:task_blocks/dropbox.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';

/// Dropbox stand-in: keeps the files in memory.
class FakeDropbox extends DropboxClient {
  FakeDropbox(this.files) : super('key', refreshToken: 'token');

  final Map<String, String> files;
  final backups = <String>[];

  @override
  Future<String?> download() async => files[DropboxClient.filePath];

  @override
  Future<void> upload(String contents) async => files[DropboxClient.filePath] = contents;

  /// Each save is a new revision, so a stale upload is refused like Dropbox does.
  @override
  Future<(String, String)?> downloadWithRev(String path) async {
    final t = files[path];
    return t == null ? null : (t, '${t.hashCode}');
  }

  @override
  Future<bool> uploadIfUnchanged(String path, String contents, String? rev) async {
    final now = files[path];
    if (rev == null ? now != null : rev.isNotEmpty && '${now.hashCode}' != rev) return false;
    files[path] = contents;
    return true;
  }

  @override
  Future<void> backup(String contents, DateTime now) async => backups.add(contents);

  @override
  Future<List<String>> inboxFiles() async => const [];

  @override
  Future<String?> downloadPath(String path) async => files[path];

  @override
  Future<void> uploadPath(String path, String contents) async => files[path] = contents;
}

/// A tasks.json as a future version might write it: every level has fields this version
/// doesn't know.
Map<String, dynamic> futureFile() {
  final d = AppData(categories: [TaskCategory(id: 'c1', name: 'Work')]);
  d.templates.add(ChecklistTemplate(id: 'tp', name: 'Trip', steps: ['Pack']));
  final t = Task.create('Renew insurance')
    ..kanban = true
    ..stageId = 'next';
  t.steps.add(TaskStep.create('Get quotes'));
  t.moves.add(StageMove.create(to: d.stages[1], at: DateTime(2026, 11, 1), how: MoveHow.menu));
  d.active.add(t);
  d.done['old'] = DoneRecord(at: DateTime(2026, 10, 1), tookMinutes: 5);

  final j = jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;
  j['newestApp'] = '9.0.0';
  j['focusMode'] = {'on': true, 'until': '18:00'};
  (j['categories'] as List).first['icon'] = true;
  (j['stages'] as List).first['wip'] = {'warn': 3};
  (j['templates'] as List).first['icon'] = 'plane';
  ((j['done'] as Map)['old'] as Map)['box'] = 'do';
  final task = (j['active'] as List).first as Map<String, dynamic>;
  task['matrix'] = 'decide';
  task['attachments'] = [
    {'subject': 'Your renewal', 'from': 'insurer@example.com'},
  ];
  (task['steps'] as List).first['colour'] = 'blue';
  ((task['moves'] as List).first as Map)['by'] = 'widget';
  return j;
}

AppData read(Map<String, dynamic> j) => AppData.fromJson(jsonDecode(jsonEncode(j)));

Map<String, dynamic> written(AppData d) => jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;

void main() {
  test('fields from a newer version survive a read and write at every level', () {
    final out = written(read(futureFile()));
    expect(out['focusMode'], {'on': true, 'until': '18:00'});
    expect((out['categories'] as List).first['icon'], isTrue);
    expect((out['stages'] as List).first['wip'], {'warn': 3});
    expect((out['templates'] as List).first['icon'], 'plane');
    expect(((out['done'] as Map)['old'] as Map)['box'], 'do');
    final task = (out['active'] as List).first as Map;
    expect(task['matrix'], 'decide');
    expect((task['attachments'] as List).single['subject'], 'Your renewal');
    expect((task['steps'] as List).first['colour'], 'blue');
    expect(((task['moves'] as List).first as Map)['by'], 'widget');
  });

  test('editing a task here keeps its newer fields, and known fields still change', () {
    final d = read(futureFile());
    final t = d.active.first
      ..title = 'Renew car insurance'
      ..starred = true;
    t.steps.first.done = true;
    t.steps.add(TaskStep.create('Pay'));
    var task = (written(d)['active'] as List).first as Map;
    expect(task['title'], 'Renew car insurance');
    expect(task['matrix'], 'decide');
    expect((task['steps'] as List).first['colour'], isNotNull);
    expect((task['steps'] as List).first['done'], isTrue);
    expect((task['steps'] as List).last.containsKey('colour'), isFalse);

    // A known field switched back off isn't brought back by the kept fields.
    t.starred = false;
    task = (written(read(written(d)))['active'] as List).first as Map;
    expect(task.containsKey('starred'), isFalse);
  });

  test('known fields never end up in the kept extras', () {
    final d = read(futureFile());
    expect(d.extra.keys, ['focusMode']);
    expect(d.active.first.extra.keys.toSet(), {'matrix', 'attachments'});
    expect(d.active.first.steps.first.extra.keys, ['colour']);
    expect(d.categories.first.extra.keys, ['icon']);
  });

  test('a merge keeps newer fields from either copy', () {
    final newer = read(futureFile());
    final older = AppData.fromJson(jsonDecode(jsonEncode(newer.toJson()))
      ..remove('focusMode'))
      ..updatedAt = DateTime.utc(2000);
    // This device changed the task more recently, still keeping the newer version's fields.
    older.active.first
      ..title = 'Changed here'
      ..touch();
    final m = mergeData(older, newer);
    expect(m.extra['focusMode'], isNotNull);
    expect(m.active.first.title, 'Changed here');
    expect(m.active.first.extra['matrix'], 'decide');
    expect(m.newestApp, '9.0.0');
  });

  test('the file records the newest version that saved it', () {
    expect(written(AppData())['newestApp'], currentAppVersion);
    expect(currentAppVersion, releases.first.version);
    final d = read(futureFile());
    expect(d.newerAppElsewhere, isTrue);
    expect(written(d)['newestApp'], '9.0.0');
    expect(AppData(newestApp: currentAppVersion).newerAppElsewhere, isFalse);
    expect(AppData(newestApp: '1.0.0').newerAppElsewhere, isFalse);
    expect(AppData().newerAppElsewhere, isFalse);
  });

  test('version names compare part by part', () {
    expect(compareVersions('1.6.2', '1.6.10'), lessThan(0));
    expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.6', '1.6.0'), 0);
    expect(compareVersions('1.6.2+3', '1.6.2'), 0);
    expect(newerVersion(null, '1.0.0'), '1.0.0');
    expect(newerVersion('2.0.0', '1.9.0'), '2.0.0');
  });

  test('sync keeps a Dropbox copy before saving over a newer version, and loses nothing', () async {
    final files = {DropboxClient.filePath: jsonEncode(futureFile())};
    final db = FakeDropbox(files);
    final s = AppStore()..dropbox = db;
    s.addTask('Added on the old device');
    await s.sync();
    expect(db.backups, hasLength(1));
    expect(jsonDecode(db.backups.single)['focusMode'], isNotNull);
    final up = jsonDecode(files[DropboxClient.filePath]!) as Map;
    expect(up['focusMode'], {'on': true, 'until': '18:00'});
    expect(up['newestApp'], '9.0.0');
    final titles = [for (final t in up['active'] as List) t['title']];
    expect(titles, containsAll(['Renew insurance', 'Added on the old device']));
    expect((up['active'] as List).firstWhere((t) => t['title'] == 'Renew insurance')['matrix'], 'decide');
    expect(s.data.newerAppElsewhere, isTrue);
  });

  test('no Dropbox copy when the file came from this version or an older one', () async {
    final files = {DropboxClient.filePath: jsonEncode(AppData(newestApp: '1.5.0').toJson())};
    final db = FakeDropbox(files);
    final s = AppStore()..dropbox = db;
    s.addTask('New');
    await s.sync();
    expect(db.backups, isEmpty);
    expect(jsonDecode(files[DropboxClient.filePath]!)['newestApp'], currentAppVersion);
  });
}
