import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import 'sync_meta_helpers.dart';

class ReviewSync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;

  ReviewSync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId;

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
      });

      await _db.customUpdate(
        'UPDATE review_cards SET synced = 1 WHERE id = ?',
        variables: [Variable.withString(cardId)],
        updates: {_db.reviewCards},
      );
    } catch (e) {
      debugPrint('Push review card failed (will retry): $e');
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
      });

      await _db.customUpdate(
        'UPDATE review_logs SET synced = 1 WHERE id = ?',
        variables: [Variable.withString(logId)],
        updates: {_db.reviewLogs},
      );
    } catch (e) {
      debugPrint('Push review log failed (will retry): $e');
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

  Future<int> pullReviewCards() async {
    if (_getUserId() == null) return 0;

    final lastSyncAt = await getLastSyncAt(_db, 'review_cards');

    var filter = _supabase
        .from('review_cards')
        .select()
        .eq('user_id', _getUserId()!);

    if (lastSyncAt != null) {
      filter = filter.gt('updated_at', lastSyncAt);
    }

    final rows = await filter.order('updated_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      final id = row['id'] as String;
      final remoteUpdatedAt = row['updated_at'] as String;

      final existing = await _db
          .customSelect(
            'SELECT id, updated_at FROM review_cards WHERE id = ?',
            variables: [Variable.withString(id)],
            readsFrom: {_db.reviewCards},
          )
          .get();

      if (existing.isEmpty) {
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
        pulled++;
      } else {
        final localUpdatedAt = existing.first.data['updated_at'] as String;
        if (remoteUpdatedAt.compareTo(localUpdatedAt) > 0) {
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
          pulled++;
        }
      }
    }

    if (rows.isNotEmpty) {
      await setLastSyncAt(
        _db,
        'review_cards',
        rows.first['updated_at'] as String,
      );
    }

    return pulled;
  }

  Future<int> pullReviewLogs() async {
    if (_getUserId() == null) return 0;

    final lastSyncAt = await getLastSyncAt(_db, 'review_logs');

    var filter = _supabase
        .from('review_logs')
        .select()
        .eq('user_id', _getUserId()!);

    if (lastSyncAt != null) {
      filter = filter.gt('reviewed_at', lastSyncAt);
    }

    final rows = await filter.order('reviewed_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      final id = row['id'] as String;

      final existing = await _db
          .customSelect(
            'SELECT id FROM review_logs WHERE id = ?',
            variables: [Variable.withString(id)],
            readsFrom: {_db.reviewLogs},
          )
          .get();

      if (existing.isEmpty) {
        await _db.customInsert(
          '''INSERT INTO review_logs
             (id, card_id, rating, state, due, stability, difficulty,
              elapsed_days, scheduled_days, review_duration, reviewed_at, synced)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)''',
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
          ],
          updates: {_db.reviewLogs},
        );
        pulled++;
      }
    }

    if (rows.isNotEmpty) {
      await setLastSyncAt(
        _db,
        'review_logs',
        rows.first['reviewed_at'] as String,
      );
    }

    return pulled;
  }

  Future<void> syncReviewData() async {
    if (await _hasPendingReviewClear()) {
      try {
        await _executeClearRemoteReviewData();
        return;
      } catch (_) {
        return;
      }
    }
    await pushAllUnsyncedReviewCards();
    await pushAllUnsyncedReviewLogs();
    await pullReviewCards();
    await pullReviewLogs();
  }

  Future<void> clearRemoteReviewData() async {
    if (_getUserId() == null) return;
    try {
      await _executeClearRemoteReviewData();
    } catch (e) {
      debugPrint('Clear remote failed, will retry on next sync: $e');
      await _setPendingReviewClear(true);
    }
  }

  Future<void> _executeClearRemoteReviewData() async {
    if (_getUserId() == null) return;
    await _supabase.from('review_logs').delete().eq('user_id', _getUserId()!);
    await _supabase.from('review_cards').delete().eq('user_id', _getUserId()!);
    await setLastSyncAt(_db, 'review_cards', '');
    await setLastSyncAt(_db, 'review_logs', '');
    await _setPendingReviewClear(false);
  }

  // ── Pending review clear tracking ───────────────────────────────────────

  static const _pendingReviewClearKey = 'pending_review_clear';

  Future<bool> _hasPendingReviewClear() async {
    final rows = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [Variable.withString(_pendingReviewClearKey)],
          readsFrom: {_db.syncMeta},
        )
        .get();
    return rows.isNotEmpty && rows.first.data['value'] == 'true';
  }

  Future<void> _setPendingReviewClear(bool pending) async {
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: _pendingReviewClearKey,
            value: pending ? 'true' : '',
          ),
        );
  }
}
