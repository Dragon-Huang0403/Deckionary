import 'package:drift/drift.dart';
import 'app_database.dart';

/// Data access for review cards and logs (FSRS spaced repetition).
class ReviewDao {
  final UserDatabase _db;
  final DictionaryDatabase _dictDb;

  ReviewDao({required UserDatabase db, required DictionaryDatabase dictDb})
      : _db = db,
        _dictDb = dictDb;

  // ── Review Cards ──────────────────────────────────────────────────────────

  /// Get all cards due for review (due <= now), ordered by due date.
  Future<List<ReviewCard>> getDueCards({int limit = 200}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return (_db.select(_db.reviewCards)
          ..where((t) => t.due.isSmallerOrEqualValue(now))
          ..orderBy([(t) => OrderingTerm.asc(t.due)])
          ..limit(limit))
        .get();
  }

  /// Get a single review card by entry ID.
  Future<ReviewCard?> getCardByEntryId(int entryId) async {
    return (_db.select(_db.reviewCards)
          ..where((t) => t.entryId.equals(entryId)))
        .getSingleOrNull();
  }

  /// Get all existing review card entry IDs (for filtering new cards).
  Future<Set<int>> getAllReviewedEntryIds() async {
    final rows = await _db.customSelect(
      'SELECT entry_id FROM review_cards',
      readsFrom: {_db.reviewCards},
    ).get();
    return rows.map((r) => r.data['entry_id'] as int).toSet();
  }

  /// Find new entry IDs matching the filter that don't have review cards yet.
  /// Uses cross-database strategy: query dict DB, then subtract existing cards.
  /// [randomOrder] shuffles the result instead of alphabetical order.
  Future<List<int>> getNewEntryIds({
    List<String> cefrLevels = const [],
    bool ox3000 = false,
    bool ox5000 = false,
    required int limit,
    bool randomOrder = false,
  }) async {
    // Get all candidate IDs from dictionary DB (alphabetical)
    final candidates = await _dictDb.getFilteredEntryIds(
      cefrLevels: cefrLevels,
      ox3000: ox3000,
      ox5000: ox5000,
      limit: 10000, // fetch all candidates
    );
    if (candidates.isEmpty) return [];

    // Get existing review card entry IDs
    final existing = await getAllReviewedEntryIds();

    // Subtract existing
    final newIds = candidates.where((id) => !existing.contains(id)).toList();

    // Apply ordering
    if (randomOrder) newIds.shuffle();

    return newIds.take(limit).toList();
  }

  /// Insert or update a review card.
  Future<void> upsertCard(ReviewCardsCompanion card) async {
    await _db.into(_db.reviewCards).insertOnConflictUpdate(card);
  }

  /// Insert a review log entry.
  Future<void> insertLog(ReviewLogsCompanion log) async {
    await _db.into(_db.reviewLogs).insert(log);
  }

  // ── Counts & Stats ────────────────────────────────────────────────────────

  /// Count cards due right now.
  Future<int> countDueCards() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final result = await _db.customSelect(
      'SELECT COUNT(*) as cnt FROM review_cards WHERE due <= ?',
      variables: [Variable.withString(now)],
      readsFrom: {_db.reviewCards},
    ).getSingle();
    return result.data['cnt'] as int;
  }

  /// Count cards reviewed today.
  Future<int> countReviewedToday() async {
    final todayStart = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(todayStart.year, todayStart.month, todayStart.day).toIso8601String();
    final result = await _db.customSelect(
      'SELECT COUNT(*) as cnt FROM review_logs WHERE reviewed_at >= ?',
      variables: [Variable.withString(startOfDay)],
      readsFrom: {_db.reviewLogs},
    ).getSingle();
    return result.data['cnt'] as int;
  }

  /// Count new cards learned today (first review ever for a card, today).
  Future<int> countNewLearnedToday() async {
    final todayStart = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(todayStart.year, todayStart.month, todayStart.day).toIso8601String();
    final result = await _db.customSelect(
      '''SELECT COUNT(DISTINCT card_id) as cnt FROM review_logs
         WHERE reviewed_at >= ?
         AND card_id IN (
           SELECT card_id FROM review_logs
           GROUP BY card_id
           HAVING MIN(reviewed_at) >= ?
         )''',
      variables: [Variable.withString(startOfDay), Variable.withString(startOfDay)],
      readsFrom: {_db.reviewLogs},
    ).getSingle();
    return result.data['cnt'] as int;
  }

  /// Total review cards in the system.
  Future<int> countTotalCards() async {
    final result = await _db.customSelect(
      'SELECT COUNT(*) as cnt FROM review_cards',
      readsFrom: {_db.reviewCards},
    ).getSingle();
    return result.data['cnt'] as int;
  }

  /// Watch due card count as a stream (for reactive UI).
  Stream<int> watchDueCount() {
    final now = DateTime.now().toUtc().toIso8601String();
    return _db
        .customSelect(
          'SELECT COUNT(*) as cnt FROM review_cards WHERE due <= ?',
          variables: [Variable.withString(now)],
          readsFrom: {_db.reviewCards},
        )
        .watchSingle()
        .map((row) => row.data['cnt'] as int);
  }

  /// Delete all review cards and logs, resetting progress.
  Future<void> clearAllProgress() async {
    await _db.delete(_db.reviewLogs).go();
    await _db.delete(_db.reviewCards).go();
  }

  /// Look up dictionary entry data for a list of entry IDs.
  Future<List<Map<String, dynamic>>> getEntryDetails(List<int> entryIds) async {
    return _dictDb.getEntriesByIds(entryIds);
  }
}
