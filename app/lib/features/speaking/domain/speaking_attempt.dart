import 'speaking_result.dart';

/// One recorded attempt in a practice session. Pairs the LLM-analyzed result
/// with the optional local shadow-recording path.
class SpeakingAttempt {
  final String id; // = speaking_results.id
  final int attemptNumber; // 1-indexed within the session
  final SpeakingResult result;
  final String? shadowAudioPath; // local temp file; null until recorded
  final String? audioLocalPath; // persisted user recording on this device
  final String? audioStorageKey; // remote object key under 'speaking-audio'
  final DateTime createdAt;

  const SpeakingAttempt({
    required this.id,
    required this.attemptNumber,
    required this.result,
    required this.createdAt,
    this.shadowAudioPath,
    this.audioLocalPath,
    this.audioStorageKey,
  });

  SpeakingAttempt copyWith({
    String? shadowAudioPath,
    bool clearShadow = false,
    String? audioLocalPath,
    String? audioStorageKey,
  }) {
    return SpeakingAttempt(
      id: id,
      attemptNumber: attemptNumber,
      result: result,
      createdAt: createdAt,
      shadowAudioPath: clearShadow
          ? null
          : (shadowAudioPath ?? this.shadowAudioPath),
      audioLocalPath: audioLocalPath ?? this.audioLocalPath,
      audioStorageKey: audioStorageKey ?? this.audioStorageKey,
    );
  }
}

/// In-memory state for the currently active practice session.
class SpeakingSessionState {
  final String sessionId;
  final String topic;
  final bool isCustomTopic;
  final List<SpeakingAttempt> attempts; // index 0 = oldest (attempt 1)

  const SpeakingSessionState({
    required this.sessionId,
    required this.topic,
    required this.isCustomTopic,
    required this.attempts,
  });

  SpeakingSessionState copyWith({List<SpeakingAttempt>? attempts}) {
    return SpeakingSessionState(
      sessionId: sessionId,
      topic: topic,
      isCustomTopic: isCustomTopic,
      attempts: attempts ?? this.attempts,
    );
  }
}
