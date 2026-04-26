import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/logging/logging_service.dart';
import '../../../core/sync/sync_provider.dart';
import '../domain/review_filter.dart';
import '../domain/review_service.dart';
import '../domain/review_session.dart';
import 'my_words_providers.dart';

/// FSRS review service (singleton, uses default scheduler params).
final reviewServiceProvider = Provider<ReviewService>((ref) {
  return ReviewService();
});

/// The user's active study filter, loaded from settings.
final reviewFilterProvider =
    AsyncNotifierProvider<ReviewFilterNotifier, ReviewFilter>(
      ReviewFilterNotifier.new,
    );

class ReviewFilterNotifier extends AsyncNotifier<ReviewFilter> {
  @override
  Future<ReviewFilter> build() async {
    final dao = ref.read(settingsDaoProvider);
    final json = await dao.getReviewFilter();
    if (json == null) return const ReviewFilter();
    return ReviewFilter.fromJson(json);
  }

  Future<void> setFilter(ReviewFilter filter) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setReviewFilter(filter.toJson());
    await dao.clearNewCardsQueue();
    state = AsyncData(filter);
  }
}

/// Summary counts for the review home screen.
class ReviewSummary {
  final int dueCount;
  final int newAvailable;
  final int reviewedToday;
  final int totalCards;

  const ReviewSummary({
    this.dueCount = 0,
    this.newAvailable = 0,
    this.reviewedToday = 0,
    this.totalCards = 0,
  });
}

// Per-count stream providers wired to drift's table watchers.
// When review_cards or review_logs change locally (including via sync pull),
// drift notifies; the dependent reviewSummaryProvider re-evaluates without
// needing a manual ref.invalidate.
final _dueCountStreamProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.read(reviewDaoProvider).watchDueCount();
});

final _reviewedTodayStreamProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.read(reviewDaoProvider).watchReviewedTodayCount();
});

final _newLearnedTodayStreamProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.read(reviewDaoProvider).watchNewLearnedTodayCount();
});

final _totalCardsStreamProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.read(reviewDaoProvider).watchTotalCardsCount();
});

final reviewSummaryProvider = FutureProvider<ReviewSummary>((ref) async {
  final dao = ref.read(reviewDaoProvider);
  final vocabDao = ref.read(vocabularyListDaoProvider);
  final settingsDao = ref.read(settingsDaoProvider);
  final filter = await ref.watch(reviewFilterProvider.future);

  // Reactive triggers — re-run whenever any underlying count changes.
  final dueCount = await ref.watch(_dueCountStreamProvider.future);
  final reviewedToday = await ref.watch(_reviewedTodayStreamProvider.future);
  final newLearnedToday = await ref.watch(
    _newLearnedTodayStreamProvider.future,
  );
  final totalCards = await ref.watch(_totalCardsStreamProvider.future);
  final newCardsPerDay = await settingsDao.getNewCardsPerDay();

  // Count available new cards (My Words + filter).
  int newAvailable = 0;
  var myWordsCount = 0;
  var filterCount = 0;
  final remaining = (newCardsPerDay - newLearnedToday).clamp(0, newCardsPerDay);
  if (remaining > 0) {
    // My Words first
    final myWordsList = await ref.read(myWordsListProvider.future);
    final myWordsIds = await vocabDao.getNewEntryIds(
      listId: myWordsList.id,
      limit: remaining,
      excludeIds: {},
    );
    myWordsCount = myWordsIds.length;
    newAvailable += myWordsIds.length;

    // Filter fills remaining
    final filterRemaining = remaining - myWordsIds.length;
    if (filterRemaining > 0 && !filter.isEmpty) {
      final filterIds = await dao.getNewEntryIds(
        cefrLevels: filter.cefrLevels.toList(),
        ox3000: filter.ox3000,
        ox5000: filter.ox5000,
        limit: filterRemaining,
      );
      // Exclude overlaps with My Words
      final myWordsSet = myWordsIds.toSet();
      filterCount = filterIds.where((id) => !myWordsSet.contains(id)).length;
      newAvailable += filterCount;
    }
  }
  globalTalker.info(
    '[Diagnose] summary: dueCount=$dueCount reviewedToday=$reviewedToday '
    'newLearnedToday=$newLearnedToday newCardsPerDay=$newCardsPerDay '
    'remaining=$remaining myWordsCount=$myWordsCount '
    'filterCount=$filterCount newAvailable=$newAvailable',
  );

  return ReviewSummary(
    dueCount: dueCount,
    newAvailable: newAvailable,
    reviewedToday: reviewedToday,
    totalCards: totalCards,
  );
});

/// Active review session state.
final reviewSessionProvider =
    AsyncNotifierProvider<ReviewSessionNotifier, ReviewSession?>(
      ReviewSessionNotifier.new,
    );

class ReviewSessionNotifier extends AsyncNotifier<ReviewSession?> {
  @override
  Future<ReviewSession?> build() async => null;

  /// Start a new review session.
  Future<ReviewSession> startSession() async {
    final dao = ref.read(reviewDaoProvider);
    final service = ref.read(reviewServiceProvider);
    final settingsDao = ref.read(settingsDaoProvider);
    final vocabDao = ref.read(vocabularyListDaoProvider);
    final filter = await ref.read(reviewFilterProvider.future);

    final newCardsPerDay = await settingsDao.getNewCardsPerDay();
    final maxReviewsPerDay = await settingsDao.getMaxReviewsPerDay();
    final cardOrder = await settingsDao.getReviewCardOrder();
    final myWordsOrder = await settingsDao.getMyWordsOrder();

    // Get My Words list ID if it exists (don't create on session start)
    final myWordsList = await ref.read(myWordsListProvider.future);

    final syncService = ref.read(syncServiceProvider);
    final session = ReviewSession(
      dao: dao,
      service: service,
      settingsDao: settingsDao,
      syncService: syncService,
      vocabDao: vocabDao,
    );
    await session.loadQueue(
      filter: filter,
      newCardsPerDay: newCardsPerDay,
      maxReviewsPerDay: maxReviewsPerDay,
      cardOrder: cardOrder,
      randomOrder: cardOrder == 'random',
      myWordsListId: myWordsList.id,
      myWordsOrder: myWordsOrder,
    );

    state = AsyncData(session);
    return session;
  }

  /// End the current session.
  void endSession() {
    final session = state.value;
    if (session != null && session.isComplete) {
      ref.read(settingsDaoProvider).clearNewCardsQueue();
    }
    // Diagnostic: log residual due count after session ends — if user
    // started with N dues and finished, but more dues remain, capture it.
    if (session != null) {
      final dao = ref.read(reviewDaoProvider);
      // Fire-and-forget; we don't want to block endSession on this.
      Future(() async {
        final residualDue = await dao.countDueCards();
        globalTalker.info(
          '[Diagnose] endSession: queue.length=${session.total} '
          'currentIndex=${session.currentIndex} '
          'isComplete=${session.isComplete} '
          'reviewed=${session.stats.reviewed} '
          'newLearned=${session.stats.newLearned} '
          'againCount=${session.stats.againCount} '
          'residualDueAfter=$residualDue',
        );
      });
    }
    state = const AsyncData(null);
    // No manual invalidate: reviewSummaryProvider watches review_cards/logs
    // via drift streams, so it already re-emitted as cards were rated.
  }
}
