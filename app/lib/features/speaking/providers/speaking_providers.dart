import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/database/database_provider.dart';
import '../../../main.dart';
import '../data/curated_topics.dart';
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

// ── History ──────────────────────────────────────────────────────────────────

final speakingHistoryProvider = FutureProvider<List<SpeakingHistoryItem>>((
  ref,
) async {
  final service = ref.read(speakingServiceProvider);
  if (service == null) return [];
  final rows = await service.getHistory();
  return rows
      .map(
        (r) => SpeakingHistoryItem(
          id: r.id,
          topic: r.topic,
          isCustomTopic: r.isCustomTopic,
          createdAt: DateTime.parse(r.createdAt),
        ),
      )
      .toList();
});

class SpeakingHistoryItem {
  final String id;
  final String topic;
  final bool isCustomTopic;
  final DateTime createdAt;

  const SpeakingHistoryItem({
    required this.id,
    required this.topic,
    required this.isCustomTopic,
    required this.createdAt,
  });
}

// ── Analyze action ───────────────────────────────────────────────────────────

/// Analyze a voice recording and save the result.
Future<SpeakingResult> analyzeRecording(
  WidgetRef ref, {
  required Uint8List audioBytes,
  required String topic,
  required bool isCustomTopic,
}) async {
  final service = ref.read(speakingServiceProvider)!;
  final result = await service.analyzeRecording(audioBytes, topic);
  await service.saveResult(
    topic: topic,
    isCustomTopic: isCustomTopic,
    result: result,
  );
  ref.invalidate(speakingHistoryProvider);
  return result;
}

/// Analyze typed text and save the result.
Future<SpeakingResult> analyzeText(
  WidgetRef ref, {
  required String text,
  required String topic,
  required bool isCustomTopic,
}) async {
  final service = ref.read(speakingServiceProvider)!;
  final result = await service.analyzeText(text, topic);
  await service.saveResult(
    topic: topic,
    isCustomTopic: isCustomTopic,
    result: result,
  );
  ref.invalidate(speakingHistoryProvider);
  return result;
}
