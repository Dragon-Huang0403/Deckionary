import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import 'sync_meta_helpers.dart';

class SearchHistorySync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;

  SearchHistorySync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId;

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
      });

      await (_db.update(_db.searchHistory)..where((t) => t.id.equals(row.id)))
          .write(const SearchHistoryCompanion(synced: Value(1)));
    } catch (e) {
      debugPrint('Push search failed (will retry): $e');
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

  Future<int> pullSearchHistory() async {
    if (_getUserId() == null) return 0;

    final lastSyncAt = await getLastSyncAt(_db, 'search_history');

    var filter = _supabase
        .from('search_history')
        .select()
        .eq('user_id', _getUserId()!);

    if (lastSyncAt != null) {
      filter = filter.gt('searched_at', lastSyncAt);
    }

    final rows = await filter.order('searched_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      final uuid = row['id'] as String;
      final existing = await _db
          .customSelect(
            'SELECT id FROM search_history WHERE uuid = ?',
            variables: [Variable.withString(uuid)],
            readsFrom: {_db.searchHistory},
          )
          .get();

      if (existing.isEmpty) {
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
                synced: const Value(1),
              ),
            );
        pulled++;
      }
    }

    if (rows.isNotEmpty) {
      await setLastSyncAt(
        _db,
        'search_history',
        rows.first['searched_at'] as String,
      );
    }

    return pulled;
  }

  Future<({int pushed, int pulled})> syncSearchHistory() async {
    final pushed = await pushAllUnsynced();
    final pulled = await pullSearchHistory();
    return (pushed: pushed, pulled: pulled);
  }
}
