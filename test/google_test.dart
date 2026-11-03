import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_blocks/csv_export.dart';
import 'package:task_blocks/csv_import.dart';
import 'package:task_blocks/google.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/screens/starred_page.dart';
import 'package:task_blocks/store.dart';

Map<String, dynamic> gmailJson(String id, {String subject = 'Pay council tax friday', String from = 'Me <me@example.com>'}) => {
      'id': id,
      'threadId': 't$id',
      'labelIds': ['STARRED', 'INBOX'],
      'snippet': 'Reminder: it&#39;s due &amp; overdue soon',
      'internalDate': '${DateTime(2026, 11, 2, 9).millisecondsSinceEpoch}',
      'payload': {
        'headers': [
          {'name': 'Subject', 'value': subject},
          {'name': 'From', 'value': from},
        ],
      },
    };

/// A fake Google: answers the token, list, get, modify and label calls, and records them.
class FakeGoogle {
  final calls = <http.Request>[];
  final labels = <Map<String, dynamic>>[
    {'id': 'INBOX', 'name': 'INBOX'},
  ];
  bool expired = false;

  late final client = MockClient((req) async {
    calls.add(req);
    final path = req.url.path;
    if (path == '/token') {
      if (expired) return http.Response('{"error":"invalid_grant"}', 400);
      return http.Response(jsonEncode({'access_token': 'acc', 'expires_in': 3600, 'refresh_token': 'ref'}), 200);
    }
    if (path.endsWith('/profile')) return http.Response('{"emailAddress":"me@example.com"}', 200);
    if (path.endsWith('/messages')) {
      return http.Response(jsonEncode({
        'messages': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      }), 200);
    }
    if (path.endsWith('/modify')) return http.Response('{}', 200);
    if (path.endsWith('/labels') && req.method == 'GET') return http.Response(jsonEncode({'labels': labels}), 200);
    if (path.endsWith('/labels')) {
      final made = {'id': 'Label_1', 'name': (jsonDecode(req.body) as Map)['name']};
      labels.add(made);
      return http.Response(jsonEncode(made), 200);
    }
    final id = path.split('/').last;
    return http.Response(jsonEncode(gmailJson(id, subject: 'Email $id')), 200);
  });

  GoogleClient signedIn() => GoogleClient('id', 'secret', refreshToken: 'ref', email: 'me@example.com', client: client);
}

GmailMessage msg(String id, {String subject = 'Pay council tax friday #Home'}) =>
    GmailMessage.fromJson(gmailJson(id, subject: subject));

