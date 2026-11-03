import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_blocks/dropbox.dart';
import 'package:task_blocks/google.dart';
import 'package:task_blocks/inbox_files.dart';
import 'package:task_blocks/models.dart';
import 'package:task_blocks/store.dart';

/// Dropbox stand-in with a main file and an inbox/ folder.
class FolderDropbox extends DropboxClient {
  FolderDropbox(this.inbox, {this.noScope = false}) : super('key', refreshToken: 'token');

  final Map<String, String> inbox;
  final bool noScope;
  String? main;
  final failed = <String>[];

  @override
  Future<String?> download() async => main;

  @override
  Future<void> upload(String contents) async => main = contents;

  @override
  Future<String?> downloadInbox() async => null;

  @override
  Future<void> clearInbox() async {}

  @override
  Future<List<String>> inboxFiles() async {
    if (noScope) throw DropboxException('Dropbox error 401: {"error": {".tag": "missing_scope"}}');
    return inbox.keys.toList();
  }

  /// Files outside the inbox folder (device settings backups).
  final other = <String, String>{};

  @override
  Future<String?> downloadPath(String path) async => inbox[path] ?? other[path];

  @override
  Future<void> uploadPath(String path, String contents) async => other[path] = contents;

  @override
  Future<void> delete(String path) async => inbox.remove(path);

  @override
  Future<void> moveToFailed(String path) async {
    inbox.remove(path);
    failed.add(path);
  }
}

Map<String, dynamic> mail(String id, String subject, String from,
        {List<String> labels = const ['INBOX'], String auth = ''}) =>
    {
      'id': id,
      'threadId': 't$id',
      'labelIds': labels,
      'snippet': 'snippet $id',
      'internalDate': '${DateTime.now().millisecondsSinceEpoch}',
      'payload': {
        'headers': [
          {'name': 'Subject', 'value': subject},
          {'name': 'From', 'value': from},
          if (auth.isNotEmpty) {'name': 'Authentication-Results', 'value': auth},
        ],
      },
    };

const pass = 'mx.google.com; dkim=pass header.i=@work.example header.s=s1; spf=pass smtp.mailfrom=me@work.example';

/// Gmail stand-in holding [messages]; records modify calls.
class FakeGmail {
  FakeGmail(this.messages);

  final Map<String, Map<String, dynamic>> messages;
  final modified = <String, Map<String, dynamic>>{};
  String? lastQuery;
  var fetched = 0;
  var labelLists = 0;

  late final client = MockClient((req) async {
    final path = req.url.path;
    if (path == '/token') return http.Response('{"access_token":"a","expires_in":3600}', 200);
    if (path.endsWith('/labels') && req.method == 'GET') {
      labelLists++;
      return http.Response(jsonEncode({
        'labels': [
          {'id': 'L_task', 'name': 'Task'},
          {'id': 'L_tasked', 'name': 'Tasked'},
        ],
      }), 200);
    }
    if (path.endsWith('/messages')) {
      lastQuery = req.url.queryParameters['q'];
      return http.Response(jsonEncode({
        'messages': [for (final id in messages.keys) {'id': id}],
      }), 200);
    }
    if (path.endsWith('/modify')) {
      modified[path.split('/')[path.split('/').length - 2]] = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response('{}', 200);
    }
    fetched++;
    return http.Response(jsonEncode(messages[path.split('/').last]), 200);
  });
}

AppStore storeWith(FakeGmail g, {List<String> allowed = const ['me@work.example']}) {
  final s = AppStore()
    ..google = GoogleClient('id', 'secret', refreshToken: 'r', email: 'me@gmail.example', client: g.client);
  s.data.emailTasks = true;
  s.data.allowedSenders.addAll(allowed);
  s.data.categories.add(TaskCategory(id: 'h', name: 'Home'));
  return s;
}

