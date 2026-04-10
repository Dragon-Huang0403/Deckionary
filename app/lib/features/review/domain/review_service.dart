import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:uuid/uuid.dart';
import '../../../core/database/app_database.dart';

const _uuid = Uuid();

/// Bridges between the FSRS scheduler and our Drift database types.
class ReviewService {
  final fsrs.Scheduler scheduler;

  ReviewService({fsrs.Scheduler? scheduler})
      : scheduler = scheduler ?? fsrs.Scheduler();

  /// Convert a DB ReviewCard row to an FSRS Card for scheduling.
  fsrs.Card toFsrsCard(ReviewCard dbCard) {
    return fsrs.Card(
      cardId: dbCard.entryId,
      state: dbCard.state == 0
          ? fsrs.State.learning
          : fsrs.State.fromValue(dbCard.state),
      step: dbCard.step,
      stability: dbCard.stability == 0 ? null : dbCard.stability,
      difficulty: dbCard.difficulty == 0 ? null : dbCard.difficulty,
      due: DateTime.parse(dbCard.due).toUtc(),
      lastReview:
          dbCard.lastReview != null ? DateTime.parse(dbCard.lastReview!) : null,
    );
  }

  /// Create a new FSRS Card for a never-seen entry.
  fsrs.Card newFsrsCard(int entryId) {
    return fsrs.Card(
      cardId: entryId,
      state: fsrs.State.learning,
      step: 0,
    );
  }

  /// Review a card and return updated DB companions for both card and log.
  ({ReviewCardsCompanion card, ReviewLogsCompanion log}) reviewCard({
    required ReviewCard dbCard,
    required fsrs.Rating rating,
    int? reviewDurationMs,
  }) {
    final fsrsCard = toFsrsCard(dbCard);
    final now = DateTime.now().toUtc();
    final result = scheduler.reviewCard(fsrsCard, rating, reviewDateTime: now, reviewDuration: reviewDurationMs);

    final updatedCard = ReviewCardsCompanion(
      id: Value(dbCard.id),
      entryId: Value(dbCard.entryId),
      headword: Value(dbCard.headword),
      pos: Value(dbCard.pos),
      due: Value(result.card.due.toIso8601String()),
      stability: Value(result.card.stability ?? 0),
      difficulty: Value(result.card.difficulty ?? 0),
      state: Value(result.card.state.value),
      step: Value(result.card.step),
      lastReview: Value(result.card.lastReview?.toIso8601String()),
      updatedAt: Value(now.toIso8601String()),
    );

    final log = ReviewLogsCompanion.insert(
      id: _uuid.v4(),
      cardId: dbCard.id,
      rating: rating.value,
      state: result.card.state.value,
      due: result.card.due.toIso8601String(),
      stability: result.card.stability ?? 0,
      difficulty: result.card.difficulty ?? 0,
      elapsedDays: result.card.lastReview != null
          ? now.difference(result.card.lastReview!).inDays
          : 0,
      scheduledDays: result.card.due.difference(now).inDays,
      reviewDuration: Value(reviewDurationMs),
    );

    return (card: updatedCard, log: log);
  }

  /// Review a brand-new card (no existing DB row) and return companions.
  ({ReviewCardsCompanion card, ReviewLogsCompanion log}) reviewNewCard({
    required int entryId,
    required String headword,
    required String pos,
    required fsrs.Rating rating,
  }) {
    final fsrsCard = newFsrsCard(entryId);
    final now = DateTime.now().toUtc();
    final cardId = _uuid.v4();
    final result = scheduler.reviewCard(fsrsCard, rating, reviewDateTime: now);

    final card = ReviewCardsCompanion.insert(
      id: cardId,
      entryId: entryId,
      headword: headword,
      pos: Value(pos),
      due: result.card.due.toIso8601String(),
      stability: Value(result.card.stability ?? 0),
      difficulty: Value(result.card.difficulty ?? 0),
      state: Value(result.card.state.value),
      step: Value(result.card.step),
      lastReview: Value(result.card.lastReview?.toIso8601String()),
    );

    final log = ReviewLogsCompanion.insert(
      id: _uuid.v4(),
      cardId: cardId,
      rating: rating.value,
      state: result.card.state.value,
      due: result.card.due.toIso8601String(),
      stability: result.card.stability ?? 0,
      difficulty: result.card.difficulty ?? 0,
      elapsedDays: 0,
      scheduledDays: result.card.due.difference(now).inDays,
    );

    return (card: card, log: log);
  }

  /// Preview what intervals each rating would give for a card.
  /// Returns map of Rating -> human-readable string ("1m", "10m", "1d").
  Map<fsrs.Rating, String> previewIntervals(ReviewCard? dbCard, {int? entryId}) {
    final fsrsCard = dbCard != null ? toFsrsCard(dbCard) : newFsrsCard(entryId ?? 0);
    final now = DateTime.now().toUtc();
    final result = <fsrs.Rating, String>{};

    for (final rating in fsrs.Rating.values) {
      final reviewed = scheduler.reviewCard(fsrsCard, rating, reviewDateTime: now);
      final interval = reviewed.card.due.difference(now);
      result[rating] = _formatInterval(interval);
    }
    return result;
  }

  static String _formatInterval(Duration d) {
    if (d.inDays > 30) return '${(d.inDays / 30).round()}mo';
    if (d.inDays > 0) return '${d.inDays}d';
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '<1m';
  }
}
