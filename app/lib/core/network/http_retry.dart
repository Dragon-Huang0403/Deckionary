import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown when an HTTP request is cancelled via [isCancelled].
class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => 'CancelledException';
}

/// HTTP GET with exponential backoff and full jitter.
///
/// Retries on transient failures: timeouts, network errors, 5xx, 429.
/// Does NOT retry client errors (4xx except 429).
/// If [isCancelled] returns true, throws [CancelledException] immediately
/// (checked before each attempt and before each backoff sleep).
///
/// Uses "Full Jitter" algorithm to prevent thundering herd / DDoS:
///   delay = random(0, min(maxBackoff, baseDelay * 2^attempt))
///
/// See: https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
Future<http.Response> httpGetWithRetry(
  http.Client client,
  Uri url, {
  int maxAttempts = 3,
  Duration timeout = const Duration(seconds: 30),
  Duration baseDelay = const Duration(seconds: 1),
  Duration maxBackoff = const Duration(seconds: 30),
  bool Function()? isCancelled,
}) async {
  final rng = Random();
  for (var attempt = 0; ; attempt++) {
    if (isCancelled?.call() ?? false) throw const CancelledException();

    try {
      final sw = Stopwatch()..start();
      final response = await client.get(url).timeout(timeout);
      sw.stop();

      debugPrint(
        'httpGetWithRetry: ${response.statusCode} for $url '
        '(${sw.elapsedMilliseconds}ms)',
      );

      // Success or non-retryable client error — return immediately
      if (response.statusCode < 500 && response.statusCode != 429) {
        return response;
      }

      // Server error or rate-limited — retry if attempts remain
      if (attempt >= maxAttempts - 1) return response;

      debugPrint(
        'httpGetWithRetry: ${response.statusCode} for $url '
        '(attempt ${attempt + 1}/$maxAttempts, retrying)',
      );
    } catch (e) {
      if (e is CancelledException) rethrow;
      if (attempt >= maxAttempts - 1) rethrow;

      // Only retry transient network errors
      if (e is! TimeoutException &&
          e is! SocketException &&
          e is! http.ClientException) {
        rethrow;
      }

      debugPrint(
        'httpGetWithRetry: $e for $url '
        '(attempt ${attempt + 1}/$maxAttempts, retrying)',
      );
    }

    if (isCancelled?.call() ?? false) throw const CancelledException();

    // Exponential backoff with full jitter
    final expMs = min(
      maxBackoff.inMilliseconds,
      baseDelay.inMilliseconds * (1 << attempt),
    );
    await Future.delayed(Duration(milliseconds: rng.nextInt(expMs + 1)));
  }
}
