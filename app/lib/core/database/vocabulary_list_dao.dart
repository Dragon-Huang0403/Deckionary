import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

const _uuid = Uuid();

/// Data access for vocabulary lists ("My Words" custom word list).
class VocabularyListDao {
  final UserDatabase _db;
  static const myWordsName = 'My Words';

  VocabularyListDao(this._db);

  // ── List management ───────────────────────────────────────────────────────

  /// Get or lazily create the single "My Words" list.
  Future<VocabularyList> getOrCreateMyWordsList() async {
    final existing = await (_db.select(_db.vocabularyLists)
          ..where((t) => t.deletedAt.isNull() & t.name.equals(myWordsName))
          ..orderBy([
            (t) => OrderingTerm(expression: t.synced, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .get();
    if (existing.isNotEmpty) return existing.first;

    final now = DateTime.now().toUtc().toIso8601String();
    final companion = VocabularyListsCompanion.insert(
      id: _uuid.v4(),
      name: myWordsName,
      createdAt: Value(now),
      updatedAt: Value(now),
      synced: Value(0),
    );
    await _db.into(_db.vocabularyLists).insert(companion);
    return (_db.select(_db.vocabularyLists)
          ..where((t) => t.name.equals(myWordsName) & t.deletedAt.isNull())
          ..limit(1))
        .getSingle();
  }

  // ── Entry management ──────────────────────────────────────────────────────

  /// Add a word to a vocabulary list. No-op if already present.
  Future<void> addEntry({
    required String listId,
    required int entryId,
    required String headword,
    required String pos,
  }) async {
    if (await containsEntry(listId, entryId)) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await _db
        .into(_db.vocabularyListEntries)
        .insert(
          VocabularyListEntriesCompanion.insert(
            id: _uuid.v4(),
            listId: listId,
            entryId: entryId,
            headword: headword,
            pos: Value(pos),
            addedAt: Value(now),
            updatedAt: Value(now),
            synced: Value(0),
          ),
        );
  }

  /// Soft-delete an entry from the list and optionally its review card.
  /// Returns the entryId of the removed entry (for review card deletion).
  Future<int?> removeEntry(String entryId) async {
    final now = DateTime.now().toUtc().toIso8601String();

    // Find the entry first to get the dictionary entryId
    final entry =
        await (_db.select(_db.vocabularyListEntries)
              ..where((t) => t.id.equals(entryId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    if (entry == null) return null;

    // Soft-delete the list entry
    await _db.customUpdate(
      '''UPDATE vocabulary_list_entries
         SET deleted_at = ?, updated_at = ?, synced = 0
         WHERE id = ?''',
      variables: [
        Variable.withString(now),
        Variable.withString(now),
        Variable.withString(entryId),
      ],
      updates: {_db.vocabularyListEntries},
    );

    return entry.entryId;
  }

  /// Soft-delete a review card by dictionary entry ID.
  Future<void> deleteReviewCard(int dictEntryId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.customUpdate(
      '''UPDATE review_cards
         SET deleted_at = ?, updated_at = ?, synced = 0
         WHERE entry_id = ? AND deleted_at IS NULL''',
      variables: [
        Variable.withString(now),
        Variable.withString(now),
        Variable.withInt(dictEntryId),
      ],
      updates: {_db.reviewCards},
    );
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  /// Check if a dictionary entry is in the list.
  Future<bool> containsEntry(String listId, int entryId) async {
    final result = await _db
        .customSelect(
          '''SELECT 1 FROM vocabulary_list_entries
             WHERE list_id = ? AND entry_id = ? AND deleted_at IS NULL
             LIMIT 1''',
          variables: [Variable.withString(listId), Variable.withInt(entryId)],
          readsFrom: {_db.vocabularyListEntries},
        )
        .get();
    return result.isNotEmpty;
  }

  /// Get all active entries in a list, ordered by the given mode.
  Future<List<VocabularyListEntry>> getEntries(
    String listId, {
    String order = 'oldest',
  }) async {
    final orderClause = switch (order) {
      'newest' => 'ORDER BY added_at DESC',
      'random' => 'ORDER BY RANDOM()',
      _ => 'ORDER BY added_at ASC', // oldest (default)
    };
    final rows = await _db
        .customSelect(
          '''SELECT * FROM vocabulary_list_entries
             WHERE list_id = ? AND deleted_at IS NULL
             $orderClause''',
          variables: [Variable.withString(listId)],
          readsFrom: {_db.vocabularyListEntries},
        )
        .get();
    return rows.map((r) => _db.vocabularyListEntries.map(r.data)).toList();
  }

  /// Watch all active entries (for reactive UI).
  /// Display order follows setting: oldest = ASC, newest = DESC.
  /// Random keeps oldest-first display (randomness only in queue selection).
  Stream<List<VocabularyListEntry>> watchEntries(
    String listId, {
    String order = 'oldest',
  }) {
    final orderClause = switch (order) {
      'newest' => 'ORDER BY added_at DESC',
      _ => 'ORDER BY added_at ASC', // oldest + random both show oldest-first
    };
    return _db
        .customSelect(
          '''SELECT * FROM vocabulary_list_entries
             WHERE list_id = ? AND deleted_at IS NULL
             $orderClause''',
          variables: [Variable.withString(listId)],
          readsFrom: {_db.vocabularyListEntries},
        )
        .watch()
        .map(
          (rows) =>
              rows.map((r) => _db.vocabularyListEntries.map(r.data)).toList(),
        );
  }

  /// Count active entries in a list.
  Future<int> countEntries(String listId) async {
    final result = await _db
        .customSelect(
          '''SELECT COUNT(*) as cnt FROM vocabulary_list_entries
             WHERE list_id = ? AND deleted_at IS NULL''',
          variables: [Variable.withString(listId)],
          readsFrom: {_db.vocabularyListEntries},
        )
        .getSingle();
    return result.data['cnt'] as int;
  }

  /// Get new entry IDs from the list that don't have review cards yet.
  /// Used by queue building to draw My Words cards.
  Future<List<int>> getNewEntryIds({
    required String listId,
    required int limit,
    required Set<int> excludeIds,
    String order = 'oldest',
  }) async {
    final orderClause = switch (order) {
      'newest' => 'ORDER BY vle.added_at DESC',
      'random' => 'ORDER BY RANDOM()',
      _ => 'ORDER BY vle.added_at ASC', // oldest (default)
    };
    final rows = await _db
        .customSelect(
          '''SELECT vle.entry_id FROM vocabulary_list_entries vle
             LEFT JOIN review_cards rc
               ON rc.entry_id = vle.entry_id AND rc.deleted_at IS NULL
             WHERE vle.list_id = ? AND vle.deleted_at IS NULL
               AND rc.id IS NULL
             $orderClause
             LIMIT ?''',
          variables: [Variable.withString(listId), Variable.withInt(limit)],
          readsFrom: {_db.vocabularyListEntries, _db.reviewCards},
        )
        .get();

    return rows
        .map((r) => r.data['entry_id'] as int)
        .where((id) => !excludeIds.contains(id))
        .toList();
  }
}
