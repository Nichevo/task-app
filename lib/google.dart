import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Where Google sign-in is offered: phone, Windows and Mac (and Linux); the iPad comes later.
bool get googleSupported => Platform.isAndroid || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Item 53: Google sign-in and the few Gmail calls the app needs.
///
/// Uses Google's flow for installed apps: the browser opens Google's sign-in page and sends the
/// answer back to a small web server the app runs on this device for a moment (127.0.0.1), with
/// PKCE. The OAuth client is a "Desktop app" client the owner creates in Google Cloud; its id and
/// secret are typed into Settings and stay on the device (Google says the secret of an installed
/// app's client isn't treated as secret). The refresh token is device-only too, never synced.
class GoogleClient {
  GoogleClient(this.clientId, this.clientSecret, {this.refreshToken, this.email, http.Client? client})
      : _http = client ?? http.Client();

  final String clientId;
  final String clientSecret;
  String? refreshToken;

  /// The signed-in Gmail address.
  String? email;

  final http.Client _http;
  String? _accessToken;
  DateTime _accessExpiry = DateTime.fromMillisecondsSinceEpoch(0);

  /// Read emails and change their labels and stars. It can't send or delete mail.
  static const scope = 'https://www.googleapis.com/auth/gmail.modify';

  bool get isConnected => refreshToken != null;

  /// Opens Google's sign-in page with [open] and waits (up to 5 minutes) for the answer.
  Future<void> signIn(Future<void> Function(Uri url) open) async {
    final rnd = Random.secure();
    final verifier = base64UrlEncode(List.generate(48, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = base64UrlEncode(List.generate(16, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    // Listen before opening the browser, so the answer can't arrive before anyone is waiting.
    final answer = Completer<Map<String, String>>();
    final sub = server.listen((req) async {
      final q = req.uri.queryParameters;
      if (q['state'] != state || answer.isCompleted) {
        // Something else asking (a browser's favicon request, say).
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType.html;
      req.response.write('<html><body style="font-family:sans-serif;padding:2em">'
          '<h2>${q['code'] != null ? 'Signed in' : 'Not signed in'}</h2>'
          '<p>You can close this page and go back to Task Blocks.</p></body></html>');
      await req.response.close();
      answer.complete(q);
    });
    try {
      await open(Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      }));
      final q = await answer.future.timeout(const Duration(minutes: 5));
      final code = q['code'], error = q['error'];
      if (code == null) throw GoogleException(error == null ? 'Sign-in was cancelled' : 'Google said: $error');
      final res = await _http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      });
      _checkOk(res);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      refreshToken = j['refresh_token'] as String?;
      if (refreshToken == null) throw GoogleException('Google gave no refresh token; try signing in again');
      _readToken(j);
      final profile = await _get('/gmail/v1/users/me/profile');
      email = profile['emailAddress'] as String?;
    } on TimeoutException {
      throw GoogleException('Sign-in took too long; try again');
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  }

  /// Signs out on Google's side too (best effort) and forgets the tokens.
  Future<void> signOut() async {
    final token = refreshToken;
    refreshToken = null;
    email = null;
    _accessToken = null;
    if (token == null) return;
    try {
      await _http.post(Uri.https('oauth2.googleapis.com', '/revoke'), body: {'token': token});
    } catch (_) {}
  }

  void _readToken(Map<String, dynamic> j) {
    _accessToken = j['access_token'] as String?;
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _accessExpiry = DateTime.now().add(Duration(seconds: secs - 60));
  }

  Future<String> _token() async {
    if (_accessToken != null && DateTime.now().isBefore(_accessExpiry)) return _accessToken!;
    if (refreshToken == null) throw GoogleException('Not signed in to Google');
    final res = await _http.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': refreshToken!,
      'grant_type': 'refresh_token',
    });
    if (res.statusCode == 400 && res.body.contains('invalid_grant')) {
      throw GoogleException('Google signed this device out. Sign in again in Settings, Google.', signedOut: true);
    }
    _checkOk(res);
    _readToken(jsonDecode(res.body) as Map<String, dynamic>);
    return _accessToken!;
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async {
    final res = await _http.get(Uri.https('gmail.googleapis.com', path, query),
        headers: {'Authorization': 'Bearer ${await _token()}'});
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _http.post(Uri.https('gmail.googleapis.com', path),
        headers: {'Authorization': 'Bearer ${await _token()}', 'Content-Type': 'application/json'},
        body: jsonEncode(body));
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Ids of the messages matching a Gmail search ([query], e.g. `is:starred newer_than:30d`),
  /// newest first, at most [max].
  Future<List<String>> search(String query, {int max = 100}) async {
    final ids = <String>[];
    String? page;
    do {
      final j = await _get('/gmail/v1/users/me/messages', {
        'q': query,
        'maxResults': '${min(max - ids.length, 100)}',
        'pageToken': ?page,
      });
      for (final m in j['messages'] as List? ?? []) {
        ids.add((m as Map)['id'] as String);
      }
      page = j['nextPageToken'] as String?;
    } while (page != null && ids.length < max);
    return ids;
  }

  /// The headers and snippet of one message. [checkSender] also fetches Gmail's sender check
  /// (the Authentication-Results header), for item 54.
  Future<GmailMessage> message(String id, {bool checkSender = false}) async {
    final j = await _get('/gmail/v1/users/me/messages/$id', {
      'format': 'metadata',
      'metadataHeaders': ['Subject', 'From', 'Date', if (checkSender) 'Authentication-Results'],
    });
    return GmailMessage.fromJson(j);
  }

  /// Starred emails from the last [days] days (0 for all), newest first.
  Future<List<GmailMessage>> starred({int days = 30, int max = 100}) async {
    final ids = await search(days > 0 ? 'is:starred newer_than:${days}d' : 'is:starred', max: max);
    final out = <GmailMessage>[];
    // A few at a time, so a long list loads quickly without hammering Gmail.
    for (var i = 0; i < ids.length; i += 8) {
      out.addAll(await Future.wait([for (final id in ids.skip(i).take(8)) message(id)]));
    }
    return out;
  }

  /// Adds and removes labels on a message. STARRED is the star.
  Future<void> modify(String id, {List<String> add = const [], List<String> remove = const []}) =>
      _post('/gmail/v1/users/me/messages/$id/modify', {'addLabelIds': add, 'removeLabelIds': remove});

  /// The id of the label called [name], made if it doesn't exist yet.
  Future<String> labelId(String name) async {
    final j = await _get('/gmail/v1/users/me/labels');
    for (final l in j['labels'] as List? ?? []) {
      if ((l as Map)['name'].toString().toLowerCase() == name.toLowerCase()) return l['id'] as String;
    }
    final made = await _post('/gmail/v1/users/me/labels',
        {'name': name, 'labelListVisibility': 'labelShow', 'messageListVisibility': 'show'});
    return made['id'] as String;
  }

  static void _checkOk(http.Response res) {
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw GoogleException('Google error ${res.statusCode}: ${res.body}');
    }
  }
}

class GoogleException implements Exception {
  GoogleException(this.message, {this.signedOut = false});

