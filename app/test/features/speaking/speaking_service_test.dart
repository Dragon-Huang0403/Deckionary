import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/database/app_database.dart';

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
      await db.into(db.speakingResults).insert(
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
        await db.into(db.speakingResults).insert(
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

      final rows = await (db.select(db.speakingResults)
            ..where((t) => t.sessionId.equals('session-B'))
            ..orderBy([(t) => OrderingTerm.asc(t.attemptNumber)]))
          .get();
      expect(rows.map((r) => r.attemptNumber).toList(), [1, 2, 3]);
    });
  });
}
