import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

const _uuid = Uuid();

/// Data access for search history
class SearchHistoryDao {
  final UserDatabase _db;

  SearchHistoryDao(this._db);

  /// Add a search to history and enqueue for sync.
  Future<void> addSearch(String query, {int? entryId, String? headword}) async {
    final recordUuid = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await _db.into(_db.searchHistory).insert(
      SearchHistoryCompanion.insert(
        query: query,
        entryId: Value(entryId),
        headword: Value(headword),
      ).copyWith(
        uuid: Value(recordUuid),
        searchedAt: Value(now),
      ),
    );

    // Enqueue for sync
    await _db.into(_db.syncQueue).insert(
      SyncQueueCompanion.insert(
        tableName_: 'search_history',
        recordId: recordUuid,
        operation: 'INSERT',
        payload: jsonEncode({
          'id': recordUuid,
          'query': query,
          'entry_id': entryId,
          'headword': headword,
          'searched_at': now,
        }),
      ),
    );

    // Keep only last 100 entries
    await _db.customStatement('''
      DELETE FROM search_history WHERE id NOT IN (
        SELECT id FROM search_history ORDER BY searched_at DESC LIMIT 100
      )
    ''');
  }

  /// Get recent searches (most recent first)
  Future<List<SearchHistoryData>> getRecent({int limit = 50}) async {
    final rows = await (_db.select(_db.searchHistory)
          ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
          ..limit(limit))
        .get();
    return rows;
  }

  /// Get recent searches deduplicated by headword/query (most recent timestamp wins)
  Future<List<SearchHistoryData>> getRecentUnique({int limit = 30}) async {
    final rows = await _db.customSelect(
      '''SELECT * FROM search_history
         WHERE id IN (
           SELECT id FROM (
             SELECT id, ROW_NUMBER() OVER (
               PARTITION BY COALESCE(headword, query)
               ORDER BY searched_at DESC
             ) AS rn
             FROM search_history
           ) WHERE rn = 1
         )
         ORDER BY searched_at DESC
         LIMIT ?''',
      variables: [Variable.withInt(limit)],
      readsFrom: {_db.searchHistory},
    ).get();
    return rows.map((row) => _db.searchHistory.map(row.data)).toList();
  }

  /// Stream of deduplicated recent searches (auto-updates on DB changes)
  Stream<List<SearchHistoryData>> watchRecentUnique({int limit = 30}) {
    return _db.customSelect(
      '''SELECT * FROM search_history
         WHERE id IN (
           SELECT id FROM (
             SELECT id, ROW_NUMBER() OVER (
               PARTITION BY COALESCE(headword, query)
               ORDER BY searched_at DESC
             ) AS rn
             FROM search_history
           ) WHERE rn = 1
         )
         ORDER BY searched_at DESC
         LIMIT ?''',
      variables: [Variable.withInt(limit)],
      readsFrom: {_db.searchHistory},
    ).watch().map((rows) =>
      rows.map((row) => _db.searchHistory.map(row.data)).toList(),
    );
  }

  /// Delete all history entries for a given headword (or query if no headword)
  Future<void> deleteByHeadword(String headword) async {
    await (_db.delete(_db.searchHistory)
      ..where((t) => t.headword.equals(headword) | (t.headword.isNull() & t.query.equals(headword)))
    ).go();
  }

  /// Clear all search history
  Future<void> clearAll() async {
    await _db.delete(_db.searchHistory).go();
  }
}