void main() {
  group('inbox folder files (48A)', () {
    test('one task with every field', () {
      final d = AppData();
      final added = addInboxFile(d, inboxExample, DateTime(2026, 11, 3));
      final t = added.single;
      expect(t.title, 'Renew car insurance');
      expect(t.notes, 'Quote from the broker');
      expect(t.dueAt, DateTime.utc(2026, 11, 20, 9).toLocal());
      expect(d.category(t.categoryId)!.name, 'Admin');
      expect(t.steps.map((s) => s.title), ['Get quotes', 'Pay']);
      expect(t.source, 'zapier');
      expect(t.sourceRef, 'zap-7731-msg-1842');
      expect(d.active, contains(t));
    });

    test('a list, a plain date at 9am, a url in the notes, dates read from the title', () {
      final d = AppData();
      final added = addInboxFile(d, jsonEncode([
        {'title': 'Plain date', 'due': '2026-11-20', 'url': 'https://example.com/x'},
        {'title': 'Ring the vet tomorrow'},
      ]), DateTime(2026, 11, 3, 10));
      expect(added, hasLength(2));
      expect(added[0].dueAt, DateTime(2026, 11, 20, 9));
      expect(added[0].notes, 'https://example.com/x');
      expect(added[0].source, TaskSource.inbox);
      expect(added[1].title, 'Ring the vet');
      expect(added[1].dueAt?.day, 4);
    });

    test('the same source and ref is only added once', () {
      final d = AppData();
      addInboxFile(d, inboxExample, DateTime.now());
      expect(addInboxFile(d, inboxExample, DateTime.now()), isEmpty);
      expect(d.active, hasLength(1));
    });

    test('a bad entry adds nothing from the file', () {
      final d = AppData();
      expect(() => addInboxFile(d, '[{"title":"ok"},{"notes":"no title"}]', DateTime.now()), throwsFormatException);
      expect(() => addInboxFile(d, 'not json', DateTime.now()), throwsFormatException);
      expect(d.active, isEmpty);
    });

    test('sync takes the files, deletes them and sets bad ones aside', () async {
      final db = FolderDropbox({
        '/inbox/a.json': inboxExample,
        '/inbox/b.json': '{"title": "Second"}',
        '/inbox/bad.json': '{oops',
      });
      final s = AppStore()..dropbox = db;
      await s.sync();
      expect(s.data.active.map((t) => t.title), containsAll(['Renew car insurance', 'Second']));
      expect(db.inbox, isEmpty);
      expect(db.failed, ['/inbox/bad.json']);
      expect(jsonDecode(db.main!)['active'], hasLength(2));
    });

    test('without the Dropbox permission sync still works and Settings explains', () async {
      final db = FolderDropbox({}, noScope: true);
      final s = AppStore()..dropbox = db;
      s.addTask('Local');
      await s.sync();
      expect(s.syncStatus, startsWith('Synced'));
      expect(s.inboxFolderNote, contains('files.metadata.read'));
    });

    test('two devices adding the same item before syncing end up with one', () {
      final a = AppData(), b = AppData();
      addInboxFile(a, inboxExample, DateTime(2026, 11, 3, 9));
      addInboxFile(b, inboxExample, DateTime(2026, 11, 3, 10));
      final m = mergeData(a, b);
      expect(m.active, hasLength(1));
      expect(m.active.single.id, a.active.single.id);
      expect(m.deleted.keys, contains(b.active.single.id));
    });
  });

  group('allowed senders and the sender check (54)', () {
    test('exact addresses, and whole domains only when written with @', () {
      final d = AppData(allowedSenders: ['me@work.example', '@home.example']);
      expect(d.senderAllowed('ME@work.example'), isTrue);
      expect(d.senderAllowed('boss@work.example'), isFalse);
      expect(d.senderAllowed('anyone@home.example'), isTrue);
      expect(d.senderAllowed('x@nothome.example'), isFalse);
    });

    test("Gmail's SPF or DKIM pass must be for the sender's own domain", () {
      GmailMessage m(String from, String auth) => GmailMessage.fromJson(mail('x', 's', from, auth: auth));
      expect(m('Me <me@work.example>', pass).senderVerified, isTrue);
      expect(m('me@work.example', 'dkim=pass header.d=work.example').senderVerified, isTrue);
      expect(m('me@work.example', 'spf=pass smtp.mailfrom=bounce@mail.work.example').senderVerified, isTrue);
      expect(m('me@work.example', 'dkim=pass header.i=@evil.example; spf=fail').senderVerified, isFalse);
      expect(m('me@work.example', 'spf=softfail smtp.mailfrom=me@work.example').senderVerified, isFalse);
      expect(m('me@work.example', '').senderVerified, isFalse);
    });
  });

  group('emails to tasks (54)', () {
    test('only allowed, checked senders with "Task" at the start of the subject (or the label) become tasks', () async {
      final g = FakeGmail({
        'a': mail('a', 'Task: Pay council tax friday #Home', 'Me <me@work.example>', auth: pass),
        'b': mail('b', 'Task: buy a gift card', 'Stranger <x@spam.example>', auth: pass),
        'c': mail('c', 'Task - send money', 'Me <me@work.example>', auth: 'spf=fail smtp.mailfrom=me@work.example'),
        'd': mail('d', 'About the task force', 'Me <me@work.example>', auth: pass),
        'e': mail('e', 'Renew insurance', 'Me <me@work.example>', labels: ['INBOX', 'L_task'], auth: pass),
        'f': mail('f', 'task fix the gate', 'me@gmail.example', labels: ['SENT'], auth: ''),
      });
      final s = storeWith(g, allowed: ['me@work.example', 'me@gmail.example']);
      expect(await s.checkEmailTasks(), 3);
      expect(g.lastQuery, contains('-label:tasked'));

      final byRef = {for (final t in s.data.active) t.sourceRef: t};
      expect(byRef.keys.toSet(), {'a', 'e', 'f'});
      final a = byRef['a']!;
      expect(a.title, 'Pay council tax');
      expect(a.categoryId, 'h');
      expect(a.dueAt, isNotNull);
      expect(a.source, TaskSource.email);
      expect(a.emails.single.id, 'a');
      expect(byRef['f']!.title, 'fix the gate');

      expect(g.modified['a'], {'addLabelIds': ['L_tasked'], 'removeLabelIds': <String>[]});
      expect(g.modified['e'], {'addLabelIds': ['L_tasked'], 'removeLabelIds': ['L_task']});
      expect(g.modified.containsKey('b'), isFalse);

      expect({for (final i in s.ignoredEmails) i.message.id: i.reason}, {
        'b': 'Not on your allowed list',
        'c': "Failed Gmail's sender check",
      });
    });

    test('an email already made into a task is not added again', () async {
      final g = FakeGmail({'a': mail('a', 'Task: once', 'me@work.example', auth: pass)});
      final s = storeWith(g);
      expect(await s.checkEmailTasks(), 1);
      expect(await s.checkEmailTasks(force: true), 0);
      expect(s.data.active, hasLength(1));
    });

    test('nothing happens when it is off, or with no allowed senders', () async {
      final g = FakeGmail({'a': mail('a', 'Task: x', 'me@work.example', auth: pass)});
      final off = storeWith(g)..data.emailTasks = false;
      expect(await off.checkEmailTasks(), 0);
      final none = storeWith(g, allowed: []);
      expect(await none.checkEmailTasks(), 0);
      expect(none.ignoredEmails.single.reason, 'Not on your allowed list');
    });

    test('"Allow this sender" adds the address and picks the email up', () async {
      final g = FakeGmail({'b': mail('b', 'Task: from my other address', 'Me <me@other.example>',
          auth: 'dkim=pass header.i=@other.example')});
      final s = storeWith(g);
      await s.checkEmailTasks();
      expect(s.data.active, isEmpty);
      await s.allowSender(s.ignoredEmails.single.message.address);
      expect(s.data.allowedSenders, contains('me@other.example'));
      expect(s.data.active.single.title, 'from my other address');
      expect(s.ignoredEmails, isEmpty);
    });

    test('later checks don\'t fetch emails already looked at, or the labels again', () async {
      final g = FakeGmail({
        'n': mail('n', 'Your task list for today', 'Shop <news@shop.example>', auth: 'dkim=pass header.i=@shop.example'),
        'o': mail('o', 'Task: ring the vet', 'Me <me@other.example>', auth: 'dkim=pass header.i=@other.example'),
      });
      final s = storeWith(g);
      await s.checkEmailTasks();
      expect(g.fetched, 2);
      expect(g.labelLists, 2);
      expect(s.ignoredEmails, hasLength(1));
      await s.checkEmailTasks(force: true);
      expect(g.fetched, 2, reason: 'nothing fetched twice');
      expect(g.labelLists, 2);
      expect(s.ignoredEmails, hasLength(1), reason: 'the ignored list is still shown');
      await s.allowSender('me@other.example');
      expect(s.data.active.single.title, 'ring the vet');
      expect(g.fetched, 2);
    });

    test('the settings sync', () {
      final d = AppData(emailTasks: true, allowedSenders: ['me@work.example'], settingsUpdatedAt: DateTime.utc(2026));
      final copy = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(copy.emailTasks, isTrue);
      expect(mergeData(AppData(), copy).allowedSenders, ['me@work.example']);
    });
  });
}