void main() {
  group('Gmail messages', () {
    test('headers, date, sender and the escaped snippet are read', () {
      final m = GmailMessage.fromJson(gmailJson('x', from: '"Council Tax" <Tax@Council.example>'));
      expect(m.subject, 'Pay council tax friday');
      expect(m.sender, 'Council Tax');
      expect(m.address, 'tax@council.example');
      expect(m.snippet, "Reminder: it's due & overdue soon");
      expect(m.date, DateTime(2026, 11, 2, 9));
      expect(m.starred, isTrue);
      expect(GmailMessage.fromJson(gmailJson('y', from: 'plain@example.com')).sender, 'plain@example.com');
    });
  });

  group('Google client', () {
    test('starred asks Gmail for starred emails in the look-back and reads each one', () async {
      final g = FakeGoogle();
      final list = await g.signedIn().starred(days: 30);
      expect([for (final m in list) m.subject], ['Email a', 'Email b']);
      final search = g.calls.firstWhere((c) => c.url.path.endsWith('/messages'));
      expect(search.url.queryParameters['q'], 'is:starred newer_than:30d');
      final get = g.calls.firstWhere((c) => c.url.path.endsWith('/messages/a'));
      expect(get.url.queryParametersAll['metadataHeaders'], ['Subject', 'From', 'Date']);
      expect(get.headers['Authorization'], 'Bearer acc');
    });

    test('"All" leaves out the date limit', () async {
      final g = FakeGoogle();
      await g.signedIn().search('is:starred');
      expect(g.calls.last.url.queryParameters['q'], 'is:starred');
    });

    test('a refused refresh token says the device was signed out', () async {
      final g = FakeGoogle()..expired = true;
      await expectLater(g.signedIn().starred(),
          throwsA(isA<GoogleException>().having((e) => e.signedOut, 'signedOut', isTrue)));
    });

    test('the Tasked label is found or made', () async {
      final g = FakeGoogle();
      final c = g.signedIn();
      expect(await c.labelId('Tasked'), 'Label_1');
      expect(await c.labelId('tasked'), 'Label_1');
      expect(g.calls.where((r) => r.method == 'POST' && r.url.path.endsWith('/labels')), hasLength(1));
    });

    test('sign-in opens Google, takes the answer on 127.0.0.1 and keeps the refresh token', () async {
      final g = FakeGoogle();
      final c = GoogleClient('my-id', 'my-secret', client: g.client);
      await c.signIn((url) async {
        expect(url.host, 'accounts.google.com');
        expect(url.queryParameters['scope'], GoogleClient.scope);
        expect(url.queryParameters['code_challenge_method'], 'S256');
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        expect(redirect.host, '127.0.0.1');
        // The browser, sent back by Google. A request without the right state is ignored.
        // A real client (the test binding answers 400 to everything otherwise).
        final http = HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
        final stray = await http.getUrl(redirect.replace(path: '/favicon.ico'));
        expect((await stray.close()).statusCode, 404);
        final req = await http.getUrl(redirect.replace(queryParameters: {'code': 'the-code', 'state': url.queryParameters['state']}));
        final res = await req.close();
        expect(await res.transform(utf8.decoder).join(), contains('Signed in'));
        http.close();
      });
      expect(c.refreshToken, 'ref');
      expect(c.email, 'me@example.com');
      final token = g.calls.firstWhere((r) => r.url.path == '/token');
      expect(token.bodyFields['code'], 'the-code');
      expect(token.bodyFields['client_secret'], 'my-secret');
      expect(token.bodyFields['code_verifier'], isNotEmpty);
    });
  });

  group('starred emails on tasks', () {
    test('make task keeps the email and its source; the email then counts as used', () {
      final s = AppStore();
      final t = s.addTaskFromEmail(msg('a'), title: 'Pay council tax');
      expect(t.source, TaskSource.starredEmail);
      expect(t.emails.single.subject, 'Pay council tax friday #Home');
      expect(t.emails.single.link.toString(), 'https://mail.google.com/mail/u/0/#all/ta');
      expect(s.data.taskForEmail('a'), t);
      expect(s.data.taskForEmail('b'), isNull);
    });

    test('attach adds the email once; remove takes it off', () {
      final s = AppStore();
      final t = s.addTask('Renew insurance');
      s.attachEmail(t, msg('a'));
      s.attachEmail(t, msg('a'));
      s.attachEmail(t, msg('b'));
      expect(t.emails.map((e) => e.id), ['a', 'b']);
      s.removeEmail(t, t.emails.first);
      expect(t.emails.map((e) => e.id), ['b']);
    });

    test('only a short snippet is stored', () {
      final long = GmailMessage.fromJson({...gmailJson('a'), 'snippet': 'x' * 1000});
      expect(AppStore.emailOf(long).snippet.length, lessThan(310));
    });

    test('emails survive a save and sync merge; hidden emails join from both devices', () {
      final s = AppStore();
      s.attachEmail(s.addTask('Renew'), msg('a'));
      s.hideEmail('z1');
      final copy = AppData.fromJson(jsonDecode(jsonEncode(s.data.toJson())));
      expect(copy.active.single.emails.single.from, 'Me <me@example.com>');
      final other = AppData(hiddenEmails: {'z2'});
      expect(mergeData(copy, other).hiddenEmails, {'z1', 'z2'});
    });

    test('the star is removed, and Tasked added, when Settings says so', () async {
      final g = FakeGoogle();
      final s = AppStore()..google = g.signedIn();
      s.data.starredAfter = StarredAfter.keep;
      s.addTaskFromEmail(msg('a'), title: 'One');
      await Future<void>.delayed(Duration.zero);
      expect(g.calls.where((c) => c.url.path.endsWith('/modify')), isEmpty);

      s.data.starredAfter = StarredAfter.unstarLabel;
      s.attachEmail(s.data.active.first, msg('b'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final mod = g.calls.singleWhere((c) => c.url.path.endsWith('/messages/b/modify'));
      expect(jsonDecode(mod.body), {'addLabelIds': ['Label_1'], 'removeLabelIds': ['STARRED']});
    });

    test('starredWaiting leaves out used and hidden emails', () async {
      final g = FakeGoogle();
      final s = AppStore()..google = g.signedIn();
      expect(await s.starredWaiting(), 2);
      s.hideEmail('a');
      expect(await s.starredWaiting(), 1);
      s.attachEmail(s.addTask('X'), msg('b'));
      expect(await s.starredWaiting(), 0);
      expect(await AppStore().starredWaiting(), isNull);
    });

    test('export writes emails.csv and import puts the emails back on their tasks', () {
      final s = AppStore();
      final t = s.addTask('Renew insurance');
      s.attachEmail(t, msg('a', subject: 'Quote, with "commas"'));
      expect(buildCsv(s.data).split('\r\n')[1], endsWith(',1,,'));
      final csv = buildEmailsCsv(s.data)!;
      expect(csv.split('\r\n').first, emailsHeader.join(','));
      expect(isEmailsCsv(csv), isTrue);
      expect(isEmailsCsv(buildCsv(s.data)), isFalse);
      expect(buildEmailsCsv(AppData()), isNull);

      t.emails.clear();
      expect(importEmailsCsvText(s.data, csv), 1);
      expect(t.emails.single.subject, 'Quote, with "commas"');
      expect(t.emails.single.threadId, 'ta');
      expect(importEmailsCsvText(s.data, csv), 0);
    });
  });

  group('Starred emails page', () {
    testWidgets('lists emails; Make task reads the date and category; used ones say so', (tester) async {
      final s = AppStore();
      s.data.categories.add(TaskCategory(id: 'h', name: 'Home'));
      final emails = [msg('a'), msg('b', subject: 'Insurance renewal'), msg('c', subject: 'Hide me')];
      await tester.pumpWidget(MaterialApp(home: StarredPage(store: s, loader: () async => emails)));
      await tester.pumpAndSettle();
      expect(find.text('Insurance renewal'), findsOneWidget);
      expect(find.text('Make task'), findsNWidgets(3));

      await tester.tap(find.text('Make task').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      final t = s.data.active.single;
      expect(t.title, 'Pay council tax');
      expect(t.categoryId, 'h');
      expect(t.dueAt, isNotNull);
      expect(find.text('Task: Pay council tax'), findsOneWidget);

      await tester.tap(find.text('Attach to task').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay council tax').last);
      await tester.pumpAndSettle();
      expect(find.text('Attached to: Pay council tax'), findsOneWidget);
      expect(t.emails.map((e) => e.id), ['a', 'b']);

      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(find.text('Hide me'), findsNothing);
      expect(s.data.hiddenEmails, {'c'});
    });

    testWidgets('without Google sign-in it points to Settings', (tester) async {
      await tester.pumpWidget(MaterialApp(home: StarredPage(store: AppStore())));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign in to Google in Settings'), findsOneWidget);
    });
  });
}

class _RealHttp extends HttpOverrides {}
