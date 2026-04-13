import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/core/sync/table_sync.dart';

import 'sync_test_helpers.dart';

void main() {
  late SupabaseClient supabase;
  late UserDatabase dbA; // Device A (e.g. Mac)
  late UserDatabase dbB; // Device B (e.g. Phone)
  late TableSync syncA;
  late TableSync syncB;
  late String userId;

  setUp(() async {
    supabase = createTestSupabase();
    dbA = createTestDb();
    dbB = createTestDb();
    userId = await createTestUser(supabase);
    syncA = TableSync(
      db: dbA,
      supabase: supabase,
      getUserId: () => userId,
    );
    syncB = TableSync(
      db: dbB,
      supabase: supabase,
      getUserId: () => userId,
    );
  });

  tearDown(() async {
    await deleteTestUser(supabase, userId);
    await dbA.close();
    await dbB.close();
  });

  Future<int> countLocalCards(UserDatabase db) async {
    final r = await db
        .customSelect(
          'SELECT COUNT(*) as cnt FROM review_cards WHERE deleted_at IS NULL',
        )
        .getSingle();
    return r.data['cnt'] as int;
  }

  /// Push a local review card to Supabase (simulates fire-and-forget push).
  Future<void> pushCard(
    UserDatabase db,
    SupabaseClient supa,
    String cardId,
    String userId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM review_cards WHERE id = ?',
          variables: [Variable.withString(cardId)],
          readsFrom: {db.reviewCards},
        )
        .get();
    if (rows.isEmpty) return;
    final row = rows.first.data;
    await supa.from('review_cards').upsert({
      'id': row['id'],
      'user_id': userId,
      'entry_id': row['entry_id'],
      'headword': row['headword'],
      'pos': row['pos'],
      'due': row['due'],
      'stability': row['stability'],
      'difficulty': row['difficulty'],
      'elapsed_days': row['elapsed_days'],
      'scheduled_days': row['scheduled_days'],
      'reps': row['reps'],
      'lapses': row['lapses'],
      'state': row['state'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    });
    await db.customUpdate(
      'UPDATE review_cards SET synced = 1 WHERE id = ?',
      variables: [Variable.withString(cardId)],
      updates: {db.reviewCards},
    );
  }

  /// Insert a review card into local DB (simulates creating a new card).
  Future<void> createLocalCard(
    UserDatabase db, {
    required String id,
    required String headword,
    required String updatedAt,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.customInsert(
      '''INSERT INTO review_cards
         (id, entry_id, headword, pos, due, stability, difficulty,
          elapsed_days, scheduled_days, reps, lapses, state,
          created_at, updated_at, synced)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)''',
      variables: [
        Variable.withString(id),
        Variable.withInt(1),
        Variable.withString(headword),
        Variable.withString('noun'),
        Variable.withString(now),
        Variable.withReal(0),
        Variable.withReal(0),
        Variable.withInt(0),
        Variable.withInt(0),
        Variable.withInt(0),
        Variable.withInt(0),
        Variable.withInt(0),
        Variable.withString(now),
        Variable.withString(updatedAt),
      ],
      updates: {db.reviewCards},
    );
  }

  /// processRow callback for pulling review cards.
  Future<bool> Function(Map<String, dynamic>) pullCallback(UserDatabase db) {
    return (Map<String, dynamic> row) async {
      final id = row['id'] as String;
      final remoteUpdatedAt = row['updated_at'] as String;
      final remoteDeletedAt = row['deleted_at'] as String?;

      final existing = await db
          .customSelect(
            'SELECT id, updated_at FROM review_cards WHERE id = ?',
            variables: [Variable.withString(id)],
            readsFrom: {db.reviewCards},
          )
          .get();

      if (existing.isEmpty) {
        if (remoteDeletedAt != null) return false;
        await db.customInsert(
          '''INSERT INTO review_cards
             (id, entry_id, headword, pos, due, stability, difficulty,
              elapsed_days, scheduled_days, reps, lapses, state,
              created_at, updated_at, synced)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)''',
          variables: [
            Variable.withString(id),
            Variable.withInt(row['entry_id'] as int),
            Variable.withString(row['headword'] as String),
            Variable.withString((row['pos'] as String?) ?? ''),
            Variable.withString(row['due'] as String),
            Variable.withReal((row['stability'] as num).toDouble()),
            Variable.withReal((row['difficulty'] as num).toDouble()),
            Variable.withInt(row['elapsed_days'] as int),
            Variable.withInt(row['scheduled_days'] as int),
            Variable.withInt(row['reps'] as int),
            Variable.withInt(row['lapses'] as int),
            Variable.withInt(row['state'] as int),
            Variable.withString(row['created_at'] as String),
            Variable.withString(remoteUpdatedAt),
          ],
          updates: {db.reviewCards},
        );
        return true;
      } else {
        final localUpdatedAt = existing.first.data['updated_at'] as String;
        if (remoteUpdatedAt.compareTo(localUpdatedAt) > 0) {
          await db.customUpdate(
            '''UPDATE review_cards SET
               entry_id = ?, headword = ?, pos = ?, due = ?,
               stability = ?, difficulty = ?, elapsed_days = ?,
               scheduled_days = ?, reps = ?, lapses = ?, state = ?,
               updated_at = ?, synced = 1
               WHERE id = ?''',
            variables: [
              Variable.withInt(row['entry_id'] as int),
              Variable.withString(row['headword'] as String),
              Variable.withString((row['pos'] as String?) ?? ''),
              Variable.withString(row['due'] as String),
              Variable.withReal((row['stability'] as num).toDouble()),
              Variable.withReal((row['difficulty'] as num).toDouble()),
              Variable.withInt(row['elapsed_days'] as int),
              Variable.withInt(row['scheduled_days'] as int),
              Variable.withInt(row['reps'] as int),
              Variable.withInt(row['lapses'] as int),
              Variable.withInt(row['state'] as int),
              Variable.withString(remoteUpdatedAt),
              Variable.withString(id),
            ],
            updates: {db.reviewCards},
          );
          return true;
        }
        return false;
      }
    };
  }

  group('Two-device sync', () {
    test(
      'device B gets all cards created on device A with same timestamp',
      () async {
        // Reproduce the user's bug: 30 cards reviewed at same batch time
        final batchTime = '2026-04-12T14:34:05.589826+00:00';
        final cardIds = List.generate(5, (_) => testUuid());

        // Device A creates 5 cards locally with same updated_at
        for (final id in cardIds) {
          await createLocalCard(
            dbA,
            id: id,
            headword: 'word-$id',
            updatedAt: batchTime,
          );
        }

        // Device A pushes all cards
        for (final id in cardIds) {
          await pushCard(dbA, supabase, id, userId);
        }

        // Device B pulls
        await syncB.pull(
          remoteTable: 'review_cards',
          watermarkKey: 'review_cards',
          processRow: pullCallback(dbB),
        );

        expect(await countLocalCards(dbB), 5);
      },
    );

    test(
      'device B pulls cards from device A even after first sync',
      () async {
        // Device A creates 3 cards, pushes, device B pulls
        final batchTime = '2026-04-12T14:34:05.000+00:00';
        final firstBatch = List.generate(3, (_) => testUuid());

        for (final id in firstBatch) {
          await createLocalCard(
            dbA,
            id: id,
            headword: 'first-$id',
            updatedAt: batchTime,
          );
          await pushCard(dbA, supabase, id, userId);
        }

        // Device B first sync
        await syncB.pull(
          remoteTable: 'review_cards',
          watermarkKey: 'review_cards',
          processRow: pullCallback(dbB),
        );
        expect(await countLocalCards(dbB), 3);

        // Device A creates 2 MORE cards with SAME timestamp
        final secondBatch = List.generate(2, (_) => testUuid());
        for (final id in secondBatch) {
          await createLocalCard(
            dbA,
            id: id,
            headword: 'second-$id',
            updatedAt: batchTime,
          );
          await pushCard(dbA, supabase, id, userId);
        }

        // Device B second sync — must get the 2 new cards
        await syncB.pull(
          remoteTable: 'review_cards',
          watermarkKey: 'review_cards',
          processRow: pullCallback(dbB),
        );
        expect(await countLocalCards(dbB), 5);
      },
    );

    test('both devices converge to same state after bidirectional sync',
        () async {
      final tA = '2026-04-12T10:00:00.000+00:00';
      final tB = '2026-04-12T11:00:00.000+00:00';
      final cardA = testUuid(), cardB = testUuid();

      // Device A creates a card
      await createLocalCard(dbA, id: cardA, headword: 'from-A', updatedAt: tA);
      await pushCard(dbA, supabase, cardA, userId);

      // Device B creates a different card
      await createLocalCard(dbB, id: cardB, headword: 'from-B', updatedAt: tB);
      await pushCard(dbB, supabase, cardB, userId);

      // Both devices pull
      await syncA.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: pullCallback(dbA),
      );
      await syncB.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: pullCallback(dbB),
      );

      // Both should have 2 cards
      expect(await countLocalCards(dbA), 2);
      expect(await countLocalCards(dbB), 2);
    });

    test('force full sync recovers from corrupted watermark', () async {
      final t1 = '2026-04-10T10:00:00.000+00:00';
      final t2 = '2026-04-12T10:00:00.000+00:00';
      final id1 = testUuid(), id2 = testUuid();

      // Device A pushes 2 cards at different times
      await createLocalCard(dbA, id: id1, headword: 'early', updatedAt: t1);
      await pushCard(dbA, supabase, id1, userId);
      await createLocalCard(dbA, id: id2, headword: 'late', updatedAt: t2);
      await pushCard(dbA, supabase, id2, userId);

      // Device B only pulls the late card (simulate corrupted watermark)
      // Manually set watermark to t2 so t1 card is missed
      await dbB.customInsert(
        "INSERT INTO sync_meta (key, value) VALUES ('review_cards_last_sync_at', ?)",
        variables: [Variable.withString(t2)],
        updates: {dbB.syncMeta},
      );

      // Pull with corrupted watermark — only gets cards >= t2
      await syncB.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: pullCallback(dbB),
      );
      expect(await countLocalCards(dbB), 1); // only the late card

      // Force full sync: clear watermarks, then pull
      await syncB.clearAllWatermarks();
      await syncB.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: pullCallback(dbB),
      );
      expect(await countLocalCards(dbB), 2); // now has both cards
    });
  });
}
