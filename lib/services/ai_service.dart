//ai_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

/// Whether the backend has answered and reported itself ready.
///
/// On Render's free tier the service sleeps after fifteen idle minutes, and the
/// first request afterwards waits out a cold start before any work begins. That
/// is a wait worth naming — see [AppWaiting], which says "waking the server up"
/// rather than "thinking" while this is false, because a wait you have been
/// given the reason for is a much shorter wait than a silent one.
///
/// Set by [AiService.warmUp], and by any real request that succeeds — a reply
/// is proof of a running server whatever the ping managed to find out.
///
/// A plain [ValueNotifier] rather than anything with a provider behind it: one
/// bool, written in one file, read by one widget.
final ValueNotifier<bool> backendWarm = ValueNotifier<bool>(false);

/// When the backend last answered anything at all.
///
/// Null until it has. Stamped by [_markWarm], which is the only place
/// [backendWarm] is set true — so the flag and the time it was earned cannot
/// drift apart.
DateTime? _lastAnswered;

void _markWarm() {
  _lastAnswered = DateTime.now();
  backendWarm.value = true;
}

/// Whether what we know about the backend is old enough to be worth rechecking.
///
/// True when it has never answered, when the last thing it did was fail, or when
/// its last reply is older than [ApiConfig.warmthGoesStaleAfter] — because
/// Render puts a free service back to sleep fifteen minutes after its last
/// request, whether or not anyone is still looking at the app.
///
/// That last clause is the whole reason this is a *time* check and not an
/// app-lifecycle one. Someone who signs in, warms the backend, and then reads
/// their dashboard for twenty minutes has a sleeping server and a
/// [backendWarm] that still says true. Meanwhile a three-second hop to another
/// app and back cannot make the last reply ten minutes old, so the same single
/// condition is what keeps a foreground flicker from re-pinging anything.
bool backendMayHaveSlept() {
  if (!backendWarm.value) return true;
  final last = _lastAnswered;
  return last == null ||
      DateTime.now().difference(last) >= ApiConfig.warmthGoesStaleAfter;
}

/// Put the warmth state back to a known point. For tests.
@visibleForTesting
void resetBackendWarmth({DateTime? lastAnswered}) {
  _lastAnswered = lastAnswered;
  backendWarm.value = lastAnswered != null;
}

/// A failure the user should see.
///
/// [retryable] separates "try again" from "this will never work". A cold Render
/// dyno and a dropped connection are retryable; being signed out is not, and
/// offering a retry button for it would just be a loop.
class AiFailure implements Exception {
  final String message;
  final bool retryable;

  const AiFailure(this.message, {this.retryable = true});

  @override
  String toString() => message;
}

/// One generated question and its options, or the model saying it has enough.
class AdaptiveTurn {
  final bool done;
  final int round;
  final String? messageId;
  final String? question;

  /// Model-generated, specific to this user. Never contains an "other" option —
  /// the free-text fallback is the app's, and is always offered.
  final List<String> options;

  /// Whether this question takes more than one answer.
  ///
  /// Decided per question by the model, because it is a property of the question
  /// and not of the screen: "which of these are you deciding between" has one
  /// answer, and "why does it feel like this" never does. Defaults false, so a
  /// server that has not been redeployed yet — or a model that omits the field —
  /// behaves exactly as it did before this existed.
  final bool multi;

  const AdaptiveTurn({
    required this.done,
    required this.round,
    this.messageId,
    this.question,
    this.options = const [],
    this.multi = false,
  });
}

class Source {
  final String title;
  final String url;

  const Source({required this.title, required this.url});

