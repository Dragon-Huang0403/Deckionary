import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart' hide isNotNull;
import 'package:supabase/supabase.dart';
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/core/sync/table_sync.dart';

import 'sync_test_helpers.dart';

void main() {
  late SupabaseClient supabase;
  late UserDatabase db;
  late TableSync tableSync;
  late String userId;

  setUp(() async {
    supabase = createTestSupabase();
    db = createTestDb();
    userId = await createTestUser(supabase);
    tableSync = TableSync(
      db: db,
      supabase: supabase,
      getUserId: () => userId,
    );
  });

  tearDown(() async {
    await deleteTestUser(supabase, userId);
    await db.close();
  });

  /// Helper: insert a review card row into local DB.
  Future<bool> insertLocalReviewCard(Map<String, dynamic> row) async {
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
  }

  group('TableSync.pull', () {
    test('fetches all records on first pull (no watermark)', () async {
      final t = '2026-04-12T14:34:05.000+00:00';
      final id1 = testUuid(), id2 = testUuid();
      await supabase.from('review_cards').upsert([
        makeReviewCard(id: id1, userId: userId, updatedAt: t),
        makeReviewCard(id: id2, userId: userId, updatedAt: t),
      ]);

      final pulled = await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );

      expect(pulled, 2);

      final local = await db
          .customSelect('SELECT COUNT(*) as cnt FROM review_cards')
          .getSingle();
      expect(local.data['cnt'], 2);
    });

    test('records at watermark boundary are NOT missed on next pull', () async {
      // This is the EXACT bug: records with updated_at == watermark
      // were skipped because the old code used gt (strict greater-than).
      final t = '2026-04-12T14:34:05.000+00:00';
      final idA = testUuid(), idB = testUuid(), idC = testUuid();

      // First: push 2 cards with same timestamp
      await supabase.from('review_cards').upsert([
        makeReviewCard(id: idA, userId: userId, updatedAt: t),
        makeReviewCard(id: idB, userId: userId, updatedAt: t),
      ]);

      // First pull: fetches both, watermark set to t
      await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );

      // Another device pushes a 3rd card with the SAME timestamp
      await supabase.from('review_cards').upsert(
        makeReviewCard(id: idC, userId: userId, updatedAt: t),
      );

      // Second pull: card-c must be fetched (gte includes the boundary)
      final pulled = await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );

      // idA and idB are re-fetched but already exist → processRow
      // returns false. idC is new → processRow returns true.
      expect(pulled, 1);

      final local = await db
          .customSelect('SELECT COUNT(*) as cnt FROM review_cards')
          .getSingle();
      expect(local.data['cnt'], 3);
    });

    test('pull without watermark always fetches all records', () async {
      final t1 = '2026-04-10T10:00:00.000+00:00';
      final t2 = '2026-04-12T10:00:00.000+00:00';
      final id1 = testUuid(), id2 = testUuid(), id3 = testUuid();

      await supabase.from('review_cards').upsert([
        makeReviewCard(id: id1, userId: userId, updatedAt: t1),
        makeReviewCard(id: id2, userId: userId, updatedAt: t2),
      ]);

      // First pull with no watermark
      await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: null,
        processRow: insertLocalReviewCard,
      );

      // Add another card with old timestamp (simulates late push from device)
      await supabase.from('review_cards').upsert(
        makeReviewCard(id: id3, userId: userId, updatedAt: t1),
      );

      // Second pull, still no watermark → must fetch all including id3
      final pulled = await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: null,
        processRow: insertLocalReviewCard,
      );

      expect(pulled, 1); // only id3 is new locally

      final local = await db
          .customSelect('SELECT COUNT(*) as cnt FROM review_cards')
          .getSingle();
      expect(local.data['cnt'], 3);
    });

    test('watermark is updated after successful pull', () async {
      final t = '2026-04-15T08:00:00.000+00:00';
      final id1 = testUuid();
      await supabase.from('review_cards').upsert(
        makeReviewCard(id: id1, userId: userId, updatedAt: t),
      );

      await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );

      final meta = await db
          .customSelect(
            "SELECT value FROM sync_meta WHERE key = 'review_cards_last_sync_at'",
            readsFrom: {db.syncMeta},
          )
          .getSingle();

      // Watermark should contain the timestamp (Supabase normalizes format)
      final value = meta.data['value'] as String;
      expect(value, isNotEmpty);
      expect(value, contains('2026-04-15'));
    });

    test('watermark is NOT updated when watermarkKey is null', () async {
      final id1 = testUuid();
      await supabase.from('review_cards').upsert(
        makeReviewCard(id: id1, userId: userId),
      );

      await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: null,
        processRow: insertLocalReviewCard,
      );

      final meta = await db
          .customSelect(
            "SELECT value FROM sync_meta WHERE key = 'review_cards_last_sync_at'",
            readsFrom: {db.syncMeta},
          )
          .get();

      expect(meta, isEmpty);
    });

    test('returns 0 when user is not authenticated', () async {
      final unauthSync = TableSync(
        db: db,
        supabase: supabase,
        getUserId: () => null,
      );

      final pulled = await unauthSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );

      expect(pulled, 0);
    });
  });

  group('TableSync.clearAllWatermarks', () {
    test('clears all watermarks and next pull re-fetches everything', () async {
      final t = '2026-04-12T10:00:00.000+00:00';
      final id1 = testUuid(), id2 = testUuid();
      await supabase.from('review_cards').upsert([
        makeReviewCard(id: id1, userId: userId, updatedAt: t),
        makeReviewCard(id: id2, userId: userId, updatedAt: t),
      ]);

      // First pull sets watermark
      await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );

      // Clear all watermarks
      await tableSync.clearAllWatermarks();

      // Verify watermark is gone
      final meta = await db
          .customSelect(
            "SELECT value FROM sync_meta WHERE key = 'review_cards_last_sync_at'",
            readsFrom: {db.syncMeta},
          )
          .get();
      expect(meta, isEmpty);

      // Next pull re-fetches all records (no cursor filter)
      // Both already exist locally, so pulled = 0
      final pulled = await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );
      expect(pulled, 0);
    });
  });
}
