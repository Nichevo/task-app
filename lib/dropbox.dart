import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Minimal Dropbox client: OAuth (PKCE, paste-the-code flow, so no secret or
/// redirect setup is needed) plus download/upload of one file in the app folder.
class DropboxClient {
  DropboxClient(this.appKey, {this.refreshToken});

  static const filePath = '/tasks.json';

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
  Future<String?> download() async {
    final res = await http.post(Uri.https('content.dropboxapi.com', '/2/files/download'), headers: {
      'Authorization': 'Bearer ${await _token()}',
      'Dropbox-API-Arg': jsonEncode({'path': filePath}),
    });
    if (res.statusCode == 409 && res.body.contains('not_found')) return null;
    _checkOk(res);
    return utf8.decode(res.bodyBytes);
  }

  Future<void> upload(String contents) async {
    final res = await http.post(Uri.https('content.dropboxapi.com', '/2/files/upload'),
        headers: {
          'Authorization': 'Bearer ${await _token()}',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({'path': filePath, 'mode': 'overwrite', 'mute': true}),
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