  final String message;

  /// The refresh token stopped working; the device has to sign in again.
  final bool signedOut;

  @override
  String toString() => message;
}

/// What the app reads of a Gmail message.
class GmailMessage {
  GmailMessage({
    required this.id,
    required this.threadId,
    required this.subject,
    required this.from,
    required this.date,
    required this.snippet,
    required this.labels,
    this.authResults = '',
  });

  /// Gmail's Authentication-Results header (SPF, DKIM, DMARC), when asked for.
  final String authResults;

  /// The part after @ of the sender's address.
  String get domain => address.contains('@') ? address.split('@').last : '';

  /// Item 54: Gmail's own check says the email really came from the sender's domain: SPF or
  /// DKIM passed for that domain (or one under it). The From line alone can be faked.
  bool get senderVerified {
    final d = domain;
    if (d.isEmpty) return false;
    bool matches(String? x) {
      final v = x?.toLowerCase().replaceFirst(RegExp(r'^.*@'), '') ?? '';
      return v.isNotEmpty && (v == d || d.endsWith('.$v') || v.endsWith('.$d'));
    }

    final text = authResults.toLowerCase();
    for (final m in RegExp(r'dkim=pass[^;]*?header\.(?:i|d)=([^\s;]+)').allMatches(text)) {
      if (matches(m.group(1))) return true;
    }
    for (final m in RegExp(r'spf=pass[^;]*?smtp\.mailfrom=([^\s;]+)').allMatches(text)) {
      if (matches(m.group(1))) return true;
    }
    return false;
  }

  final String id;
  final String threadId;
  final String subject;
  final String from;
  final DateTime? date;
  final String snippet;
  final Set<String> labels;

  bool get starred => labels.contains('STARRED');

  /// The sender's name if there is one, else the address.
  String get sender {
    final m = RegExp(r'^\s*"?([^"<]*?)"?\s*<([^>]+)>').firstMatch(from);
    if (m == null) return from.trim();
    final name = m.group(1)!.trim();
    return name.isEmpty ? m.group(2)!.trim() : name;
  }

  /// Just the address from the From line, lower case.
  String get address {
    final m = RegExp(r'<([^>]+)>').firstMatch(from);
    return (m?.group(1) ?? from).trim().toLowerCase();
  }

  factory GmailMessage.fromJson(Map<String, dynamic> j) {
    // A header can appear more than once (Authentication-Results often does): join them.
    final headers = <String, String>{};
    for (final h in (j['payload'] as Map?)?['headers'] as List? ?? []) {
      final name = ((h as Map)['name'] as String).toLowerCase(), value = h['value'] as String? ?? '';
      headers[name] = headers.containsKey(name) ? '${headers[name]}; $value' : value;
    }
    final ms = int.tryParse(j['internalDate']?.toString() ?? '');
    return GmailMessage(
      id: j['id'] as String,
      threadId: j['threadId'] as String? ?? j['id'] as String,
      subject: headers['subject']?.trim() ?? '',
      from: headers['from'] ?? '',
      date: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
      snippet: _unescape(j['snippet'] as String? ?? ''),
      labels: {for (final l in j['labelIds'] as List? ?? []) l as String},
      authResults: headers['authentication-results'] ?? '',
    );
  }

  /// Gmail's snippets come HTML-escaped.
  static String _unescape(String s) => s
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
