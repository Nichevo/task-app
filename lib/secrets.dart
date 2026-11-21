import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Item 114 (review item A-067): sign-ins and keys live in the system's secure store (Android
/// Keystore, iPad/Mac Keychain, Windows Credential Manager) instead of device_settings.json.
///
/// If the secure store can't be used on a device (an unsigned Mac build, say), [works] turns
/// false and the caller keeps them in device_settings.json as before, so nobody is signed out.
class Secrets {
  Secrets([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// The names kept here.
  static const dropboxRefresh = 'dropboxRefreshToken';
  static const googleRefresh = 'googleRefreshToken';
  static const googleSecret = 'googleClientSecret';

  /// Item 114 G: the Claude API key for AI step breakdown.
  static const claudeKey = 'claudeApiKey';
  static const names = [dropboxRefresh, googleRefresh, googleSecret, claudeKey];

  /// False once a read or write failed: everything then stays in the settings file.
  bool works = true;

  /// All of [names] that have a value; null when the secure store couldn't be read.
  Future<Map<String, String>?> readAll() async {
    try {
      final out = <String, String>{};
      for (final n in names) {
        final v = await _storage.read(key: n);
        if (v != null) out[n] = v;
      }
      return out;
    } catch (e) {
      debugPrint('secure storage unreadable: $e');
      works = false;
      return null;
    }
  }

  /// Saves [values] (a null value removes it). False when the secure store couldn't be written.
  Future<bool> writeAll(Map<String, String?> values) async {
    if (!works) return false;
    try {
      for (final e in values.entries) {
        if (e.value == null || e.value!.isEmpty) {
          await _storage.delete(key: e.key);
        } else {
          await _storage.write(key: e.key, value: e.value);
        }
      }
      return true;
    } catch (e) {
      debugPrint('secure storage unwritable: $e');
      works = false;
      return false;
    }
  }
}