  factory Source.fromJson(Map<String, dynamic> json) => Source(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class Recommendation {
  /// The verdict, in one sentence, meant to be read alone and first.
  ///
  /// The answer used to open with whatever the model's first paragraph happened
  /// to be, which buried the actual position — the one thing the user came for —
  /// somewhere in the middle of three hundred words. Making it a separate field
  /// rather than "the first line of the body" means the model has to *commit* to
  /// a sentence that survives standing on its own.
  ///
  /// Empty against a server that predates it, in which case the body simply
  /// leads, exactly as it used to.
  final String headline;

  /// The body, in the Markdown subset [RichBody] renders.
  final String text;

  final List<String> nextSteps;
  final String confidence;

  /// Empty when the answer needed no research, which is most of the time.
  final List<Source> sources;
  final String? messageId;

  const Recommendation({
    required this.text,
    this.headline = '',
    this.nextSteps = const [],
    this.confidence = '',
    this.sources = const [],
    this.messageId,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
        headline: (json['headline'] as String? ?? '').trim(),
        text: json['recommendation'] as String? ?? '',
        nextSteps:
            (json['next_steps'] as List? ?? []).whereType<String>().toList(),
        confidence: json['confidence'] as String? ?? '',
        sources: (json['sources'] as List? ?? [])
            .whereType<Map>()
            .map((s) => Source.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
        messageId: json['message_id'] as String?,
      );
}

/// Everything that needs the model. The API does the Supabase writes for these
/// turns itself, so nothing here has a matching [DataService] call.
abstract class AiService {
  /// Records [answer] against the question it belongs to, then returns the next
  /// question — or `done`. Omit [answer] on the first call of a chat.
  ///
  /// [answer] is always the whole answer as the user gave it: for a multi-select
  /// question, the ticked options joined by [selectionSeparator]. [selections]
  /// carries the same options apart, so the server can keep them structured
  /// without either side having to parse a delimiter back out of prose the user
  /// may well have typed a semicolon into.
  Future<AdaptiveTurn> nextQuestion({
    required String chatId,
    String? answerToMessageId,
    String? answer,
    List<String>? selections,
  });

  Future<Recommendation> recommendation({required String chatId});

  Future<String> followUp({required String chatId, required String message});

  /// Closes a chat: marks it completed, and asks the API to name it and fold
  /// what it learned into the user's long-term memory.
  ///
  /// Returns as soon as the status is written — the naming and the memory merge
  /// are two model calls that run on the server *after* the response, because
  /// the user has just pressed Back and is not waiting to find out what we
  /// decided to call something they have stopped looking at.
  ///
  /// Safe to call more than once. The API skips whichever half is already done,
  /// which is what lets the history screen ask again for a chat whose title
  /// never arrived.
  Future<void> completeChat({required String chatId});

  /// Best-effort ping to wake a sleeping backend.
  ///
  /// Render's free tier puts the service to sleep after 15 minutes idle, and
  /// the first request afterwards eats close to a minute of cold start before
  /// it even starts on the model call. Firing this the moment someone is found
  /// signed in — before they've reached a screen that needs the model — lets
  /// that minute overlap with the setup questions instead of stacking on top
  /// of their first real request.
  ///
  /// Keeps asking until the server says it is *warm*, not merely reachable:
  /// the API answers `/health` as soon as the process boots, but the model
  /// client and the database session are built lazily and are seconds of work
  /// on their own. A single ping that gave up on the first answer would leave
  /// exactly that much for the user to pay. See [backendWarm].
  ///
  /// Called again whenever the app returns to the foreground and
  /// [backendMayHaveSlept] says what we know is stale — Render sleeps fifteen
  /// minutes after the last request, so an app left open long enough is
  /// looking at a cold server while still believing it warm.
  ///
  /// Never throws, and never needs awaiting: nothing here was promised to the
  /// caller, and every screen that needs the model already handles a slow or
  /// failed call on its own. Concurrent calls share one poll.
  Future<void> warmUp();
}

/// [AiService] against the FastAPI service.
class HttpAiService implements AiService {
  final AuthService _auth;
  final http.Client _client;

  HttpAiService(this._auth, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, dynamic>> _post(
    Uri url,
    Map<String, dynamic> body, {
    required Duration timeout,
  }) async {
    final token = await _auth.accessToken();
    if (token == null) {
      throw const AiFailure(
        'Please sign in again to keep going.',
        retryable: false,
      );
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AiFailure(
        'That took too long. The server may have been asleep — trying again '
        'usually works.',
      );
    } catch (e) {
      debugPrint('ThoughtLoom: request to $url failed — $e');
      throw const AiFailure(
        "Couldn't reach the server. Check your connection and try again.",
      );
    }

    // Whatever the status, the server answered — so it is awake, and a screen
    // still showing "waking the server up" should stop.
    _markWarm();

    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('ThoughtLoom: unreadable reply from $url — $e');
        throw const AiFailure('Got a confusing reply from the server.');
      }
    }

    // 401/403/404 are all "this will not work on a retry": the session is gone,
    // or this chat is not ours. Everything else — 5xx, a cold start that
    // 502'd — is worth another go.
    final fatal = response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 404;
    throw AiFailure(_detail(response), retryable: !fatal);
  }

  /// The API's own message where it sent one, since those are already written
  /// for a person to read.
  String _detail(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
    } catch (_) {
      // Fall through to the generic message.
    }
    if (response.statusCode == 401) return 'Please sign in again to keep going.';
    if (response.statusCode == 404) return 'That conversation could not be found.';
    return 'Something went wrong on our side. Please try again.';
  }

  @override
  Future<AdaptiveTurn> nextQuestion({
    required String chatId,
    String? answerToMessageId,
    String? answer,
    List<String>? selections,
  }) async {
    final json = await _post(
      ApiConfig.adaptiveQuestionUrl,
      {
        'chat_id': chatId,
        if (answer != null && answerToMessageId != null)
          'answer': {
            'message_id': answerToMessageId,
            'text': answer,
            if (selections != null && selections.isNotEmpty)
              'selections': selections,
          },
      },
      timeout: ApiConfig.requestTimeout,
    );
    return AdaptiveTurn(
      done: json['done'] as bool? ?? false,
      round: json['round'] as int? ?? 0,
      messageId: json['message_id'] as String?,
      question: json['question'] as String?,
      options: (json['options'] as List? ?? []).whereType<String>().toList(),
      multi: json['multi'] as bool? ?? false,
    );
  }

  @override
  Future<Recommendation> recommendation({required String chatId}) async {
    final json = await _post(
      ApiConfig.recommendationUrl,
      {'chat_id': chatId},
      // Its own budget: a search, up to three lookups, and a long generation,
      // possibly behind a cold start.
      timeout: ApiConfig.recommendationTimeout,
    );
    return Recommendation.fromJson(json);
  }

  @override
  Future<String> followUp({
    required String chatId,
    required String message,
  }) async {
    final json = await _post(
      ApiConfig.followUpUrl,
      {'chat_id': chatId, 'message': message},
      timeout: ApiConfig.requestTimeout,
    );
    return json['reply'] as String? ?? '';
  }

  @override
  Future<void> completeChat({required String chatId}) async {
    await _post(
      ApiConfig.completeChatUrl,
      {'chat_id': chatId},
      timeout: ApiConfig.requestTimeout,
    );
  }

  /// The poll in flight, if there is one. See [warmUp].
  Future<void>? _warmUp;

  @override
  Future<void> warmUp() {
    // One at a time. Sign-in and a foreground resume both call this, and an
    // app backgrounded *during* a cold start and brought back would otherwise
    // start a second two-minute loop racing the first.
    final existing = _warmUp;
    if (existing != null) return existing;

    // We do not know until it answers, and on a resume after a long background
    // the old `true` is exactly the thing that was lying. Setting it false here
    // is what puts the "waking the server up" copy back in front of the user
    // while this runs — and a server that is in fact awake answers the first
    // ping in milliseconds and flips it straight back.
    backendWarm.value = false;

    return _warmUp = _pollUntilWarm().whenComplete(() => _warmUp = null);
  }

  Future<void> _pollUntilWarm() async {
    // Deliberately not routed through [_post]: this must work without a
    // token, since the whole point is to be fired the instant a user shows up
    // — before anything downstream of sign-in has had a chance to fail.
    final deadline = DateTime.now().add(ApiConfig.warmUpBudget);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await _client
            .get(ApiConfig.healthUrl)
            .timeout(ApiConfig.warmUpAttemptTimeout);

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          // `warm` is the API telling us its model client and database session
          // are built. A server too old to report it is treated as warm — it
          // answered, which is all the previous version of this ever checked.
          final warm = body is Map ? body['warm'] != false : true;
          if (warm) {
            _markWarm();
            return;
          }
          // Booted but still constructing. Seconds, not tens of seconds.
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
      } catch (e) {
        // A cold start routinely outlasts a single attempt's timeout. The
        // request still reached Render and still started the boot, so the next
        // attempt is asking a server that is already on its way up.
        debugPrint('ThoughtLoom: warm-up ping failed — $e');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }

    // Out of budget. Nothing to report and nobody to report it to: the first
    // real request will simply pay for whatever is left of the cold start, and
    // the screens are built to wait it out.
    debugPrint('ThoughtLoom: gave up warming the backend.');
  }
}
