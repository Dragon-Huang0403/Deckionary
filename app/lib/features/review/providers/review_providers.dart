import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/sync/sync_provider.dart';
import '../domain/review_filter.dart';
import '../domain/review_service.dart';
import '../domain/review_session.dart';

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

final reviewSummaryProvider = FutureProvider<ReviewSummary>((ref) async {
  final dao = ref.read(reviewDaoProvider);
  final settingsDao = ref.read(settingsDaoProvider);
  final filter = await ref.watch(reviewFilterProvider.future);

  final results = await Future.wait<int>([
    dao.countDueCards(),
    dao.countReviewedToday(),
    dao.countTotalCards(),
    settingsDao.getNewCardsPerDay(),
  ]);

  final dueCount = results[0];
  final reviewedToday = results[1];
  final totalCards = results[2];
  final newCardsPerDay = results[3];

  // Count available new cards
  int newAvailable = 0;
  if (!filter.isEmpty) {
    final newLearnedToday = await dao.countNewLearnedToday();
    final remaining = (newCardsPerDay - newLearnedToday).clamp(
      0,
      newCardsPerDay,
    );
    if (remaining > 0) {
      final newIds = await dao.getNewEntryIds(
        cefrLevels: filter.cefrLevels.toList(),
        ox3000: filter.ox3000,
        ox5000: filter.ox5000,
        limit: remaining,
      );
      newAvailable = newIds.length;
    }
  }

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
    final filter = await ref.read(reviewFilterProvider.future);

    final newCardsPerDay = await settingsDao.getNewCardsPerDay();
    final maxReviewsPerDay = await settingsDao.getMaxReviewsPerDay();
    final cardOrder = await settingsDao.getReviewCardOrder();

    final syncService = ref.read(syncServiceProvider);
    final session = ReviewSession(
      dao: dao,
      service: service,
      settingsDao: settingsDao,
      syncService: syncService,
    );
    await session.loadQueue(
      filter: filter,
      newCardsPerDay: newCardsPerDay,
      maxReviewsPerDay: maxReviewsPerDay,
      cardOrder: cardOrder,
      randomOrder: cardOrder == 'random',
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
    state = const AsyncData(null);
    // Refresh summary counts
    ref.invalidate(reviewSummaryProvider);
  }
}
