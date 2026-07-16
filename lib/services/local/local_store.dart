//local_store.dart

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// UUID v4, so locally-created ids are shaped exactly like the ones Postgres
/// hands out. Rows written offline stay valid if they are ever pushed up.
String newUuidV4() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// A tiny JSON document store on top of SharedPreferences.
///
/// Backs the app when Supabase credentials are absent, so the whole flow stays
/// runnable. Each key holds one JSON object keyed by row id — enough to stand
/// in for a table, and deliberately no more.
class LocalStore {
  static const usersKey = 'thoughtloom.users';
  static const sessionKey = 'thoughtloom.session';
  static const profilesKey = 'thoughtloom.profiles';
  static const chatsKey = 'thoughtloom.chats';
  static const messagesKey = 'thoughtloom.messages';
  static const memoryKey = 'thoughtloom.memory';

  final SharedPreferences _prefs;

  LocalStore(this._prefs);

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  Map<String, dynamic> readTable(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on FormatException {
      // A corrupt blob would otherwise wedge the app on every launch.
      return {};
    }
  }

  Future<void> writeTable(String key, Map<String, dynamic> rows) =>
      _prefs.setString(key, jsonEncode(rows));

  String? readSession() => _prefs.getString(sessionKey);

  Future<void> writeSession(String? userId) async {
    if (userId == null) {
      await _prefs.remove(sessionKey);
    } else {
      await _prefs.setString(sessionKey, userId);
    }
  }
}
