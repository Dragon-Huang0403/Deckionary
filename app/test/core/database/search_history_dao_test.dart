import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/core/database/search_history_dao.dart';

import '../../test_helpers.dart';

void main() {
  late UserDatabase db;
  late SearchHistoryDao dao;

  setUp(() {
    db = createTestUserDb();
    dao = SearchHistoryDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // addSearch / getRecent
  // ---------------------------------------------------------------------------
  group('addSearch / getRecent', () {
    test('added search appears in getRecent', () async {
      await dao.addSearch('hello', headword: 'hello', pos: 'noun');
      final results = await dao.getRecent();
      expect(results, hasLength(1));
      expect(results.first.query, 'hello');
      expect(results.first.headword, 'hello');
      expect(results.first.pos, 'noun');
    });

    test('most recent entry is first', () async {
      await dao.addSearch('first');
      await dao.addSearch('second');
      await dao.addSearch('third');
      final results = await dao.getRecent();
      expect(results.first.query, 'third');
      expect(results.last.query, 'first');
    });

    test('limit parameter is respected', () async {
      for (var i = 0; i < 10; i++) {
        await dao.addSearch('word$i');
      }
      final results = await dao.getRecent(limit: 3);
      expect(results, hasLength(3));
    });

    test('deleted entries do not appear', () async {
      await dao.addSearch('visible');
      await dao.addSearch('hidden');
      final before = await dao.getRecent();
      await dao.deleteById(before.first.id); // newest = 'hidden'
      final after = await dao.getRecent();
      expect(after, hasLength(1));
      expect(after.first.query, 'visible');
    });
  });

  // ---------------------------------------------------------------------------
  // getRecentUnique
  // ---------------------------------------------------------------------------
  group('getRecentUnique', () {
    test('deduplicates by headword+pos, keeps most recent', () async {
      await dao.addSearch('run', headword: 'run', pos: 'verb');
      await dao.addSearch('run', headword: 'run', pos: 'verb');
      await dao.addSearch('run', headword: 'run', pos: 'verb');
      final results = await dao.getRecentUnique();
      expect(results, hasLength(1));
      expect(results.first.headword, 'run');
    });

    test('same headword different pos counts as two entries', () async {
      await dao.addSearch('run', headword: 'run', pos: 'verb');
      await dao.addSearch('run', headword: 'run', pos: 'noun');
      final results = await dao.getRecentUnique();
      expect(results, hasLength(2));
      final posList = results.map((r) => r.pos).toSet();
      expect(posList, containsAll(['verb', 'noun']));
    });

    test('limit parameter is respected', () async {
      await dao.addSearch('apple', headword: 'apple', pos: 'noun');
      await dao.addSearch('banana', headword: 'banana', pos: 'noun');
      await dao.addSearch('cherry', headword: 'cherry', pos: 'noun');
      final results = await dao.getRecentUnique(limit: 2);
      expect(results, hasLength(2));
    });

    test('deduplicates queries without headword using query value', () async {
      await dao.addSearch('raw query');
      await dao.addSearch('raw query');
      final results = await dao.getRecentUnique();
      expect(results, hasLength(1));
      expect(results.first.query, 'raw query');
    });
  });

  // ---------------------------------------------------------------------------
  // auto-trim to 100
  // ---------------------------------------------------------------------------
  group('auto-trim to 100', () {
    test('inserting 101 entries soft-deletes the oldest', () async {
      for (var i = 1; i <= 101; i++) {
        await dao.addSearch('word$i');
      }
      final active = await dao.getRecent(limit: 200);
      expect(active, hasLength(100));
      // The oldest entry (word1) should no longer be present
      expect(active.any((r) => r.query == 'word1'), isFalse);
      // The newest entry (word101) should be present
      expect(active.any((r) => r.query == 'word101'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // soft-delete
  // ---------------------------------------------------------------------------
  group('soft-delete', () {
    test('deleteById removes entry from getRecent', () async {
      await dao.addSearch('target');
      final before = await dao.getRecent();
      await dao.deleteById(before.first.id);
      final after = await dao.getRecent();
      expect(after, isEmpty);
    });

    test('deleteById sets synced=0 and deleted_at', () async {
      await dao.addSearch('target');
      final before = await dao.getRecent();
      await dao.deleteById(before.first.id);
      final rows = await db
          .customSelect(
            'SELECT synced, deleted_at FROM search_history WHERE id = ?',
            variables: [Variable.withInt(before.first.id)],
          )
          .get();
      expect(rows.first.data['synced'], 0);
      expect(rows.first.data['deleted_at'], isNotNull);
    });

    test('deleteByHeadwordAndPos removes all matching entries', () async {
      await dao.addSearch('run', headword: 'run', pos: 'verb');
      await dao.addSearch('run', headword: 'run', pos: 'verb');
      await dao.addSearch('run', headword: 'run', pos: 'noun'); // different pos
      await dao.deleteByHeadwordAndPos('run', 'verb');
      final results = await dao.getRecent();
      expect(results, hasLength(1));
      expect(results.first.pos, 'noun');
    });

    test('deleteByHeadwordAndPos sets synced=0 on affected rows', () async {
      await dao.addSearch('run', headword: 'run', pos: 'verb');
      final before = await dao.getRecent();
      await dao.deleteByHeadwordAndPos('run', 'verb');
      final rows = await db
          .customSelect(
            'SELECT synced, deleted_at FROM search_history WHERE id = ?',
            variables: [Variable.withInt(before.first.id)],
          )
          .get();
      expect(rows.first.data['synced'], 0);
      expect(rows.first.data['deleted_at'], isNotNull);
    });

    test('clearAll removes all entries from getRecent', () async {
      await dao.addSearch('word1');
      await dao.addSearch('word2');
      await dao.addSearch('word3');
      await dao.clearAll();
      final results = await dao.getRecent();
      expect(results, isEmpty);
    });

    test('clearAll sets synced=0 on all rows', () async {
      await dao.addSearch('word1');
      await dao.addSearch('word2');
      await dao.clearAll();
      final rows = await db
          .customSelect('SELECT synced, deleted_at FROM search_history')
          .get();
      for (final row in rows) {
        expect(row.data['synced'], 0);
        expect(row.data['deleted_at'], isNotNull);
      }
    });
  });
}
