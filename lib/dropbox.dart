import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Minimal Dropbox client: OAuth (PKCE, paste-the-code flow, so no secret or
/// redirect setup is needed) plus download/upload of one file in the app folder.
class DropboxClient {
  DropboxClient(this.appKey, {this.refreshToken});

  static const filePath = '/tasks.json';

  /// Lines written here by anything else (email-to-Dropbox, IFTTT…) become tasks.
  static const inboxPath = '/inbox.txt';

  final String appKey;
  String? refreshToken;
  String? _accessToken;
  DateTime _accessExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  String? _verifier;

  bool get isConnected => refreshToken != null;

  /// Page the user opens to approve access; Dropbox then shows a code to paste back.
  Uri authorizeUrl() {
    final rnd = Random.secure();
    _verifier = base64UrlEncode(List.generate(48, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final challenge =
        base64UrlEncode(sha256.convert(ascii.encode(_verifier!)).bytes).replaceAll('=', '');
    return Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': appKey,
      'response_type': 'code',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'token_access_type': 'offline',
    });
  }

  Future<void> finishAuth(String code) async {
    final res = await http.post(Uri.https('api.dropboxapi.com', '/oauth2/token'), body: {
      'code': code.trim(),
      'grant_type': 'authorization_code',
      'code_verifier': _verifier ?? '',
      'client_id': appKey,
    });
    _checkOk(res);
    _readToken(jsonDecode(res.body));
  }

  void _readToken(Map<String, dynamic> j) {
    _accessToken = j['access_token'] as String;
    _accessExpiry = DateTime.now().add(Duration(seconds: (j['expires_in'] as num? ?? 3600).toInt() - 60));
    refreshToken = j['refresh_token'] as String? ?? refreshToken;
  }

  Future<String> _token() async {
    if (_accessToken != null && DateTime.now().isBefore(_accessExpiry)) return _accessToken!;
    final res = await http.post(Uri.https('api.dropboxapi.com', '/oauth2/token'), body: {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken ?? '',
      'client_id': appKey,
    });
    _checkOk(res);
    _readToken(jsonDecode(res.body));
    return _accessToken!;
  }

  /// Returns the file contents, or null if it doesn't exist yet.
  Future<String?> download() => _download(filePath);

  Future<void> upload(String contents) => _upload(filePath, contents);

  /// Item 62: keeps a copy of [contents] in /backups before an older version of the app saves
  /// over data written by a newer one. Five slots, one per day in turn, so the last five days
  /// with such a save are kept without needing to list or delete files.
  Future<void> backup(String contents, DateTime now) {
    final day = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    return _upload('$backupFolder/tasks-backup-${day % 5 + 1}.json', contents);
  }

  static const backupFolder = '/backups';

  /// Item 48A: one-task-per-file inbox folder.
  static const inboxFolder = '/inbox';

  /// Paths of the .json files waiting in [inboxFolder] (not its sub-folders). Empty when the
  /// folder doesn't exist yet. Needs the files.metadata.read permission.
  Future<List<String>> inboxFiles() async {
    final out = <String>[];
    var res = await _rpc('/2/files/list_folder', {'path': inboxFolder}, notFoundOk: true);
    while (res != null) {
      for (final e in res['entries'] as List? ?? []) {
        final m = e as Map;
        final path = m['path_display'] as String? ?? m['path_lower'] as String?;
        if (m['.tag'] == 'file' && path != null && path.toLowerCase().endsWith('.json')) out.add(path);
      }
      res = res['has_more'] == true ? await _rpc('/2/files/list_folder/continue', {'cursor': res['cursor']}) : null;
    }
    return out;
  }

  Future<String?> downloadPath(String path) => _download(path);

  Future<void> uploadPath(String path, String contents) => _upload(path, contents);

  /// Item 69: each device's own settings, one file per kind of device.
  static const devicesFolder = '/devices';

  Future<void> delete(String path) => _rpc('/2/files/delete_v2', {'path': path}, notFoundOk: true);

  /// Moves a file that couldn't be read to inbox/failed, so it isn't tried again and again.
  Future<void> moveToFailed(String path) => _rpc('/2/files/move_v2', {
        'from_path': path,
        'to_path': '$inboxFolder/failed/${path.split('/').last}',
        'autorename': true,
      }, notFoundOk: true);

  Future<Map<String, dynamic>?> _rpc(String endpoint, Map<String, dynamic> body, {bool notFoundOk = false}) async {
    final res = await http.post(Uri.https('api.dropboxapi.com', endpoint),
        headers: {'Authorization': 'Bearer ${await _token()}', 'Content-Type': 'application/json'},
        body: jsonEncode(body));
    if (notFoundOk && res.statusCode == 409 && res.body.contains('not_found')) return null;
    _checkOk(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// The inbox file, or null when it is missing or empty.
  Future<String?> downloadInbox() async {
    final text = await _download(inboxPath);
    return text == null || text.trim().isEmpty ? null : text;
  }

  /// Empties the inbox (keeps the file so it's easy to find and write to again).
  Future<void> clearInbox() => _upload(inboxPath, '');

  Future<String?> _download(String path) async {
    final res = await http.post(Uri.https('content.dropboxapi.com', '/2/files/download'), headers: {
      'Authorization': 'Bearer ${await _token()}',
      'Dropbox-API-Arg': jsonEncode({'path': path}),
    });
    if (res.statusCode == 409 && res.body.contains('not_found')) return null;
    _checkOk(res);
    return utf8.decode(res.bodyBytes);
  }

  Future<void> _upload(String path, String contents) async {
    final res = await http.post(Uri.https('content.dropboxapi.com', '/2/files/upload'),
        headers: {
          'Authorization': 'Bearer ${await _token()}',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({'path': path, 'mode': 'overwrite', 'mute': true}),
        },
        body: utf8.encode(contents));
    _checkOk(res);
  }

  static void _checkOk(http.Response res) {
    if (res.statusCode != 200) {
      throw DropboxException('Dropbox error ${res.statusCode}: ${res.body}');
    }
  }
}

class DropboxException implements Exception {
  DropboxException(this.message);
  final String message;
  @override
  String toString() => message;
}
