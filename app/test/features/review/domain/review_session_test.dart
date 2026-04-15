import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/core/database/review_dao.dart';
import 'package:deckionary/core/database/settings_dao.dart';
import 'package:deckionary/features/review/domain/review_filter.dart';
import 'package:deckionary/features/review/domain/review_service.dart';
import 'package:deckionary/features/review/domain/review_session.dart';
import '../../../test_helpers.dart';

void main() {
  late DictionaryDatabase dictDb;

  setUpAll(() {
    dictDb = createTestDictDb();
  });

  tearDownAll(() async {
    await dictDb.close();
  });

  // Shared per-test setup
  late UserDatabase userDb;
  late ReviewDao dao;
  late SettingsDao settingsDao;
  late ReviewService service;
  late ReviewSession session;

  setUp(() {
    userDb = createTestUserDb();
    dao = ReviewDao(db: userDb, dictDb: dictDb);
    settingsDao = SettingsDao(userDb);
    service = ReviewService();
    session = ReviewSession(
      dao: dao,
      service: service,
      settingsDao: settingsDao,
    );
  });

  tearDown(() async {
    await userDb.close();
  });

  const defaultFilter = ReviewFilter(cefrLevels: {'a1'}, ox3000: true);

  // ── Initial state ─────────────────────────────────────────────────────────

  group('initial state', () {
    test('isLoaded is false before loadQueue', () {
      expect(session.isLoaded, false);
    });

    test('isEmpty is true before loadQueue', () {
      expect(session.isEmpty, true);
    });

    test('currentCard is null before loadQueue', () {
      expect(session.currentCard, isNull);
    });

    test('isComplete is true when queue is empty', () {
      // currentIndex(0) >= queue.length(0)
      expect(session.isComplete, true);
    });
  });

  // ── loadQueue with due cards ──────────────────────────────────────────────

  group('loadQueue with due cards', () {
    test('loads due cards ordered by due date', () async {
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
      await insertReviewCard(userDb, id: 'c3', entryId: 3, headword: 'cat', due: latest);
      await insertReviewCard(userDb, id: 'c1', entryId: 1, headword: 'apple', due: earliest);
      await insertReviewCard(userDb, id: 'c2', entryId: 2, headword: 'ball', due: middle);

      await session.loadQueue(
        filter: const ReviewFilter(), // empty filter — no new cards
        newCardsPerDay: 0,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.isLoaded, true);
      expect(session.total, 3);
      expect(session.currentCard!.headword, 'apple');
    });

    test('due cards are not marked as new', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: pastDue);

      await session.loadQueue(
        filter: const ReviewFilter(),
        newCardsPerDay: 0,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.currentCard!.isNew, false);
      expect(session.currentCard!.dbCard, isNotNull);
    });
  });

  // ── loadQueue with new cards ──────────────────────────────────────────────

  group('loadQueue with new cards', () {
    test('loads new cards from dictionary when filter is non-empty', () async {
      await session.loadQueue(
        filter: defaultFilter,
        newCardsPerDay: 5,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.isLoaded, true);
      expect(session.total, 5);
      // New cards should be marked as new with no dbCard
      expect(session.currentCard!.isNew, true);
      expect(session.currentCard!.dbCard, isNull);
    });

    test('new cards appear after due cards', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(
        userDb,
        id: 'c1',
        entryId: 1,
        headword: 'due-card',
        due: pastDue,
      );

      await session.loadQueue(
        filter: defaultFilter,
        newCardsPerDay: 3,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      // First card should be the due card
      expect(session.currentCard!.isNew, false);
      expect(session.currentCard!.headword, 'due-card');
      // Total should be due(1) + new(3) = 4
      expect(session.total, 4);
    });
  });

  // ── loadQueue new card limit ──────────────────────────────────────────────

  group('loadQueue new card limit', () {
    test('reduces new card count by newLearnedToday', () async {
      // First, create a card and a review log from today so countNewLearnedToday > 0
      final now = DateTime.now().toUtc().toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 99999, due: now);
      await insertReviewLog(userDb, id: 'l1', cardId: 'c1', reviewedAt: now);

      // newLearnedToday = 1, so newLimit = (5 - 1).clamp(0, 5) = 4
      await session.loadQueue(
        filter: defaultFilter,
        newCardsPerDay: 5,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      // The due card (c1) counts as 1, new cards should be 4
      // Total = 1 due + 4 new = 5
      expect(session.total, 5);
    });

    test('zero new cards when newLearnedToday >= newCardsPerDay', () async {
      // Create enough review logs today to exhaust the limit
      final now = DateTime.now().toUtc().toIso8601String();
      for (var i = 0; i < 3; i++) {
        await insertReviewCard(
          userDb,
          id: 'c$i',
          entryId: 90000 + i,
          due: now,
        );
        await insertReviewLog(
          userDb,
          id: 'l$i',
          cardId: 'c$i',
          reviewedAt: now,
        );
      }

      // newLearnedToday = 3, newCardsPerDay = 3 => newLimit = 0
      await session.loadQueue(
        filter: defaultFilter,
        newCardsPerDay: 3,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      // Only the 3 due cards, no new cards
      expect(session.total, 3);
      expect(session.currentCard!.isNew, false);
    });
  });

  // ── loadQueue empty filter skips new cards ────────────────────────────────

  group('loadQueue empty filter skips new cards', () {
    test('empty ReviewFilter loads only due cards, no new cards', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(userDb, id: 'c1', entryId: 1, due: pastDue);

      await session.loadQueue(
        filter: const ReviewFilter(), // empty
        newCardsPerDay: 20,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.total, 1); // only the due card
      expect(session.currentCard!.isNew, false);
    });

    test('empty filter with no due cards results in empty queue', () async {
      await session.loadQueue(
        filter: const ReviewFilter(),
        newCardsPerDay: 20,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.isEmpty, true);
      expect(session.isComplete, true);
    });
  });

  // ── rateCurrentCard ───────────────────────────────────────────────────────

  group('rateCurrentCard', () {
    test('rating a due card increments reviewed and advances index', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      final lastReview = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 10))
          .toIso8601String();
      await insertReviewCard(
        userDb,
        id: 'c1',
        entryId: 1,
        headword: 'test',
        due: pastDue,
        // Use state=2 (review) with valid stability/difficulty so FSRS works
        state: 2,
        stability: 10.0,
        difficulty: 5.0,
        lastReview: lastReview,
      );

      await session.loadQueue(
        filter: const ReviewFilter(),
        newCardsPerDay: 0,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.currentIndex, 0);
      expect(session.stats.reviewed, 0);

      await session.rateCurrentCard(fsrs.Rating.good);

      expect(session.stats.reviewed, 1);
      expect(session.currentIndex, 1);
    });

    test('rating does nothing when no current card', () async {
      await session.loadQueue(
        filter: const ReviewFilter(),
        newCardsPerDay: 0,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      // No cards loaded, should be a no-op
      await session.rateCurrentCard(fsrs.Rating.good);
      expect(session.stats.reviewed, 0);
    });
  });

  // ── rateCurrentCard new card ──────────────────────────────────────────────

  group('rateCurrentCard new card', () {
    test('rating a new card increments newLearned and persists to DB',
        () async {
      await session.loadQueue(
        filter: defaultFilter,
        newCardsPerDay: 1,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.total, greaterThanOrEqualTo(1));
      final card = session.currentCard!;
      expect(card.isNew, true);
      expect(card.dbCard, isNull);

      await session.rateCurrentCard(fsrs.Rating.good);

      expect(session.stats.newLearned, 1);
      expect(session.stats.reviewed, 1);

      // Verify the card was persisted to DB
      final persisted = await dao.getCardByEntryId(card.entryId);
      expect(persisted, isNotNull);
      expect(persisted!.headword, card.headword);
    });
  });

  // ── rateCurrentCard again ─────────────────────────────────────────────────

  group('rateCurrentCard again', () {
    test('rating with again increments againCount', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      await insertReviewCard(
        userDb,
        id: 'c1',
        entryId: 1,
        headword: 'test',
        due: pastDue,
      );

      await session.loadQueue(
        filter: const ReviewFilter(),
        newCardsPerDay: 0,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      await session.rateCurrentCard(fsrs.Rating.again);

      expect(session.stats.againCount, 1);
      expect(session.stats.reviewed, 1);
    });

    test('rating with good does not increment againCount', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      final lastReview = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 10))
          .toIso8601String();
      await insertReviewCard(
        userDb,
        id: 'c1',
        entryId: 1,
        headword: 'test',
        due: pastDue,
        state: 2,
        stability: 10.0,
        difficulty: 5.0,
        lastReview: lastReview,
      );

      await session.loadQueue(
        filter: const ReviewFilter(),
        newCardsPerDay: 0,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      await session.rateCurrentCard(fsrs.Rating.good);

      expect(session.stats.againCount, 0);
    });
  });

  // ── isComplete ────────────────────────────────────────────────────────────

  group('isComplete', () {
    test('is true after rating all cards', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      final lastReview = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 10))
          .toIso8601String();
      // Use state=2 (review) so cards won't be re-queued after rating
      await insertReviewCard(
        userDb,
        id: 'c1',
        entryId: 1,
        headword: 'alpha',
        due: pastDue,
        state: 2,
        stability: 10.0,
        difficulty: 5.0,
        lastReview: lastReview,
      );
      await insertReviewCard(
        userDb,
        id: 'c2',
        entryId: 2,
        headword: 'bravo',
        due: pastDue,
        state: 2,
        stability: 10.0,
        difficulty: 5.0,
        lastReview: lastReview,
      );

      await session.loadQueue(
        filter: const ReviewFilter(),
        newCardsPerDay: 0,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.isComplete, false);
      expect(session.remaining, 2);

      await session.rateCurrentCard(fsrs.Rating.good);
      expect(session.isComplete, false);
      expect(session.remaining, 1);

      await session.rateCurrentCard(fsrs.Rating.good);
      expect(session.isComplete, true);
      expect(session.remaining, 0);
      expect(session.currentCard, isNull);
    });

    test('re-queued cards extend the session', () async {
      final pastDue = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      // state=0 (learning) step=0: rating with Again should produce a
      // short due (<20 min) and stay in learning, causing re-queue.
      await insertReviewCard(
        userDb,
        id: 'c1',
        entryId: 1,
        headword: 'test',
        due: pastDue,
        state: 0,
        step: 0,
      );

      await session.loadQueue(
        filter: const ReviewFilter(),
        newCardsPerDay: 0,
        maxReviewsPerDay: 200,
        cardOrder: 'alphabetical',
      );

      expect(session.total, 1);

      // Rating "again" on a learning card should re-queue it
      await session.rateCurrentCard(fsrs.Rating.again);

      // The card should have been re-added to the queue
      expect(session.total, greaterThan(1));
      expect(session.isComplete, false);
    });
  });
}
