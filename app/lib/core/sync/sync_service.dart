import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';

/// Sync service for search history.
/// Pushes immediately after each search, pulls on app resume.
class SyncService {
  final UserDatabase _db;
  final SupabaseClient _supabase;

  SyncService({required UserDatabase db, required SupabaseClient supabase})
      : _db = db,
        _supabase = supabase;

  String? get _userId => _supabase.auth.currentUser?.id;

  /// Push the most recent unsynced row immediately (fire-and-forget after search).
  Future<void> pushLatestSearch() async {
    if (_userId == null) return;
    try {
      final rows = await (_db.select(_db.searchHistory)
            ..where((t) => t.synced.equals(0))
            ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
            ..limit(1))
          .get();
      if (rows.isEmpty || rows.first.uuid.isEmpty) return;

      final row = rows.first;
      await _supabase.from('search_history').upsert({
        'id': row.uuid,
        'user_id': _userId,
        'query': row.query,
        'entry_id': row.entryId,
        'headword': row.headword,
        'pos': row.pos,
        'searched_at': row.searchedAt,
      });

      await (_db.update(_db.searchHistory)..where((t) => t.id.equals(row.id)))
          .write(const SearchHistoryCompanion(synced: Value(1)));
    } catch (e) {
      debugPrint('Push search failed (will retry): $e');
    }
  }

