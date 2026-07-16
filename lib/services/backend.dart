//backend.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'ai_service.dart';
import 'auth_service.dart';
import 'data_service.dart';
import 'local/local_auth_service.dart';
import 'local/local_data_service.dart';
import 'local/local_store.dart';
import 'speech_service.dart';
import 'supabase/supabase_auth_service.dart';
import 'supabase/supabase_data_service.dart';

/// Chooses the backend once, at startup, and hands the rest of the app two
/// interfaces it can use without knowing which one it got.
///
/// Swapping providers later means adding an [AuthService] / [DataService] pair
/// and one branch in [init] — no screen changes.
class Backend {
  Backend._();

  static AuthService? _auth;
  static DataService? _data;
  static SpeechService? _speech;
  static AiService? _ai;
  static bool _usingSupabase = false;

  static AuthService get auth => _auth ?? _notReady();
  static DataService get data => _data ?? _notReady();

  /// Everything that needs the model, via the FastAPI service.
  ///
  /// Works only when [usingSupabase]: the API reads a chat's context from
  /// Supabase and authorises the caller by their Supabase token, neither of
  /// which the on-device backend has. Screens check [usingSupabase] and say so
  /// plainly rather than letting the call fail with a network error.
  static AiService get ai => _ai ?? _notReady();

  /// Dictation. Unlike the other two this does not vary by backend — it is the
  /// device's own recogniser either way — but it lives here so screens have one
  /// place to reach for a service and tests have one place to replace it.
  static SpeechService get speech => _speech ?? _notReady();

  /// False when running on on-device storage because no credentials were given.
  static bool get usingSupabase => _usingSupabase;

  static Never _notReady() =>
      throw StateError('Backend.init() must be awaited before use.');

  /// Awaited before `runApp`, so a restored session is readable on the first
  /// frame and the app never flashes the signed-out UI at a signed-in user.
  static Future<void> init() async {
    // Constructed, not initialised: SpeechToText.initialize() asks for the
    // microphone, and doing that at launch would prompt a user who has not yet
    // gone anywhere near dictation. The describe screen initialises it on
    // arrival instead.
    _speech = PluginSpeechService();

    if (SupabaseConfig.isConfigured) {
      // Deliberately not wrapped in a fallback: silently demoting a misconfigured
      // Supabase build to on-device storage would send real data somewhere the
      // developer never looks. Fail loudly instead.
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      final client = Supabase.instance.client;
      final auth = SupabaseAuthService(client);
      _auth = auth;
      _data = SupabaseDataService(client);
      _ai = HttpAiService(auth);
      _usingSupabase = true;
      debugPrint('ThoughtLoom: using Supabase backend.');
      return;
    }

    final store = await LocalStore.open();
    final auth = LocalAuthService(store);
    _auth = auth;
    _data = LocalDataService(store);
    // Constructed even though it cannot work here, so `Backend.ai` is never the
    // thing that explodes. The screens gate on `usingSupabase` and explain;
    // reaching the network would only produce a worse version of the same
    // message.
    _ai = HttpAiService(auth);
    _usingSupabase = false;
    debugPrint(
      'ThoughtLoom: SUPABASE_URL / SUPABASE_ANON_KEY not set — '
      'using on-device storage. Data stays on this device only.',
    );
  }

  @visibleForTesting
  static void overrideWith({
    AuthService? auth,
    DataService? data,
    SpeechService? speech,
    AiService? ai,
    bool? usingSupabase,
  }) {
    _auth = auth ?? _auth;
    _data = data ?? _data;
    _speech = speech ?? _speech;
    _ai = ai ?? _ai;
    _usingSupabase = usingSupabase ?? _usingSupabase;
  }
}
