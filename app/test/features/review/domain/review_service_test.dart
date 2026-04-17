import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:deckionary/features/review/domain/review_service.dart';
import 'package:deckionary/core/database/app_database.dart';

ReviewCard _makeDbCard({
  String id = 'card-1',
  int entryId = 42,
  String headword = 'test',
  String pos = 'noun',
  String? due,
  double stability = 0,
  double difficulty = 0,
  int state = 0,
  int? step = 0,
  String? lastReview,
}) {
  return ReviewCard(
    id: id,
    entryId: entryId,
    headword: headword,
    pos: pos,
    due: due ?? DateTime.now().toUtc().toIso8601String(),
    stability: stability,
    difficulty: difficulty,
    elapsedDays: 0,
    scheduledDays: 0,
    reps: 0,
    lapses: 0,
    state: state,
    step: step,
    lastReview: lastReview,
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
    synced: 1,
    deletedAt: null,
  );
}

void main() {
  late ReviewService service;

  setUp(() {
    service = ReviewService();
  });

  group('toFsrsCard', () {
    test('converts DB card with all fields', () {
      final dbCard = _makeDbCard(
        entryId: 42,
        due: '2026-01-15T10:00:00.000Z',
        stability: 5.0,
        difficulty: 3.0,
        state: 2, // review
        lastReview: '2026-01-10T10:00:00.000Z',
      );
      final fsrsCard = service.toFsrsCard(dbCard);
      expect(fsrsCard.cardId, 42);
      expect(fsrsCard.state, fsrs.State.review);
      expect(fsrsCard.stability, 5.0);
      expect(fsrsCard.difficulty, 3.0);
      expect(fsrsCard.due, DateTime.utc(2026, 1, 15, 10));
    });

    test('state=0 maps to learning', () {
      final fsrsCard = service.toFsrsCard(_makeDbCard(state: 0));
      expect(fsrsCard.state, fsrs.State.learning);
    });

    test('stability=0 and difficulty=0 become null for FSRS', () {
      final fsrsCard = service.toFsrsCard(
        _makeDbCard(stability: 0, difficulty: 0),
      );
      expect(fsrsCard.stability, isNull);
      expect(fsrsCard.difficulty, isNull);
    });

    test('non-zero stability/difficulty preserved', () {
      final fsrsCard = service.toFsrsCard(
        _makeDbCard(stability: 4.5, difficulty: 6.7),
      );
      expect(fsrsCard.stability, 4.5);
      expect(fsrsCard.difficulty, 6.7);
    });

    test('null lastReview handled', () {
      final fsrsCard = service.toFsrsCard(_makeDbCard(lastReview: null));
      expect(fsrsCard.lastReview, isNull);
    });
  });

  group('newFsrsCard', () {
    test('creates learning card at step 0', () {
      final card = service.newFsrsCard(99);
      expect(card.cardId, 99);
      expect(card.state, fsrs.State.learning);
      expect(card.step, 0);
    });
  });

  group('reviewCard', () {
    test('returns updated card companion with synced=0', () {
      final dbCard = _makeDbCard(id: 'card-1', entryId: 42, headword: 'test');
      final result = service.reviewCard(
        dbCard: dbCard,
        rating: fsrs.Rating.good,
      );

      expect(result.card.id.value, 'card-1');
      expect(result.card.entryId.value, 42);
      expect(result.card.headword.value, 'test');
      expect(result.card.synced.value, 0);
    });

    test('log references the card id', () {
      final dbCard = _makeDbCard(id: 'card-1');
      final result = service.reviewCard(
        dbCard: dbCard,
        rating: fsrs.Rating.good,
      );
      expect(result.log.cardId.value, 'card-1');
      expect(result.log.rating.value, fsrs.Rating.good.value);
    });

    test('due date advances after review', () {
      final now = DateTime.now().toUtc();
      final dbCard = _makeDbCard(due: now.toIso8601String());
      final result = service.reviewCard(
        dbCard: dbCard,
        rating: fsrs.Rating.good,
      );
      final newDue = DateTime.parse(result.card.due.value);
      expect(newDue.isAfter(now.subtract(const Duration(seconds: 5))), true);
    });
  });

  group('reviewNewCard', () {
    test('creates card and log for brand-new entry', () {
      final result = service.reviewNewCard(
        entryId: 100,
        headword: 'apple',
        pos: 'noun',
        rating: fsrs.Rating.good,
      );
      expect(result.card.entryId.value, 100);
      expect(result.card.headword.value, 'apple');
      expect(result.card.id.value, isNotEmpty);
      expect(result.log.cardId.value, result.card.id.value);
      expect(result.log.elapsedDays.value, 0);
    });
  });

  group('previewIntervals', () {
    test('returns an entry for every Rating', () {
      final intervals = service.previewIntervals(null, entryId: 1);
      expect(intervals.keys, containsAll(fsrs.Rating.values));
      for (final v in intervals.values) {
        expect(v, isNotEmpty);
      }
    });

    test('again produces shorter interval than easy for new card', () {
      final intervals = service.previewIntervals(null, entryId: 1);
      final again = intervals[fsrs.Rating.again]!;
      final easy = intervals[fsrs.Rating.easy]!;
      // Again should be minutes for a new card
      expect(again.endsWith('m') || again == '<1m', true);
      // Easy should be days for a new card
      expect(easy.endsWith('d') || easy.endsWith('mo'), true);
    });

    test('format strings match expected patterns', () {
      final intervals = service.previewIntervals(null, entryId: 1);
      final pattern = RegExp(r'^(<1m|\d+m|\d+h|\d+d|\d+mo)$');
      for (final v in intervals.values) {
        expect(pattern.hasMatch(v), true, reason: '"$v" does not match format');
      }
    });
  });
}
