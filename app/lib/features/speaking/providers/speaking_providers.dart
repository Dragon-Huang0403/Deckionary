import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/database_provider.dart';
import '../../../main.dart';
import '../data/curated_topics.dart';
import '../domain/speaking_attempt.dart';
import '../domain/speaking_result.dart';
import '../domain/speaking_service.dart';
import '../domain/speaking_topic.dart';
import '../domain/tts_cache_service.dart';

// ── Services ─────────────────────────────────────────────────────────────────

final speakingServiceProvider = Provider<SpeakingService?>((ref) {
  if (!syncEnabled) return null;
  return SpeakingService(
    db: ref.read(userDbProvider),
    supabase: Supabase.instance.client,
  );
});

final ttsCacheServiceProvider = Provider<TtsCacheService?>((ref) {
  if (!syncEnabled) return null;
  final service = TtsCacheService(supabase: Supabase.instance.client);
  ref.onDispose(service.dispose);
  return service;
});

// ── Input mode ───────────────────────────────────────────────────────────────

enum InputMode { speaking, typing }

final inputModeProvider = NotifierProvider<_InputModeNotifier, InputMode>(
  _InputModeNotifier.new,
);

class _InputModeNotifier extends Notifier<InputMode> {
  @override
  InputMode build() => InputMode.speaking;
  void set(InputMode mode) => state = mode;
}

// ── Recording state ──────────────────────────────────────────────────────────

enum RecordingStatus { idle, recording, processing }

final recordingStatusProvider =
    NotifierProvider<_RecordingStatusNotifier, RecordingStatus>(
      _RecordingStatusNotifier.new,
    );

class _RecordingStatusNotifier extends Notifier<RecordingStatus> {
  @override
  RecordingStatus build() => RecordingStatus.idle;
  void set(RecordingStatus status) => state = status;
}

// ── Current session result ───────────────────────────────────────────────────

final speakingResultProvider =
    NotifierProvider<_SpeakingResultNotifier, SpeakingResult?>(
      _SpeakingResultNotifier.new,
    );

class _SpeakingResultNotifier extends Notifier<SpeakingResult?> {
  @override
  SpeakingResult? build() => null;
  void set(SpeakingResult? result) => state = result;
}

// ── Topics ───────────────────────────────────────────────────────────────────

final curatedTopicsProvider =
    Provider<Map<SpeakingTopicCategory, List<SpeakingTopic>>>((ref) {
      final grouped = <SpeakingTopicCategory, List<SpeakingTopic>>{};
      for (final topic in curatedTopics) {
        grouped.putIfAbsent(topic.category, () => []).add(topic);
      }
      return grouped;
    });

// ── History (grouped by session_id) ─────────────────────────────────────────

final speakingHistoryProvider = FutureProvider<List<SpeakingHistoryItem>>((
  ref,
) async {
  final service = ref.watch(speakingServiceProvider);
  if (service == null) return [];
  final rows = await service.getHistory(limit: 200);

  // Group by session_id; fall back to row id for legacy rows where session_id
  // is null (should not happen post-migration, but defensively handled).
  final Map<String, List<SpeakingResultRow>> bySession = {};
  for (final row in rows) {
    final key = row.sessionId ?? row.id;
    bySession.putIfAbsent(key, () => []).add(row);
  }

  final items = bySession.entries.map((entry) {
    final sessionRows = entry.value
      ..sort((a, b) => (a.attemptNumber ?? 1).compareTo(b.attemptNumber ?? 1));
    final latest = sessionRows.last;
    var count = 0;
    try {
      final list = jsonDecode(latest.correctionsJson);
      if (list is List) count = list.length;
    } catch (_) {}
    return SpeakingHistoryItem(
      sessionId: entry.key,
      topic: latest.topic,
      isCustomTopic: latest.isCustomTopic,
      correctionsCount: count,
      attemptCount: sessionRows.length,
      createdAt: DateTime.parse(latest.createdAt),
    );
  }).toList();

  items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return items;
});

