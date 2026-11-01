import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/csv_import.dart';
import 'package:task_blocks/location.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';

class _FakeLocation extends LocationRecorder {
  final point = GeoPoint(lat: 51.5, lng: -0.12, accuracy: 8, at: DateTime(2026, 11, 1, 9));
  int calls = 0;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<GeoPoint?> current() async {
    calls++;
    return point;
  }
}

AppData _roundTrip(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));

void main() {
  group('task source', () {
    test('typed tasks, lists and checklist steps record where they came from', () {
      final store = AppStore();
      final typed = store.addTask('Typed');
      final cal = store.addTask('Dentist', eventId: 'e1', source: TaskSource.calendar);
      final pasted = store.addMany(['One', 'Two']);
      final photo = store.addMany(['Three'], source: TaskSource.photo);
      final step = store.stepToTask(typed, store.addStep(typed, 'Sub'));
      expect(typed.source, TaskSource.typed);
      expect(cal.source, TaskSource.calendar);
      expect(pasted.map((t) => t.source), everyElement(TaskSource.paste));
      expect(photo.single.source, TaskSource.photo);
      expect(step.source, TaskSource.step);
    });

    test('a repeat of a task is marked as a repeat', () {
      final store = AppStore();
      final t = store.addTask('Bins', due: DateTime(2026, 11, 3, 8))..repeat = const Repeat(unit: RepeatUnit.week);
      final next = store.complete(t)!;
      expect(next.source, TaskSource.repeat);
    });

    test('survives saving; old calendar tasks become Calendar, other old tasks Unknown', () {
      final d = AppData(active: [Task.create('x', source: 'zapier')]);
      expect(_roundTrip(d).active.single.source, 'zapier');
      final oldCal = Task.fromJson({'id': '1', 'title': 'a', 'createdAt': '2026-01-01T00:00:00', 'eventId': 'e'});
      final old = Task.fromJson({'id': '2', 'title': 'b', 'createdAt': '2026-01-01T00:00:00'});
      expect(oldCal.source, TaskSource.calendar);
      expect(old.source, isNull);
      expect(TaskSource.label(old.source), 'Unknown');
      expect(TaskSource.label('zapier'), 'Zapier');
      expect(TaskSource.label(TaskSource.calendar), 'Calendar');
    });

    test('CSV export writes the source and import reads it back', () {
      final d = AppData(active: [Task.create('Dentist', source: TaskSource.calendar)]);
      final csv = buildCsv(d);
      expect(csv, contains(',Calendar\r\n'));
      final into = AppData();
      expect(importCsvText(into, csv), 1);
      expect(into.active.single.source, TaskSource.calendar);
      final plain = AppData();
      importCsvText(plain, 'Task\r\nFrom a spreadsheet\r\n');
      expect(plain.active.single.source, TaskSource.csv);
    });
  });

  group('calendar look-ahead', () {
    test('defaults to 14 days and syncs', () {
      expect(AppData().eventDays, 14);
      final d = AppData(eventDays: 90);
      expect(_roundTrip(d).eventDays, 90);
      final newer = AppData(eventDays: 30, settingsUpdatedAt: DateTime.utc(2026, 11, 2));
      expect(mergeData(d, newer).eventDays, 30);
    });
  });

  group('location', () {
    test('nothing is recorded while the setting is off', () async {
      final loc = _FakeLocation();
      final store = AppStore(location: loc);
      final t = store.addTask('Milk');
      await Future<void>.delayed(Duration.zero);
      expect(t.addedWhere, isNull);
      expect(loc.calls, 0);
    });

    test('records where a task is added and ticked off, and syncs it', () async {
      final loc = _FakeLocation();
      final store = AppStore(location: loc);
      expect(await store.setRecordLocation(true), isTrue);
      final t = store.addTask('Milk');
      await Future<void>.delayed(Duration.zero);
      expect(t.addedWhere?.lat, 51.5);
      store.complete(t);
      await Future<void>.delayed(Duration.zero);
      expect(t.doneWhere?.lng, -0.12);
      final back = _roundTrip(store.data).archived.single;
      expect(back.addedWhere?.accuracy, 8);
      expect(back.doneWhere?.lat, 51.5);
    });

    test('a tick picked up later from a widget gets no location', () async {
      final loc = _FakeLocation();
      final store = AppStore(location: loc)..recordLocation = true;
      final t = store.addTask('Milk');
      await Future<void>.delayed(Duration.zero);
      store.complete(t, at: DateTime.now().subtract(const Duration(hours: 1)));
      await Future<void>.delayed(Duration.zero);
      expect(t.doneWhere, isNull);
    });
  });
}
