//ai_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

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

  const AdaptiveTurn({
    required this.done,
    required this.round,
    this.messageId,
    this.question,
    this.options = const [],
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
  final String text;
  final List<String> nextSteps;
  final String confidence;

  /// Empty when the answer needed no research, which is most of the time.
  final List<Source> sources;
  final String? messageId;

  const Recommendation({
    required this.text,
    this.nextSteps = const [],
    this.confidence = '',
    this.sources = const [],
    this.messageId,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
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
  Future<AdaptiveTurn> nextQuestion({
    required String chatId,
    String? answerToMessageId,
    String? answer,
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
  }) async {
    final json = await _post(
      ApiConfig.adaptiveQuestionUrl,
      {
        'chat_id': chatId,
        if (answer != null && answerToMessageId != null)
          'answer': {'message_id': answerToMessageId, 'text': answer},
      },
      timeout: ApiConfig.requestTimeout,
    );
    return AdaptiveTurn(
      done: json['done'] as bool? ?? false,
      round: json['round'] as int? ?? 0,
      messageId: json['message_id'] as String?,
      question: json['question'] as String?,
      options: (json['options'] as List? ?? []).whereType<String>().toList(),
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
}
