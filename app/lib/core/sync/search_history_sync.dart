import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../logging/logging_service.dart';
import 'table_sync.dart';

class SearchHistorySync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;
  final TableSync _tableSync;

  SearchHistorySync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
    required TableSync tableSync,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId,
       _tableSync = tableSync;

  // ── Push (unchanged) ───────────────────────────────────────────────────────

  Future<void> pushLatestSearch() async {
    if (_getUserId() == null) return;
    try {
      final rows =
          await (_db.select(_db.searchHistory)
                ..where((t) => t.synced.equals(0))
                ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
                ..limit(1))
              .get();
      if (rows.isEmpty || rows.first.uuid.isEmpty) return;

      final row = rows.first;
      await _supabase.from('search_history').upsert({
        'id': row.uuid,
        'user_id': _getUserId(),
        'query': row.query,
        'entry_id': row.entryId,
        'headword': row.headword,
        'pos': row.pos,
        'searched_at': row.searchedAt,
        'updated_at': row.updatedAt ?? row.searchedAt,
        'deleted_at': row.deletedAt,
      });

      await (_db.update(_db.searchHistory)..where((t) => t.id.equals(row.id)))
          .write(const SearchHistoryCompanion(synced: Value(1)));
    } catch (e) {
      globalTalker.error('[Sync] Push search failed (will retry): $e');
    }
  }

  Future<int> pushAllUnsynced() async {
    if (_getUserId() == null) return 0;

    final unsynced =
        await (_db.select(_db.searchHistory)
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
          'user_id': _getUserId(),
          'query': row.query,
          'entry_id': row.entryId,
          'headword': row.headword,
          'pos': row.pos,
          'searched_at': row.searchedAt,
          'updated_at': row.updatedAt ?? row.searchedAt,
          'deleted_at': row.deletedAt,
        });

        await (_db.update(_db.searchHistory)..where((t) => t.id.equals(row.id)))
            .write(const SearchHistoryCompanion(synced: Value(1)));
        pushed++;
      } catch (e) {
        continue;
      }
    }
    return pushed;
  }

  // ── Pull (delegated to TableSync) ──────────────────────────────────────────

  Future<int> pullSearchHistory() => _tableSync.pull(
    remoteTable: 'search_history',
    watermarkKey: 'search_history',
    processRow: _processSearchHistoryRow,
  );

  Future<bool> _processSearchHistoryRow(Map<String, dynamic> row) async {
    final uuid = row['id'] as String;
    final remoteDeletedAt = row['deleted_at'] as String?;

    final existing = await _db
        .customSelect(
          'SELECT id, deleted_at FROM search_history WHERE uuid = ?',
          variables: [Variable.withString(uuid)],
          readsFrom: {_db.searchHistory},
        )
        .get();

    if (existing.isEmpty) {
      if (remoteDeletedAt != null) return false;

      await _db
          .into(_db.searchHistory)
          .insert(
            SearchHistoryCompanion.insert(
              query: row['query'] as String,
              entryId: Value(row['entry_id'] as int?),
              headword: Value(row['headword'] as String?),
            ).copyWith(
              uuid: Value(uuid),
              pos: Value(row['pos'] as String? ?? ''),
              searchedAt: Value(row['searched_at'] as String),
              updatedAt: Value(row['updated_at'] as String),
              synced: const Value(1),
            ),
          );
      return true;
    }

    if (remoteDeletedAt != null) {
      final localDeletedAt = existing.first.data['deleted_at'] as String?;
      if (localDeletedAt == null) {
        final localId = existing.first.data['id'] as int;
        await _db.customUpdate(
          'UPDATE search_history SET deleted_at = ?, updated_at = ?, synced = 1 WHERE id = ?',
          variables: [
            Variable.withString(remoteDeletedAt),
            Variable.withString(row['updated_at'] as String),
            Variable.withInt(localId),
          ],
          updates: {_db.searchHistory},
        );
        return true;
      }
    }
    return false;
  }

  // ── Orchestration ──────────────────────────────────────────────────────────

  /// Sync order: push first, then pull. See ReviewSync.syncReviewData for
  /// the rationale.
  Future<({int pushed, int pulled})> syncSearchHistory() async {
    final pushed = await pushAllUnsynced();
    final pulled = await pullSearchHistory();
    return (pushed: pushed, pulled: pulled);
  }

  Future<void> cleanupSoftDeletes({int retentionDays = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toUtc()
        .toIso8601String();
    await _db.customUpdate(
      'DELETE FROM search_history WHERE deleted_at IS NOT NULL AND synced = 1 AND deleted_at < ?',
      variables: [Variable.withString(cutoff)],
      updates: {_db.searchHistory},
    );
  }
}
