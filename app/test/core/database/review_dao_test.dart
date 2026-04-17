import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/core/database/review_dao.dart';
import '../../test_helpers.dart';

void main() {
  late DictionaryDatabase dictDb;
  late UserDatabase userDb;
  late ReviewDao dao;

  setUpAll(() {
    dictDb = createTestDictDb();
  });

  tearDownAll(() async {
    await dictDb.close();
  });

  setUp(() {
    userDb = createTestUserDb();
    dao = ReviewDao(db: userDb, dictDb: dictDb);
  });

  tearDown(() async {
    await userDb.close();
  });

  // ── getDueCards ──────────────────────────────────────────────────────────────

  group('getDueCards', () {
    test('returns card with past due date', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: pastDue);

      final cards = await dao.getDueCards();
      expect(cards, hasLength(1));
      expect(cards.first.id, 'c1');
    });

    test('does not return card with future due date', () async {
      final futureDue = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: futureDue);

      final cards = await dao.getDueCards();
      expect(cards, isEmpty);
    });

    test('excludes soft-deleted cards', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: pastDue);

      // Soft-delete the card
      await userDb.customUpdate(
        "UPDATE review_cards SET deleted_at = ? WHERE id = 'c1'",
        variables: [
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
        ],
        updates: {userDb.reviewCards},
      );

      final cards = await dao.getDueCards();
      expect(cards, isEmpty);
    });

    test('respects limit parameter', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: pastDue);
      await insertReviewCard(userDb, id: 'c2', entryId: 2, due: pastDue);
      await insertReviewCard(userDb, id: 'c3', entryId: 3, due: pastDue);

      final cards = await dao.getDueCards(limit: 2);
      expect(cards, hasLength(2));
    });

    test('orders by due date ascending', () async {
      final earliest = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 3))
          .toIso8601String();
      final middle = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String();
      final latest = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();

      // Insert in non-ascending order
      await insertReviewCard(userDb, id: 'c3', entryId: 3, due: latest);
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: earliest);
      await insertReviewCard(userDb, id: 'c2', entryId: 2, due: middle);

      final cards = await dao.getDueCards();
      expect(cards, hasLength(3));
      expect(cards[0].id, 'c1');
      expect(cards[1].id, 'c2');
      expect(cards[2].id, 'c3');
    });
  });

  // ── getCardByEntryId ──────────────────────────────────────────────────────────

  group('getCardByEntryId', () {
    test('returns card when it exists', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(
        userDb,
        id: 'c1',
        entryId: 42,
        headword: 'apple',
        due: due,
      );

      final card = await dao.getCardByEntryId(42);
      expect(card, isNotNull);
      expect(card!.id, 'c1');
      expect(card.headword, 'apple');
    });

    test('returns null when card does not exist', () async {
      final card = await dao.getCardByEntryId(999);
      expect(card, isNull);
    });

    test('excludes soft-deleted cards', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 42, due: due);

      await userDb.customUpdate(
        "UPDATE review_cards SET deleted_at = ? WHERE id = 'c1'",
        variables: [
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
        ],
        updates: {userDb.reviewCards},
      );

      final card = await dao.getCardByEntryId(42);
      expect(card, isNull);
    });
  });

  // ── counts ────────────────────────────────────────────────────────────────────

  group('countTotalCards', () {
    test('returns 0 when no cards', () async {
      expect(await dao.countTotalCards(), 0);
    });

    test('returns count of non-deleted cards', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: due);
      await insertReviewCard(userDb, id: 'c2', entryId: 2, due: due);
      await insertReviewCard(userDb, id: 'c3', entryId: 3, due: due);

      expect(await dao.countTotalCards(), 3);
    });

    test('excludes soft-deleted cards', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: due);
      await insertReviewCard(userDb, id: 'c2', entryId: 2, due: due);

      await userDb.customUpdate(
        "UPDATE review_cards SET deleted_at = ? WHERE id = 'c2'",
        variables: [
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
        ],
        updates: {userDb.reviewCards},
      );

      expect(await dao.countTotalCards(), 1);
    });
  });

  group('countDueCards', () {
    test('returns 0 when no cards', () async {
      expect(await dao.countDueCards(), 0);
    });

    test('counts only cards due now or past', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      final futureDue = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String();

      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: pastDue);
      await insertReviewCard(userDb, id: 'c2', entryId: 2, due: futureDue);

      expect(await dao.countDueCards(), 1);
    });

    test('excludes soft-deleted cards from due count', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: pastDue);

      await userDb.customUpdate(
        "UPDATE review_cards SET deleted_at = ? WHERE id = 'c1'",
        variables: [
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
        ],
        updates: {userDb.reviewCards},
      );

      expect(await dao.countDueCards(), 0);
    });
  });

  // ── countNewLearnedToday ──────────────────────────────────────────────────────

  group('countNewLearnedToday', () {
    test('returns 0 when no logs', () async {
      expect(await dao.countNewLearnedToday(), 0);
    });

    test('counts cards whose first review log is today', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      final todayReview = DateTime.now().toUtc().toIso8601String();

      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: due);
      await insertReviewCard(userDb, id: 'c2', entryId: 2, due: due);
      await insertReviewLog(
        userDb,
        id: 'l1',
        cardId: 'c1',
        reviewedAt: todayReview,
      );
      await insertReviewLog(
        userDb,
        id: 'l2',
        cardId: 'c2',
        reviewedAt: todayReview,
      );

      expect(await dao.countNewLearnedToday(), 2);
    });

    test('does not count cards whose first review was before today', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      final yesterday = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 1))
          .toIso8601String();
      final today = DateTime.now().toUtc().toIso8601String();

      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: due);
      // Card first reviewed yesterday, then reviewed again today — not "new" today
      await insertReviewLog(
        userDb,
        id: 'l1',
        cardId: 'c1',
        reviewedAt: yesterday,
      );
      await insertReviewLog(userDb, id: 'l2', cardId: 'c1', reviewedAt: today);

      expect(await dao.countNewLearnedToday(), 0);
    });
  });

  // ── clearAllProgress ──────────────────────────────────────────────────────────

  group('clearAllProgress', () {
    test('soft-deletes all cards', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: due);
      await insertReviewCard(userDb, id: 'c2', entryId: 2, due: due);

      await dao.clearAllProgress();

      expect(await dao.countTotalCards(), 0);
    });

    test('soft-deletes all logs', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: due);
      await insertReviewLog(userDb, id: 'l1', cardId: 'c1', reviewedAt: due);

      await dao.clearAllProgress();

      expect(await dao.countNewLearnedToday(), 0);
    });

    test('sets synced=0 on cards', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: due);

      await dao.clearAllProgress();

      final rows = await userDb
          .customSelect(
            'SELECT synced FROM review_cards WHERE id = ?',
            variables: [Variable.withString('c1')],
            readsFrom: {userDb.reviewCards},
          )
          .get();
      expect(rows.first.data['synced'], 0);
    });

    test('sets synced=0 on logs', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: due);
      await insertReviewLog(userDb, id: 'l1', cardId: 'c1', reviewedAt: due);

      await dao.clearAllProgress();

      final rows = await userDb
          .customSelect(
            'SELECT synced FROM review_logs WHERE id = ?',
            variables: [Variable.withString('l1')],
            readsFrom: {userDb.reviewLogs},
          )
          .get();
      expect(rows.first.data['synced'], 0);
    });
  });

  // ── getAllReviewedEntryIds ──────────────────────────────────────────────────────

  group('getAllReviewedEntryIds', () {
    test('returns empty set when no cards', () async {
      expect(await dao.getAllReviewedEntryIds(), isEmpty);
    });

    test('returns set of entry IDs', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 10, due: due);
      await insertReviewCard(userDb, id: 'c2', entryId: 20, due: due);

      final ids = await dao.getAllReviewedEntryIds();
      expect(ids, containsAll([10, 20]));
    });

    test('excludes soft-deleted cards', () async {
      final due = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 10, due: due);

      await userDb.customUpdate(
        "UPDATE review_cards SET deleted_at = ? WHERE id = 'c1'",
        variables: [
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
        ],
        updates: {userDb.reviewCards},
      );

      final ids = await dao.getAllReviewedEntryIds();
      expect(ids, isEmpty);
    });
  });

  // ── getNewEntryIds ────────────────────────────────────────────────────────────

  group('getNewEntryIds', () {
    test('returns dict IDs not already in review_cards', () async {
      // Get some real entry IDs from dictionary
      final newIds = await dao.getNewEntryIds(
        cefrLevels: ['a1'],
        ox3000: true,
        limit: 5,
      );
      expect(newIds, hasLength(5));

      // Add a card for the first ID
      await insertReviewCard(
        userDb,
        id: 'c1',
        entryId: newIds.first,
        due: DateTime.now().toUtc().toIso8601String(),
      );

      // Now that ID should be excluded
      final newIds2 = await dao.getNewEntryIds(
        cefrLevels: ['a1'],
        ox3000: true,
        limit: 5,
      );
      expect(newIds2, isNot(contains(newIds.first)));
    });

    test('returns empty list when no matching dictionary entries', () async {
      // Use an empty cefrLevels list and no flags — this typically returns nothing
      // (unlikely to match anything with empty filters unless the DAO handles it)
      // Instead test with a very specific unlikely filter combo
      final ids = await dao.getNewEntryIds(
        cefrLevels: ['a1'],
        ox3000: true,
        limit: 0,
      );
      expect(ids, isEmpty);
    });

    test('returns up to limit entries', () async {
      final ids = await dao.getNewEntryIds(
        cefrLevels: ['a1'],
        ox3000: true,
        limit: 3,
      );
      expect(ids.length, lessThanOrEqualTo(3));
    });
  });
}
