import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:deckionary/core/database/database_provider.dart';
import 'package:deckionary/features/speaking/domain/speaking_result.dart';
import 'package:deckionary/features/speaking/domain/speaking_service.dart';
import 'package:deckionary/features/speaking/providers/speaking_providers.dart';
import 'package:deckionary/features/speaking/providers/speaking_session_notifier.dart';

import '../../test_helpers.dart';

class _FakeSpeakingService extends SpeakingService {
  final SpeakingResult stubbed;
  _FakeSpeakingService({
    required super.db,
    required super.supabase,
    required this.stubbed,
  });

  @override
  Future<SpeakingResult> analyzeRecording(
    Uint8List audioBytes,
    String topic,
  ) async => stubbed;

  @override
  Future<SpeakingResult> analyzeText(String text, String topic) async =>
      stubbed;
}

void main() {
  group('SpeakingSessionNotifier', () {
    late UserDatabase db;
    late ProviderContainer container;

    SpeakingResult result(String suffix) => SpeakingResult(
      transcript: 'transcript-$suffix',
      corrections: const [],
      naturalVersion: 'natural-$suffix',
    );

    setUp(() {
      db = createTestUserDb();
      container = ProviderContainer(
        overrides: [
          userDbProvider.overrideWithValue(db),
          speakingServiceProvider.overrideWithValue(
            _FakeSpeakingService(
              db: db,
              supabase: SupabaseClient('http://localhost', 'anon'),
              stubbed: result('stub'),
            ),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('startSession initializes an empty session', () {
      container
          .read(speakingSessionNotifierProvider.notifier)
          .startSession(topic: 'travel', isCustomTopic: false);
      final state = container.read(speakingSessionNotifierProvider);
      expect(state, isNotNull);
      expect(state!.topic, 'travel');
      expect(state.attempts, isEmpty);
      expect(state.sessionId, isNotEmpty);
    });

    test('addAttemptFromText persists a row and appends to state', () async {
      final notifier = container.read(speakingSessionNotifierProvider.notifier);
      notifier.startSession(topic: 'travel', isCustomTopic: false);
      await notifier.addAttemptFromText('hello world');

      final state = container.read(speakingSessionNotifierProvider)!;
      expect(state.attempts, hasLength(1));
      expect(state.attempts.first.attemptNumber, 1);
      expect(state.attempts.first.result.transcript, 'transcript-stub');

      final dbRows = await db.select(db.speakingResults).get();
      expect(dbRows, hasLength(1));
      expect(dbRows.first.sessionId, state.sessionId);
      expect(dbRows.first.attemptNumber, 1);
    });

    test(
      'second attempt increments attemptNumber and keeps the session id',
      () async {
        final notifier = container.read(
          speakingSessionNotifierProvider.notifier,
        );
        notifier.startSession(topic: 'food', isCustomTopic: true);
        await notifier.addAttemptFromText('first');
        await notifier.addAttemptFromText('second');

        final state = container.read(speakingSessionNotifierProvider)!;
        expect(state.attempts.map((a) => a.attemptNumber).toList(), [1, 2]);

        final dbRows = await (db.select(
          db.speakingResults,
        )..orderBy([(t) => OrderingTerm.asc(t.attemptNumber)])).get();
        expect(dbRows, hasLength(2));
        expect(dbRows.every((r) => r.sessionId == state.sessionId), isTrue);
      },
    );

    test('endSession deletes shadow files and clears state', () async {
      final notifier = container.read(speakingSessionNotifierProvider.notifier);
      notifier.startSession(topic: 'work', isCustomTopic: false);
      await notifier.addAttemptFromText('first');

      final tmp = File('${Directory.systemTemp.path}/shadow_dummy.wav');
      await tmp.writeAsBytes([0, 1, 2]);
      final attemptId = container
          .read(speakingSessionNotifierProvider)!
          .attempts
          .first
          .id;
      notifier.setShadowAudio(attemptId: attemptId, path: tmp.path);

      await notifier.endSession();

      expect(container.read(speakingSessionNotifierProvider), isNull);
      expect(tmp.existsSync(), isFalse);
    });
  });
}
