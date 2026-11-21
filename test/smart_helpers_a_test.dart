import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/home_page.dart';
import 'package:task_blocks/screens/settings_page.dart';
import 'package:task_blocks/secrets.dart';
import 'package:task_blocks/store.dart';
import 'package:task_blocks/widgets/simple_cards.dart';

/// Item 114: update A of the smart helpers (security, the Smart helpers switches, simple view).
void main() {
  group('helpers', () {
    test('switches are on by default, saved, and merged with the settings', () {
      final d = AppData();
      expect(d.helperOn(Helper.simpleView), isTrue);
      d.helpers[Helper.simpleView] = false;
      final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(back.helperOn(Helper.simpleView), isFalse);
      expect(AppData().toJson().containsKey('helpers'), isFalse);
    });

    test('turning simple view off in Settings leaves the simple view', () {
      final s = AppStore()..setSimpleView(true);
      s.setHelper(Helper.simpleView, false);
      expect(s.simpleView, isFalse);
      expect(s.data.helperOn(Helper.simpleView), isFalse);
    });
  });

  group('simple view', () {
    String due(DateTime? d) => simpleDue(d, DateTime(2026, 11, 21, 10));
    test('due line', () {
      expect(due(null), 'No date');
      expect(due(DateTime(2026, 11, 21)), 'Due Today');
      expect(due(DateTime(2026, 11, 18)), 'Overdue · was due Wed 18');
      expect(due(DateTime(2026, 11, 21, 9)), 'Overdue · was due Today 09:00');
      expect(due(DateTime(2026, 12, 12)), 'Due Sat 12 Dec');
    });

    testWidgets('the button swaps in big cards with open steps under them, and back', (tester) async {
      final s = AppStore();
      final t = s.addTask('Write tender reply');
      t.dueAt = DateTime.now().add(const Duration(days: 3));
      t.steps.addAll([TaskStep.create('Draft pricing section'), TaskStep.create('Read brief')..done = true]);
      s.addTask('Book flights');
      tester.view.physicalSize = const Size(412, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: HomePage(store: s)));
      expect(find.byType(SimpleCards), findsNothing);
      await tester.tap(find.byTooltip('Simple view'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleCards), findsOneWidget);
      expect(find.byType(SimpleTaskCard), findsNWidgets(2));
      expect(find.text('Draft pricing section'), findsOneWidget);
      expect(find.text('Read brief'), findsNothing, reason: 'ticked steps are left out');
      expect(find.textContaining('1 of 2 steps done'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(TextField), findsNothing, reason: 'no add box');
      expect(s.simpleView, isTrue);
      await tester.tap(find.byTooltip('Back to the full list'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleCards), findsNothing);
    });

    testWidgets('two columns on a wide screen', (tester) async {
      final s = AppStore()..setSimpleView(true);
      for (final n in ['a', 'b', 'c']) {
        s.addTask(n);
      }
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SimpleCards(data: s.data, entries: [
        for (final t in s.data.active) SimpleTask(t),
      ]))));
      final xs = {for (final e in find.byType(SimpleTaskCard).evaluate()) tester.getTopLeft(find.byWidget(e.widget)).dx};
      expect(xs.length, 2);
    });

    testWidgets('Settings has the Smart helpers switch', (tester) async {
      final s = AppStore();
      await tester.pumpWidget(MaterialApp(home: SettingsPage(store: s)));
      expect(find.text('Smart helpers'), findsOneWidget);
      await tester.tap(find.text('Simple view'));
      await tester.pump();
      expect(s.data.helperOn(Helper.simpleView), isFalse);
    });
  });

  group('sign-ins in the secure store', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('tb');
      PathProviderPlatform.instance = _Paths(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('old sign-ins move out of the settings file and still work', () async {
      FlutterSecureStorage.setMockInitialValues({});
      File('${dir.path}/device_settings.json').writeAsStringSync(jsonEncode({
        'dropboxAppKey': 'key',
        'dropboxRefreshToken': 'drop-refresh',
        'googleClientId': 'id',
        'googleClientSecret': 'shh',
        'googleRefreshToken': 'g-refresh',
        'deviceKey': 'k1',
      }));
      final s = AppStore(secrets: Secrets());
      await s.load();
      await s.saveDeviceSettings();
      expect(s.dropbox?.refreshToken, 'drop-refresh');
      expect(s.google?.refreshToken, 'g-refresh');
      final file = File('${dir.path}/device_settings.json').readAsStringSync();
      expect(file, isNot(contains('refresh')));
      expect(file, isNot(contains('shh')));
      expect(jsonDecode(file)['dropboxAppKey'], 'key');

      // A fresh start reads them back from the secure store.
      final again = AppStore(secrets: Secrets());
      await again.load();
      await again.saveDeviceSettings();
      expect(again.dropbox?.refreshToken, 'drop-refresh');
      expect(again.google?.refreshToken, 'g-refresh');
      expect(again.googleClientSecret, 'shh');
    });

    test('without a secure store they stay in the file', () async {
      final s = AppStore(secrets: _Broken());
      File('${dir.path}/device_settings.json').writeAsStringSync(jsonEncode({
        'dropboxAppKey': 'key',
        'dropboxRefreshToken': 'drop-refresh',
        'deviceKey': 'k1',
      }));
      await s.load();
      await s.saveDeviceSettings();
      expect(s.dropbox?.refreshToken, 'drop-refresh');
      expect(File('${dir.path}/device_settings.json').readAsStringSync(), contains('drop-refresh'));
    });

    test('the Dropbox settings backup leaves the Google secret out', () {
      final s = AppStore()
        ..googleClientId = 'id'
        ..googleClientSecret = 'shh';
      expect(jsonEncode(s.deviceSettingsBackup()), isNot(contains('shh')));
      expect(s.deviceSettingsBackup()['googleClientId'], 'id');
    });
  });
}

class _Broken extends Secrets {
  @override
  Future<Map<String, String>?> readAll() async {
    works = false;
    return null;
  }
}

class _Paths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
