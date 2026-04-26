import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../logging/logging_service.dart';
import 'table_sync.dart';

class ReviewSync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;
  final TableSync _tableSync;

  ReviewSync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
    required TableSync tableSync,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId,
       _tableSync = tableSync;

  // ── Push (unchanged) ───────────────────────────────────────────────────────

  Future<void> pushLatestReviewCard(String cardId) async {
    if (_getUserId() == null) return;
    try {
      final rows = await _db
          .customSelect(
            'SELECT * FROM review_cards WHERE id = ?',
            variables: [Variable.withString(cardId)],
            readsFrom: {_db.reviewCards},
          )
          .get();
      if (rows.isEmpty) return;

      final row = rows.first.data;
      await _supabase.from('review_cards').upsert({
        'id': row['id'],
        'user_id': _getUserId(),
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
        'step': row['step'],
        'last_review': row['last_review'],
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
        'deleted_at': row['deleted_at'],
      });

      await _db.customUpdate(
        'UPDATE review_cards SET synced = 1 WHERE id = ?',
        variables: [Variable.withString(cardId)],
        updates: {_db.reviewCards},
      );
    } catch (e) {
      globalTalker.error('[Sync] Push review card failed (will retry): $e');
    }
  }

  Future<void> pushLatestReviewLog(String logId) async {
    if (_getUserId() == null) return;
    try {
      final rows = await _db
          .customSelect(
            'SELECT * FROM review_logs WHERE id = ?',
            variables: [Variable.withString(logId)],
            readsFrom: {_db.reviewLogs},
          )
          .get();
      if (rows.isEmpty) return;

      final row = rows.first.data;
      await _supabase.from('review_logs').upsert({
        'id': row['id'],
        'user_id': _getUserId(),
        'card_id': row['card_id'],
        'rating': row['rating'],
        'state': row['state'],
        'due': row['due'],
        'stability': row['stability'],
        'difficulty': row['difficulty'],
        'elapsed_days': row['elapsed_days'],
        'scheduled_days': row['scheduled_days'],
        'review_duration': row['review_duration'],
        'reviewed_at': (row['reviewed_at'] as String?)?.isNotEmpty == true
            ? row['reviewed_at']
            : DateTime.now().toUtc().toIso8601String(),
        'updated_at': row['updated_at'] ?? row['reviewed_at'],
        'deleted_at': row['deleted_at'],
      });

      await _db.customUpdate(
        'UPDATE review_logs SET synced = 1 WHERE id = ?',
        variables: [Variable.withString(logId)],
        updates: {_db.reviewLogs},
      );
    } catch (e) {
      globalTalker.error('[Sync] Push review log failed (will retry): $e');
    }
  }

  Future<int> pushAllUnsyncedReviewCards() async {
    if (_getUserId() == null) return 0;

    final unsynced = await _db
        .customSelect(
          'SELECT * FROM review_cards WHERE synced = 0',
          readsFrom: {_db.reviewCards},
        )
        .get();
    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      final data = row.data;
      try {
        await _supabase.from('review_cards').upsert({
          'id': data['id'],
          'user_id': _getUserId(),
          'entry_id': data['entry_id'],
          'headword': data['headword'],
          'pos': data['pos'],
          'due': data['due'],
          'stability': data['stability'],
          'difficulty': data['difficulty'],
          'elapsed_days': data['elapsed_days'],
          'scheduled_days': data['scheduled_days'],
          'reps': data['reps'],
          'lapses': data['lapses'],
          'state': data['state'],
          'step': data['step'],
          'last_review': data['last_review'],
          'created_at': data['created_at'],
          'updated_at': data['updated_at'],
          'deleted_at': data['deleted_at'],
        });

        await _db.customUpdate(
          'UPDATE review_cards SET synced = 1 WHERE id = ?',
          variables: [Variable.withString(data['id'] as String)],
          updates: {_db.reviewCards},
        );
        pushed++;
      } catch (e) {
        continue;
      }
    }
    return pushed;
  }

  Future<int> pushAllUnsyncedReviewLogs() async {
    if (_getUserId() == null) return 0;

    final unsynced = await _db
        .customSelect(
          'SELECT * FROM review_logs WHERE synced = 0',
          readsFrom: {_db.reviewLogs},
        )
        .get();
    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      final data = row.data;
      try {
        await _supabase.from('review_logs').upsert({
          'id': data['id'],
          'user_id': _getUserId(),
          'card_id': data['card_id'],
          'rating': data['rating'],
          'state': data['state'],
          'due': data['due'],
          'stability': data['stability'],
          'difficulty': data['difficulty'],
          'elapsed_days': data['elapsed_days'],
          'scheduled_days': data['scheduled_days'],
          'review_duration': data['review_duration'],
          'reviewed_at': (data['reviewed_at'] as String?)?.isNotEmpty == true
              ? data['reviewed_at']
              : DateTime.now().toUtc().toIso8601String(),
          'updated_at': data['updated_at'] ?? data['reviewed_at'],
          'deleted_at': data['deleted_at'],
        });

        await _db.customUpdate(
          'UPDATE review_logs SET synced = 1 WHERE id = ?',
          variables: [Variable.withString(data['id'] as String)],
          updates: {_db.reviewLogs},
        );
        pushed++;
      } catch (e) {
        continue;
      }
    }
    return pushed;
  }

  // ── Pull (delegated to TableSync) ──────────────────────────────────────────

  Future<int> pullReviewCards() => _tableSync.pull(
    remoteTable: 'review_cards',
    watermarkKey: 'review_cards',
    processRow: _processReviewCardRow,
  );

  Future<int> pullReviewLogs() => _tableSync.pull(
    remoteTable: 'review_logs',
    watermarkKey: 'review_logs',
    processRow: _processReviewLogRow,
  );

  Future<bool> _processReviewCardRow(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdatedAt = row['updated_at'] as String;
    final remoteDeletedAt = row['deleted_at'] as String?;

    final existing = await _db
        .customSelect(
          'SELECT id, updated_at FROM review_cards WHERE id = ?',
          variables: [Variable.withString(id)],
          readsFrom: {_db.reviewCards},
        )
        .get();

    if (existing.isEmpty) {
      if (remoteDeletedAt != null) return false;

      await _db.customInsert(
        '''INSERT INTO review_cards
           (id, entry_id, headword, pos, due, stability, difficulty,
            elapsed_days, scheduled_days, reps, lapses, state, step,
            last_review, created_at, updated_at, synced)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)''',
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
          if (row['step'] != null)
            Variable.withInt(row['step'] as int)
          else
            const Variable(null),
          if (row['last_review'] != null)
            Variable.withString(row['last_review'] as String)
          else
            const Variable(null),
          Variable.withString(row['created_at'] as String),
          Variable.withString(remoteUpdatedAt),
        ],
        updates: {_db.reviewCards},
      );
      return true;
    }

    final localUpdatedAt = existing.first.data['updated_at'] as String;
    if (remoteUpdatedAt.compareTo(localUpdatedAt) > 0) {
      if (remoteDeletedAt != null) {
        await _db.customUpdate(
          'UPDATE review_cards SET deleted_at = ?, updated_at = ?, synced = 1 WHERE id = ?',
          variables: [
            Variable.withString(remoteDeletedAt),
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.reviewCards},
        );
      } else {
        await _db.customUpdate(
          '''UPDATE review_cards SET
             entry_id = ?, headword = ?, pos = ?, due = ?,
             stability = ?, difficulty = ?, elapsed_days = ?,
             scheduled_days = ?, reps = ?, lapses = ?, state = ?,
             step = ?, last_review = ?, updated_at = ?, synced = 1
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
            if (row['step'] != null)
              Variable.withInt(row['step'] as int)
            else
              const Variable(null),
            if (row['last_review'] != null)
              Variable.withString(row['last_review'] as String)
            else
              const Variable(null),
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.reviewCards},
        );
      }
      return true;
    }
    return false;
  }

  Future<bool> _processReviewLogRow(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteDeletedAt = row['deleted_at'] as String?;

    final existing = await _db
        .customSelect(
          'SELECT id, deleted_at FROM review_logs WHERE id = ?',
          variables: [Variable.withString(id)],
          readsFrom: {_db.reviewLogs},
        )
        .get();

    if (existing.isEmpty) {
      if (remoteDeletedAt != null) return false;

      await _db.customInsert(
        '''INSERT INTO review_logs
           (id, card_id, rating, state, due, stability, difficulty,
            elapsed_days, scheduled_days, review_duration, reviewed_at,
            updated_at, synced)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)''',
        variables: [
          Variable.withString(id),
          Variable.withString(row['card_id'] as String),
          Variable.withInt(row['rating'] as int),
          Variable.withInt(row['state'] as int),
          Variable.withString(row['due'] as String),
          Variable.withReal((row['stability'] as num).toDouble()),
          Variable.withReal((row['difficulty'] as num).toDouble()),
          Variable.withInt(row['elapsed_days'] as int),
          Variable.withInt(row['scheduled_days'] as int),
          if (row['review_duration'] != null)
            Variable.withInt(row['review_duration'] as int)
          else
            const Variable(null),
          Variable.withString(row['reviewed_at'] as String),
          Variable.withString(row['updated_at'] as String),
        ],
        updates: {_db.reviewLogs},
      );
      return true;
    }

    if (remoteDeletedAt != null) {
      final localDeletedAt = existing.first.data['deleted_at'] as String?;
      if (localDeletedAt == null) {
        await _db.customUpdate(
          'UPDATE review_logs SET deleted_at = ?, updated_at = ?, synced = 1 WHERE id = ?',
          variables: [
            Variable.withString(remoteDeletedAt),
            Variable.withString(row['updated_at'] as String),
            Variable.withString(id),
          ],
          updates: {_db.reviewLogs},
        );
        return true;
      }
    }
    return false;
  }

  // ── Orchestration ──────────────────────────────────────────────────────────

  /// Sync order: push first, then pull.
  ///
  /// Push-first guarantees this device's local writes reach the server before
  /// the pull step runs, so a user opening another device immediately after
  /// will see them on the next foreground without alternating reopens. With
  /// last-write-wins by `updated_at`, our own rows are authoritative for
  /// themselves, so there's no "stale push overwrites fresh remote" race that
  /// pull-first would protect against.
  Future<void> syncReviewData() async {
    await pushAllUnsyncedReviewCards();
    await pushAllUnsyncedReviewLogs();
    await pullReviewCards();
    await pullReviewLogs();
  }

  Future<void> cleanupSoftDeletes({int retentionDays = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toUtc()
        .toIso8601String();
    await _db.customUpdate(
      'DELETE FROM review_logs WHERE deleted_at IS NOT NULL AND synced = 1 AND deleted_at < ?',
      variables: [Variable.withString(cutoff)],
      updates: {_db.reviewLogs},
    );
    await _db.customUpdate(
      'DELETE FROM review_cards WHERE deleted_at IS NOT NULL AND synced = 1 AND deleted_at < ?',
      variables: [Variable.withString(cutoff)],
      updates: {_db.reviewCards},
    );
  }
}