class SpeakingHistoryItem {
  final String sessionId;
  final String topic;
  final bool isCustomTopic;
  final int correctionsCount; // from the latest attempt
  final int attemptCount;
  final DateTime createdAt; // latest attempt's createdAt

  const SpeakingHistoryItem({
    required this.sessionId,
    required this.topic,
    required this.isCustomTopic,
    required this.correctionsCount,
    required this.attemptCount,
    required this.createdAt,
  });
}

/// Loads a full SpeakingResult from DB by ID (for history detail screen).
final speakingResultByIdProvider =
    FutureProvider.family<SpeakingResult?, String>((ref, id) async {
      final service = ref.watch(speakingServiceProvider);
      if (service == null) return null;
      final row = await service.getResultById(id);
      if (row == null) return null;
      final corrections = (jsonDecode(row.correctionsJson) as List)
          .map((e) => SpeakingCorrection.fromJson(e as Map<String, dynamic>))
          .toList();
      return SpeakingResult(
        transcript: row.transcript,
        corrections: corrections,
        naturalVersion: row.naturalVersion,
        overallNote: row.overallNote,
        pronunciationIssues: _decodePronunciationIssues(
          row.pronunciationIssuesJson,
        ),
      );
    });

List<PronunciationIssue>? _decodePronunciationIssues(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final list = jsonDecode(json);
    if (list is! List || list.isEmpty) return null;
    return list
        .map((e) => PronunciationIssue.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return null;
  }
}

/// Loads all attempts for one session (for history detail screen).
final speakingSessionByIdProvider =
    FutureProvider.family<SpeakingHistorySession?, String>((
      ref,
      sessionId,
    ) async {
      final service = ref.watch(speakingServiceProvider);
      if (service == null) return null;
      final rows = await service.getAttemptsBySessionId(sessionId);
      if (rows.isEmpty) return null;
      final attempts = rows.map(_rowToAttempt).toList();
      return SpeakingHistorySession(
        sessionId: sessionId,
        topic: rows.first.topic,
        isCustomTopic: rows.first.isCustomTopic,
        attempts: attempts,
      );
    });

SpeakingAttempt _rowToAttempt(SpeakingResultRow row) {
  final corrections = (jsonDecode(row.correctionsJson) as List)
      .map((e) => SpeakingCorrection.fromJson(e as Map<String, dynamic>))
      .toList();
  final result = SpeakingResult(
    transcript: row.transcript,
    corrections: corrections,
    naturalVersion: row.naturalVersion,
    overallNote: row.overallNote,
    pronunciationIssues: _decodePronunciationIssues(
      row.pronunciationIssuesJson,
    ),
  );
  return SpeakingAttempt(
    id: row.id,
    attemptNumber: row.attemptNumber ?? 1,
    result: result,
    createdAt: DateTime.parse(row.createdAt),
    audioLocalPath: row.audioLocalPath,
    audioStorageKey: row.audioStorageKey,
  );
}

/// Read-only snapshot of a past session loaded from the DB.
class SpeakingHistorySession {
  final String sessionId;
  final String topic;
  final bool isCustomTopic;
  final List<SpeakingAttempt> attempts;

  const SpeakingHistorySession({
    required this.sessionId,
    required this.topic,
    required this.isCustomTopic,
    required this.attempts,
  });
}

// ── Analyze action ───────────────────────────────────────────────────────────

// Temporary shims — removed in Task 12.
Future<SpeakingResult> analyzeRecording(
  WidgetRef ref, {
  required Uint8List audioBytes,
  required String topic,
  required bool isCustomTopic,
}) async {
  throw UnimplementedError(
    'analyzeRecording(ref, ...) is deprecated — use SpeakingSessionNotifier',
  );
}

Future<SpeakingResult> analyzeText(
  WidgetRef ref, {
  required String text,
  required String topic,
  required bool isCustomTopic,
}) async {
  throw UnimplementedError(
    'analyzeText(ref, ...) is deprecated — use SpeakingSessionNotifier',
  );
}
