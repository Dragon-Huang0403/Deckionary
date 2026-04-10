import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';

/// Generic sync service using outbox pattern.
/// Reads from local SyncQueue, pushes to Supabase, pulls remote changes.
class SyncService {
  final UserDatabase _db;
  final SupabaseClient _supabase;

  SyncService({required UserDatabase db, required SupabaseClient supabase})
      : _db = db,
        _supabase = supabase;

  String? get _userId => _supabase.auth.currentUser?.id;

  /// Push unsynced local changes to Supabase.
  Future<int> pushChanges() async {
    if (_userId == null) return 0;

    final unsynced = await (_db.select(_db.syncQueue)
          ..where((t) => t.synced.equals(0))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final entry in unsynced) {
      try {
        final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
        payload['user_id'] = _userId;

        if (entry.operation == 'INSERT') {
          await _supabase.from(entry.tableName_).upsert(payload);
        } else if (entry.operation == 'DELETE') {
          await _supabase.from(entry.tableName_).delete().eq('id', entry.recordId);
        }

        await (_db.update(_db.syncQueue)..where((t) => t.id.equals(entry.id)))
            .write(const SyncQueueCompanion(synced: Value(1)));
        pushed++;
      } catch (e) {
        // Skip failed entries, retry next sync cycle
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
            searchedAt: Value(row['searched_at'] as String),
            synced: const Value(1),
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

  /// Full sync: push local changes, then pull remote.
  Future<({int pushed, int pulled})> syncSearchHistory() async {
    final pushed = await pushChanges();
    final pulled = await pullSearchHistory();
    return (pushed: pushed, pulled: pulled);
  }

  Future<String?> _getLastSyncAt(String table) async {
    final rows = await _db.customSelect(
      'SELECT value FROM sync_meta WHERE key = ?',
      variables: [Variable.withString('${table}_last_sync_at')],
      readsFrom: {_db.syncMeta},
    ).get();
    return rows.isEmpty ? null : rows.first.data['value'] as String?;
  }

  Future<void> _setLastSyncAt(String table, String timestamp) async {
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(
        key: '${table}_last_sync_at',
        value: timestamp,
      ),
    );
  }
}
