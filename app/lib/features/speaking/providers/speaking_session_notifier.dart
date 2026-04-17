import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/speaking_attempt.dart';
import '../domain/speaking_result.dart';
import '../domain/speaking_service.dart';
import 'speaking_providers.dart';

class SpeakingSessionNotifier extends Notifier<SpeakingSessionState?> {
  @override
  SpeakingSessionState? build() => null;

  void startSession({required String topic, required bool isCustomTopic}) {
    state = SpeakingSessionState(
      sessionId: const Uuid().v4(),
      topic: topic,
      isCustomTopic: isCustomTopic,
      attempts: const [],
    );
  }

  /// Record + analyze + persist a voice attempt. Caller is responsible for
  /// navigation. Throws on analysis / persistence failure.
  Future<SpeakingAttempt> addAttemptFromAudio(Uint8List audioBytes) async {
    final session = state;
    if (session == null) {
      throw StateError('addAttemptFromAudio called with no active session');
    }
    final service = ref.read(speakingServiceProvider);
    if (service == null) {
      throw StateError('Speaking service unavailable (sync disabled?)');
    }
    final result = await service.analyzeRecording(audioBytes, session.topic);
    return _appendAttempt(service, session, result);
  }

  /// Same as above but for typed text.
  Future<SpeakingAttempt> addAttemptFromText(String text) async {
    final session = state;
    if (session == null) {
      throw StateError('addAttemptFromText called with no active session');
    }
    final service = ref.read(speakingServiceProvider);
    if (service == null) {
      throw StateError('Speaking service unavailable (sync disabled?)');
    }
    final result = await service.analyzeText(text, session.topic);
    return _appendAttempt(service, session, result);
  }

  Future<SpeakingAttempt> _appendAttempt(
    SpeakingService service,
    SpeakingSessionState session,
    SpeakingResult result,
  ) async {
    final attemptNumber = session.attempts.length + 1;
    final id = await service.saveAttempt(
      sessionId: session.sessionId,
      topic: session.topic,
      isCustomTopic: session.isCustomTopic,
      attemptNumber: attemptNumber,
      result: result,
    );
    final attempt = SpeakingAttempt(
      id: id,
      attemptNumber: attemptNumber,
      result: result,
      createdAt: DateTime.now(),
    );
    state = session.copyWith(attempts: [...session.attempts, attempt]);
    ref.invalidate(speakingHistoryProvider);
    return attempt;
  }

  void setShadowAudio({required String attemptId, required String path}) {
    final session = state;
    if (session == null) return;
    final updated = session.attempts
        .map((a) => a.id == attemptId ? a.copyWith(shadowAudioPath: path) : a)
        .toList(growable: false);
    state = session.copyWith(attempts: updated);
  }

  Future<void> clearShadowAudio(String attemptId) async {
    final session = state;
    if (session == null) return;
    for (final attempt in session.attempts) {
      if (attempt.id == attemptId && attempt.shadowAudioPath != null) {
        final f = File(attempt.shadowAudioPath!);
        if (f.existsSync()) await f.delete();
      }
    }
    final updated = session.attempts
        .map((a) => a.id == attemptId ? a.copyWith(clearShadow: true) : a)
        .toList(growable: false);
    state = session.copyWith(attempts: updated);
  }

  /// Delete all shadow files for the active session and clear state.
  /// DB rows are NOT deleted — they've been persisted per-attempt.
  Future<void> endSession() async {
    final session = state;
    if (session == null) return;
    for (final attempt in session.attempts) {
      final path = attempt.shadowAudioPath;
      if (path != null) {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      }
    }
    state = null;
  }
}

final speakingSessionNotifierProvider =
    NotifierProvider<SpeakingSessionNotifier, SpeakingSessionState?>(
      SpeakingSessionNotifier.new,
    );
