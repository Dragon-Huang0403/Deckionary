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
    tableSync = TableSync(db: db, supabase: supabase, getUserId: () => userId);
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
      await supabase
          .from('review_cards')
          .upsert(makeReviewCard(id: idC, userId: userId, updatedAt: t));

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
      await supabase
          .from('review_cards')
          .upsert(makeReviewCard(id: id3, userId: userId, updatedAt: t1));

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
      // server_updated_at is stamped by the DB trigger at insert time. The
      // watermark must match that exact value — comparing against
      // DateTime.now() on the client is unreliable when the test runner's
      // clock differs from the Postgres container's by a few milliseconds.
      final id1 = testUuid();
      await supabase
          .from('review_cards')
          .upsert(makeReviewCard(id: id1, userId: userId));

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

      final watermarkRaw = meta.data['value'] as String;
      expect(watermarkRaw, isNotEmpty);

      final serverRow = await supabase
          .from('review_cards')
          .select('server_updated_at')
          .eq('id', id1)
          .single();
      final serverUpdatedAt = serverRow['server_updated_at'] as String;

      // Both timestamps come from the server; they must represent the same
      // instant regardless of representation differences.
      expect(
        DateTime.parse(watermarkRaw).toUtc(),
        DateTime.parse(serverUpdatedAt).toUtc(),
      );
    });

    test('delayed push with older client updated_at is not skipped '
        '(server_updated_at watermark race fix)', () async {
      // Simulates the production bug: device A creates a record at T1 but
      // push is slow; device B creates+pushes a record at T2 (> T1) which
      // lands first; device C pulls and advances its watermark to T2;
      // device A's push finally lands with client updated_at = T1 (< T2).
      // With a server-authoritative watermark, device C's next pull must
      // still fetch A's record.
      final tEarly = '2026-01-01T00:00:00.000+00:00';
      final tLate = '2026-06-01T00:00:00.000+00:00';
      final idB = testUuid();
      final idA = testUuid();

      // Device B pushes first (later client timestamp)
      await supabase
          .from('review_cards')
          .upsert(makeReviewCard(id: idB, userId: userId, updatedAt: tLate));

      // Device C pulls → watermark advances to server_updated_at of idB
      await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );

      // Device A's delayed push arrives with OLDER client updated_at.
      // The trigger stamps server_updated_at = now() (strictly > idB's).
      await supabase
          .from('review_cards')
          .upsert(makeReviewCard(id: idA, userId: userId, updatedAt: tEarly));

      // Device C pulls again. With the old client-timestamp watermark this
      // would skip idA (because tEarly < tLate). With server_updated_at it
      // must be included.
      final pulled = await tableSync.pull(
        remoteTable: 'review_cards',
        watermarkKey: 'review_cards',
        processRow: insertLocalReviewCard,
      );

      expect(pulled, 1);

      final local = await db
          .customSelect(
            'SELECT COUNT(*) AS cnt FROM review_cards WHERE id = ?',
            variables: [Variable.withString(idA)],
          )
          .getSingle();
      expect(local.data['cnt'], 1);
    });

    test('watermark is NOT updated when watermarkKey is null', () async {
      final id1 = testUuid();
      await supabase
          .from('review_cards')
          .upsert(makeReviewCard(id: id1, userId: userId));

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
