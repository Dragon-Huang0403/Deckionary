import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

const _uuid = Uuid();

/// Data access for search history (local only — sync is handled by SyncService)
class SearchHistoryDao {
  final UserDatabase _db;

  SearchHistoryDao(this._db);

  /// Add a search to history. Synced=0 until SyncService pushes it.
  Future<void> addSearch(
    String query, {
    int? entryId,
    String? headword,
    String pos = '',
  }) async {
    final now = DateTime.now().toIso8601String();
    await _db
        .into(_db.searchHistory)
        .insert(
          SearchHistoryCompanion.insert(
            query: query,
            entryId: Value(entryId),
            headword: Value(headword),
          ).copyWith(
            uuid: Value(_uuid.v4()),
            pos: Value(pos),
            searchedAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // Soft-delete entries beyond 100 active ones
    final now2 = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      '''UPDATE search_history SET deleted_at = ?, updated_at = ?, synced = 0
         WHERE deleted_at IS NULL AND id NOT IN (
           SELECT id FROM search_history
           WHERE deleted_at IS NULL
           ORDER BY searched_at DESC LIMIT 100
         )''',
      variables: [Variable.withString(now2), Variable.withString(now2)],
      updates: {_db.searchHistory},
    );
  }

  /// Get recent searches (most recent first)
  Future<List<SearchHistoryData>> getRecent({int limit = 50}) async {
    final rows =
        await (_db.select(_db.searchHistory)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
              ..limit(limit))
            .get();
    return rows;
  }

  /// Get recent searches deduplicated by headword+pos (most recent timestamp wins)
  Future<List<SearchHistoryData>> getRecentUnique({int limit = 30}) async {
    final rows = await _db
        .customSelect(
          '''SELECT * FROM search_history
         WHERE deleted_at IS NULL AND id IN (
           SELECT id FROM (
             SELECT id, ROW_NUMBER() OVER (
               PARTITION BY COALESCE(headword, query), pos
               ORDER BY searched_at DESC
             ) AS rn
             FROM search_history
             WHERE deleted_at IS NULL
           ) WHERE rn = 1
         )
         ORDER BY searched_at DESC
         LIMIT ?''',
          variables: [Variable.withInt(limit)],
          readsFrom: {_db.searchHistory},
        )
        .get();
    return rows.map((row) => _db.searchHistory.map(row.data)).toList();
  }

  /// Stream of deduplicated recent searches (auto-updates on DB changes)
  Stream<List<SearchHistoryData>> watchRecentUnique({int limit = 30}) {
    return _db
        .customSelect(
          '''SELECT * FROM search_history
         WHERE deleted_at IS NULL AND id IN (
           SELECT id FROM (
             SELECT id, ROW_NUMBER() OVER (
               PARTITION BY COALESCE(headword, query), pos
               ORDER BY searched_at DESC
             ) AS rn
             FROM search_history
             WHERE deleted_at IS NULL
           ) WHERE rn = 1
         )
         ORDER BY searched_at DESC
         LIMIT ?''',
          variables: [Variable.withInt(limit)],
          readsFrom: {_db.searchHistory},
        )
        .watch()
        .map(
          (rows) => rows.map((row) => _db.searchHistory.map(row.data)).toList(),
        );
  }

  /// Soft-delete a single history entry by its local ID.
  Future<void> deleteById(int id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(_db.searchHistory)..where((t) => t.id.equals(id))).write(
      SearchHistoryCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        synced: const Value(0),
      ),
    );
  }

  /// Soft-delete all history entries for a given headword (or query if no headword)
  Future<void> deleteByHeadword(String headword) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      '''UPDATE search_history SET deleted_at = ?, updated_at = ?, synced = 0
         WHERE deleted_at IS NULL
         AND (headword = ? OR (headword IS NULL AND query = ?))''',
      variables: [
        Variable.withString(now),
        Variable.withString(now),
        Variable.withString(headword),
        Variable.withString(headword),
      ],
      updates: {_db.searchHistory},
    );
  }

  /// Soft-delete all search history
  Future<void> clearAll() async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      '''UPDATE search_history SET deleted_at = ?, updated_at = ?, synced = 0
         WHERE deleted_at IS NULL''',
      variables: [Variable.withString(now), Variable.withString(now)],
      updates: {_db.searchHistory},
    );
  }
}