  /// Push all local rows with synced=0 to Supabase.
  /// Preserves original searched_at timestamps for correct cross-device ordering.
  Future<int> pushAllUnsynced() async {
    if (_userId == null) return 0;

    final unsynced = await (_db.select(_db.searchHistory)
          ..where((t) => t.synced.equals(0))
          ..orderBy([(t) => OrderingTerm.asc(t.searchedAt)]))
        .get();

    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      if (row.uuid.isEmpty) continue;
      try {
        await _supabase.from('search_history').upsert({
          'id': row.uuid,
          'user_id': _userId,
          'query': row.query,
          'entry_id': row.entryId,
          'headword': row.headword,
          'pos': row.pos,
          'searched_at': row.searchedAt,
        });

        // Mark as synced
        await (_db.update(_db.searchHistory)..where((t) => t.id.equals(row.id)))
            .write(const SearchHistoryCompanion(synced: Value(1)));
        pushed++;
      } catch (e) {
        // Skip failed rows, retry next sync cycle
        continue;
      }
    }
    return pushed;
  }

  /// Pull remote changes newer than last sync timestamp.
  Future<int> pullSearchHistory() async {
    if (_userId == null) return 0;

    final lastSyncAt = await _getLastSyncAt('search_history');

    var filter = _supabase
        .from('search_history')
        .select()
        .eq('user_id', _userId!);

    if (lastSyncAt != null) {
      filter = filter.gt('searched_at', lastSyncAt);
    }

    final rows = await filter.order('searched_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      // Check if we already have this record locally (by uuid)
      final uuid = row['id'] as String;
      final existing = await _db.customSelect(
        'SELECT id FROM search_history WHERE uuid = ?',
        variables: [Variable.withString(uuid)],
        readsFrom: {_db.searchHistory},
      ).get();

      if (existing.isEmpty) {
        await _db.into(_db.searchHistory).insert(
          SearchHistoryCompanion.insert(
            query: row['query'] as String,
            entryId: Value(row['entry_id'] as int?),
            headword: Value(row['headword'] as String?),
          ).copyWith(
            uuid: Value(uuid),
            pos: Value(row['pos'] as String? ?? ''),
            searchedAt: Value(row['searched_at'] as String),
            synced: const Value(1), // came from remote, already synced
          ),
        );
        pulled++;
      }
    }

    // Update last sync timestamp
    if (rows.isNotEmpty) {
      await _setLastSyncAt('search_history', rows.first['searched_at'] as String);
    }

    return pulled;
  }

  /// Full sync: push unsynced local rows, then pull remote changes.
  Future<({int pushed, int pulled})> syncSearchHistory() async {
    final pushed = await pushAllUnsynced();
    final pulled = await pullSearchHistory();
    return (pushed: pushed, pulled: pulled);
  }

  // ── Review Cards Sync ─────────────────────────────────────────────────────

  /// Push the latest unsynced review card (fire-and-forget after each review).
  Future<void> pushLatestReviewCard(String cardId) async {
    if (_userId == null) return;
    try {
      final rows = await _db.customSelect(
        'SELECT * FROM review_cards WHERE id = ?',
        variables: [Variable.withString(cardId)],
        readsFrom: {_db.reviewCards},
      ).get();
      if (rows.isEmpty) return;

      final row = rows.first.data;
      await _supabase.from('review_cards').upsert({
        'id': row['id'],
        'user_id': _userId,
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

  /// Push the latest unsynced review log.
  Future<void> pushLatestReviewLog(String logId) async {
    if (_userId == null) return;
    try {
      final rows = await _db.customSelect(
        'SELECT * FROM review_logs WHERE id = ?',
        variables: [Variable.withString(logId)],
        readsFrom: {_db.reviewLogs},
      ).get();
      if (rows.isEmpty) return;

      final row = rows.first.data;
      await _supabase.from('review_logs').upsert({
        'id': row['id'],
        'user_id': _userId,
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

  /// Push all unsynced review cards to Supabase.
  Future<int> pushAllUnsyncedReviewCards() async {
    if (_userId == null) return 0;

    final unsynced = await _db.customSelect(
      'SELECT * FROM review_cards WHERE synced = 0',
      readsFrom: {_db.reviewCards},
    ).get();
    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      final data = row.data;
      try {
        await _supabase.from('review_cards').upsert({
          'id': data['id'],
          'user_id': _userId,
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

  /// Push all unsynced review logs to Supabase.
  Future<int> pushAllUnsyncedReviewLogs() async {
    if (_userId == null) return 0;

    final unsynced = await _db.customSelect(
      'SELECT * FROM review_logs WHERE synced = 0',
      readsFrom: {_db.reviewLogs},
    ).get();
    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      final data = row.data;
      try {
        await _supabase.from('review_logs').upsert({
          'id': data['id'],
          'user_id': _userId,
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

  /// Pull remote review cards newer than last sync.
  Future<int> pullReviewCards() async {
    if (_userId == null) return 0;

    final lastSyncAt = await _getLastSyncAt('review_cards');

    var filter = _supabase
        .from('review_cards')
        .select()
        .eq('user_id', _userId!);

    if (lastSyncAt != null) {
      filter = filter.gt('updated_at', lastSyncAt);
    }

    final rows = await filter.order('updated_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      final id = row['id'] as String;
      final remoteUpdatedAt = row['updated_at'] as String;

      // Check if card exists locally
      final existing = await _db.customSelect(
        'SELECT id, updated_at FROM review_cards WHERE id = ?',
        variables: [Variable.withString(id)],
        readsFrom: {_db.reviewCards},
      ).get();

      if (existing.isEmpty) {
        // New card from remote — insert locally
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
            if (row['step'] != null) Variable.withInt(row['step'] as int) else const Variable(null),
            if (row['last_review'] != null) Variable.withString(row['last_review'] as String) else const Variable(null),
            Variable.withString(row['created_at'] as String),
            Variable.withString(remoteUpdatedAt),
          ],
          updates: {_db.reviewCards},
        );
        pulled++;
      } else {
        // Exists locally — only update if remote is newer
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
              if (row['step'] != null) Variable.withInt(row['step'] as int) else const Variable(null),
              if (row['last_review'] != null) Variable.withString(row['last_review'] as String) else const Variable(null),
              Variable.withString(remoteUpdatedAt),
              Variable.withString(id),
            ],
            updates: {_db.reviewCards},
          );
          pulled++;
        }
      }
    }

    // Update last sync timestamp
    if (rows.isNotEmpty) {
      await _setLastSyncAt('review_cards', rows.first['updated_at'] as String);
    }

    return pulled;
  }

  /// Pull remote review logs newer than last sync.
  Future<int> pullReviewLogs() async {
    if (_userId == null) return 0;

    final lastSyncAt = await _getLastSyncAt('review_logs');

    var filter = _supabase
        .from('review_logs')
        .select()
        .eq('user_id', _userId!);

    if (lastSyncAt != null) {
      filter = filter.gt('reviewed_at', lastSyncAt);
    }

    final rows = await filter.order('reviewed_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      final id = row['id'] as String;

      // Skip if already exists locally
      final existing = await _db.customSelect(
        'SELECT id FROM review_logs WHERE id = ?',
        variables: [Variable.withString(id)],
        readsFrom: {_db.reviewLogs},
      ).get();

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
            if (row['review_duration'] != null) Variable.withInt(row['review_duration'] as int) else const Variable(null),
            Variable.withString(row['reviewed_at'] as String),
          ],
          updates: {_db.reviewLogs},
        );
        pulled++;
      }
    }

    // Update last sync timestamp
    if (rows.isNotEmpty) {
      await _setLastSyncAt('review_logs', rows.first['reviewed_at'] as String);
    }

    return pulled;
  }

  /// Full sync for review data: push then pull.
  /// If a remote clear is pending (from an offline "clear progress"), execute it
  /// first so stale data doesn't get pulled back.
  Future<void> syncReviewData() async {
    if (await _hasPendingReviewClear()) {
      try {
        await _executeClearRemoteReviewData();
        // Don't pull — local is empty and remote was just cleared
        return;
      } catch (_) {
        // Still offline — skip the rest to avoid pulling stale data back
        return;
      }
    }
    await pushAllUnsyncedReviewCards();
    await pushAllUnsyncedReviewLogs();
    await pullReviewCards();
    await pullReviewLogs();
  }

  /// Delete all review cards and logs from Supabase and reset sync timestamps.
  /// On failure, sets a pending flag so the clear is retried on next sync.
  Future<void> clearRemoteReviewData() async {
    if (_userId == null) return;
    try {
      await _executeClearRemoteReviewData();
    } catch (e) {
      debugPrint('Clear remote failed, will retry on next sync: $e');
      await _setPendingReviewClear(true);
    }
  }

  Future<void> _executeClearRemoteReviewData() async {
    if (_userId == null) return;
    await _supabase.from('review_logs').delete().eq('user_id', _userId!);
    await _supabase.from('review_cards').delete().eq('user_id', _userId!);
    await _setLastSyncAt('review_cards', '');
    await _setLastSyncAt('review_logs', '');
    await _setPendingReviewClear(false);
  }

  // ── Settings Sync ──────────────────────────────────────────────────────

  /// Keys worth syncing across devices (review config + audio preferences).
  static const _syncedSettingKeys = [
    'new_cards_per_day',
    'max_reviews_per_day',
    'review_card_order',
    'review_auto_pronounce',
    'review_filter',
    'audio_dialect',
    'pronunciation_display',
    'auto_pronounce',
    'theme_mode',
  ];

  /// Push a single setting to Supabase (fire-and-forget after change).
  /// On failure, marks the key as dirty for retry on next sync.
  Future<void> pushSetting(String key, String value) async {
    if (_userId == null || !_syncedSettingKeys.contains(key)) return;
    try {
      await _supabase.from('user_settings').upsert({
        'user_id': _userId,
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _removeDirtySetting(key);
    } catch (e) {
      debugPrint('Push setting "$key" failed, marking dirty: $e');
      await _addDirtySetting(key);
    }
  }

  /// Push any settings that failed to sync previously.
  Future<void> pushDirtySettings() async {
    if (_userId == null) return;
    final dirty = await _getDirtySettings();
    if (dirty.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    for (final key in dirty) {
      final row = await (_db.select(_db.settings)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      if (row == null) {
        await _removeDirtySetting(key);
        continue;
      }
      try {
        await _supabase.from('user_settings').upsert({
          'user_id': _userId,
          'key': key,
          'value': row.value,
          'updated_at': now,
        });
        await _removeDirtySetting(key);
      } catch (e) {
        // Still offline — will retry next sync
        break;
      }
    }
  }

  /// Pull all settings from Supabase that are newer than local.
  Future<int> pullSettings() async {
    if (_userId == null) return 0;

    final lastSyncAt = await _getLastSyncAt('user_settings');

    var filter = _supabase
        .from('user_settings')
        .select()
        .eq('user_id', _userId!);

    if (lastSyncAt != null) {
      filter = filter.gt('updated_at', lastSyncAt);
    }

    final rows = await filter.order('updated_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      final key = row['key'] as String;
      final value = row['value'] as String;
      if (!_syncedSettingKeys.contains(key)) continue;

      // Write to local settings (overwrites local value)
      await _db.into(_db.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: key, value: value),
      );
      pulled++;
    }

    if (rows.isNotEmpty) {
      await _setLastSyncAt('user_settings', rows.first['updated_at'] as String);
    }

    return pulled;
  }

  /// Push all synced settings to Supabase (for initial sync after sign-in).
  Future<int> pushAllSettings() async {
    if (_userId == null) return 0;
    var pushed = 0;
    final now = DateTime.now().toUtc().toIso8601String();

    for (final key in _syncedSettingKeys) {
      final row = await (_db.select(_db.settings)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      if (row == null) continue;

      try {
        await _supabase.from('user_settings').upsert({
          'user_id': _userId,
          'key': key,
          'value': row.value,
          'updated_at': now,
        });
        pushed++;
      } catch (e) {
        continue;
      }
    }
    return pushed;
  }

  Future<String?> _getLastSyncAt(String table) async {
    final rows = await _db.customSelect(
      'SELECT value FROM sync_meta WHERE key = ?',
      variables: [Variable.withString('${table}_last_sync_at')],
      readsFrom: {_db.syncMeta},
    ).get();
    if (rows.isEmpty) return null;
    final value = rows.first.data['value'] as String?;
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> _setLastSyncAt(String table, String timestamp) async {
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(
        key: '${table}_last_sync_at',
        value: timestamp,
      ),
    );
  }

  // ── Dirty settings tracking ─────────────────────────────────────────────

  static const _dirtySettingsKey = 'dirty_settings';

  Future<Set<String>> _getDirtySettings() async {
    final rows = await _db.customSelect(
      'SELECT value FROM sync_meta WHERE key = ?',
      variables: [Variable.withString(_dirtySettingsKey)],
      readsFrom: {_db.syncMeta},
    ).get();
    if (rows.isEmpty) return {};
    final csv = rows.first.data['value'] as String;
    return csv.isEmpty ? {} : csv.split(',').toSet();
  }

  Future<void> _addDirtySetting(String key) async {
    final dirty = await _getDirtySettings();
    dirty.add(key);
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(key: _dirtySettingsKey, value: dirty.join(',')),
    );
  }

  Future<void> _removeDirtySetting(String key) async {
    final dirty = await _getDirtySettings();
    if (!dirty.remove(key)) return;
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(key: _dirtySettingsKey, value: dirty.join(',')),
    );
  }

  // ── Pending review clear tracking ───────────────────────────────────────

  static const _pendingReviewClearKey = 'pending_review_clear';

  Future<bool> _hasPendingReviewClear() async {
    final rows = await _db.customSelect(
      'SELECT value FROM sync_meta WHERE key = ?',
      variables: [Variable.withString(_pendingReviewClearKey)],
      readsFrom: {_db.syncMeta},
    ).get();
    return rows.isNotEmpty && rows.first.data['value'] == 'true';
  }

  Future<void> _setPendingReviewClear(bool pending) async {
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(
        key: _pendingReviewClearKey,
        value: pending ? 'true' : '',
      ),
    );
  }
}
