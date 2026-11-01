import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/places.dart';
import 'package:task_blocks/store.dart';

void main() {
  test('33 a task keeps its place reminder through JSON and into the next repeat', () {
    final t = Task.create('Take bins out')
      ..place = 'Home'
      ..placeLeave = true
      ..repeat = const Repeat(unit: RepeatUnit.week);
    final back = Task.fromJson(jsonDecode(jsonEncode(t.toJson())));
    expect(back.place, 'Home');
    expect(back.placeLeave, isTrue);
    final next = t.nextRepeat(DateTime.now());
    expect(next.place, 'Home');
    expect(next.placeLeave, isTrue);
    expect(Task.fromJson(Task.create('x').toJson()).place, isNull);
  });

  test('33 places round trip; renaming a place moves its tasks along', () async {
    final p = Place.create('Home', -36.85, 174.76, radius: 250);
    final back = Place.tryParse(jsonDecode(jsonEncode(p.toJson())))!;
    expect((back.name, back.lat, back.radius), ('Home', -36.85, 250));
    expect(Place.tryParse({'name': 'x'}), isNull);

    final s = AppStore();
    s.places.add(p);
    final t = s.addTask('Water plants')..place = 'Home';
    await s.updatePlace(p, name: 'House');
    expect(p.name, 'House');
    expect(t.place, 'House');
  });

  test('46 restoring a backup replaces the data and wins over a later sync', () async {
    final s = AppStore();
    final kept = s.addTask('In the backup');
    final backup = s.backupText();
    final added = s.addTask('Added after the backup');
    kept.title = 'Renamed after the backup';
    s.changed(task: kept);
    final remote = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())));

    await s.restoreBackup(backup);
    expect(s.data.active.map((t) => t.title), ['In the backup']);
    expect(s.data.deleted.containsKey(added.id), isTrue);

    // Dropbox still has the newer copy from before the restore: the restore must win.
    final merged = mergeData(s.data, remote);
    expect(merged.active.map((t) => t.title), ['In the backup']);

    expect(() => s.restoreBackup('not json'), throwsA(anything));
  });
}
