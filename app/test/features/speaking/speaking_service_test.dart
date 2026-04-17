import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/features/speaking/domain/speaking_result.dart';
import 'package:deckionary/features/speaking/domain/speaking_service.dart';

import '../../test_helpers.dart';

void main() {
  group('SpeakingResults schema v10', () {
    late UserDatabase db;

    setUp(() {
      db = createTestUserDb();
    });

    tearDown(() async {
      await db.close();
    });

    test('inserts a row with session_id and attempt_number', () async {
      await db
          .into(db.speakingResults)
          .insert(
            SpeakingResultsCompanion.insert(
              id: 'row-1',
              topic: 'weekend plans',
              transcript: 'I go store',
              correctionsJson: '[]',
              naturalVersion: 'I will go to the store',
              sessionId: const Value('session-A'),
              attemptNumber: const Value(1),
            ),
          );

      final rows = await db.select(db.speakingResults).get();
      expect(rows, hasLength(1));
      expect(rows.first.sessionId, 'session-A');
      expect(rows.first.attemptNumber, 1);
    });

    test('allows multiple rows sharing the same session_id', () async {
      for (var i = 1; i <= 3; i++) {
        await db
            .into(db.speakingResults)
            .insert(
              SpeakingResultsCompanion.insert(
                id: 'row-$i',
                topic: 'weekend plans',
                transcript: 'attempt $i',
                correctionsJson: '[]',
                naturalVersion: 'natural $i',
                sessionId: const Value('session-B'),
                attemptNumber: Value(i),
              ),
            );
      }

      final rows =
          await (db.select(db.speakingResults)
                ..where((t) => t.sessionId.equals('session-B'))
                ..orderBy([(t) => OrderingTerm.asc(t.attemptNumber)]))
              .get();
      expect(rows.map((r) => r.attemptNumber).toList(), [1, 2, 3]);
    });
  });

  group(
    'SpeakingService.saveAttempt / getAttemptsBySessionId / deleteSession',
    () {
      late UserDatabase db;
      late SpeakingService service;

      setUp(() {
        db = createTestUserDb();
        // SupabaseClient not used by these methods; pass a dummy via a stub.
        service = SpeakingService(
          db: db,
          supabase: SupabaseClient('http://localhost', 'anon'),
        );
      });

      tearDown(() async {
        await db.close();
      });

      SpeakingResult sampleResult(String suffix) => SpeakingResult(
        transcript: 'transcript-$suffix',
        corrections: const [],
        naturalVersion: 'natural-$suffix',
        overallNote: null,
      );

      test(
        'saveAttempt persists all session fields and returns the row id',
        () async {
          final id = await service.saveAttempt(
            sessionId: 'session-1',
            topic: 'travel',
            isCustomTopic: false,
            attemptNumber: 2,
            result: sampleResult('a'),
          );

          expect(id, isNotEmpty);
          final rows = await db.select(db.speakingResults).get();
          expect(rows, hasLength(1));
          expect(rows.first.id, id);
          expect(rows.first.sessionId, 'session-1');
          expect(rows.first.attemptNumber, 2);
          expect(rows.first.topic, 'travel');
          expect(rows.first.synced, 0);
        },
      );

      test('getAttemptsBySessionId returns attempts in order', () async {
        await service.saveAttempt(
          sessionId: 'session-2',
          topic: 'travel',
          isCustomTopic: false,
          attemptNumber: 1,
          result: sampleResult('a'),
        );
        await service.saveAttempt(
          sessionId: 'session-2',
          topic: 'travel',
          isCustomTopic: false,
          attemptNumber: 2,
          result: sampleResult('b'),
        );

        final rows = await service.getAttemptsBySessionId('session-2');
        expect(rows.map((r) => r.attemptNumber).toList(), [1, 2]);
        expect(rows.first.transcript, 'transcript-a');
      });

      test(
        'deleteSession soft-deletes every row sharing the session_id',
        () async {
          await service.saveAttempt(
            sessionId: 'session-3',
            topic: 'food',
            isCustomTopic: true,
            attemptNumber: 1,
            result: sampleResult('a'),
          );
          await service.saveAttempt(
            sessionId: 'session-3',
            topic: 'food',
            isCustomTopic: true,
            attemptNumber: 2,
            result: sampleResult('b'),
          );

          await service.deleteSession('session-3');

          final rows = await db.select(db.speakingResults).get();
          expect(rows, hasLength(2));
          expect(rows.every((r) => r.deletedAt != null), isTrue);
          expect(rows.every((r) => r.synced == 0), isTrue);
        },
      );

      test('getHistory excludes soft-deleted rows from any session', () async {
        await service.saveAttempt(
          sessionId: 'session-4',
          topic: 'work',
          isCustomTopic: false,
          attemptNumber: 1,
          result: sampleResult('a'),
        );
        await service.deleteSession('session-4');
        final rows = await service.getHistory();
        expect(rows, isEmpty);
      });
    },
  );
}
