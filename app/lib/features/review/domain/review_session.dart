import 'package:fsrs/fsrs.dart' as fsrs;
import '../../../core/database/app_database.dart';
import '../../../core/database/review_dao.dart';
import '../../../core/database/settings_dao.dart';
import '../../../core/sync/sync_service.dart';
import 'review_filter.dart';
import 'review_service.dart';

/// Stats tracked during a review session.
class SessionStats {
  int reviewed = 0;
  int newLearned = 0;
  int againCount = 0;
}

/// A card in the review queue — either an existing DB card or a new one.
class QueueCard {
  /// Non-null if this is an existing review card.
  ReviewCard? dbCard;

  /// Entry metadata for new cards (no DB row yet).
  final int entryId;
  final String headword;
  final String pos;

  /// Whether this is a brand-new card (first review ever).
  final bool isNew;

  QueueCard({
    this.dbCard,
    required this.entryId,
    required this.headword,
    required this.pos,
    required this.isNew,
  });
}

/// Manages the in-memory review queue for a single session.
class ReviewSession {
  final ReviewDao _dao;
  final ReviewService _service;
  final SyncService? _syncService;
  final SettingsDao _settingsDao;
  final List<QueueCard> _queue = [];
  int _currentIndex = 0;
  final SessionStats stats = SessionStats();
  bool _isLoaded = false;

  ReviewSession({
    required ReviewDao dao,
    required ReviewService service,
    required SettingsDao settingsDao,
    SyncService? syncService,
  }) : _dao = dao,
       _service = service,
       _settingsDao = settingsDao,
       _syncService = syncService;

  bool get isLoaded => _isLoaded;
  bool get isEmpty => _queue.isEmpty;
  bool get isComplete => _currentIndex >= _queue.length;
  int get remaining => _queue.length - _currentIndex;
  int get total => _queue.length;
  int get currentIndex => _currentIndex;

  QueueCard? get currentCard =>
      _currentIndex < _queue.length ? _queue[_currentIndex] : null;

  /// Load the review queue: due cards first, then new cards.
  Future<void> loadQueue({
    required ReviewFilter filter,
    required int newCardsPerDay,
    required int maxReviewsPerDay,
    required String cardOrder,
    bool randomOrder = false,
  }) async {
    _queue.clear();
    _currentIndex = 0;

    // 1. Due review cards
    final dueCards = await _dao.getDueCards(limit: maxReviewsPerDay);
    for (final card in dueCards) {
      _queue.add(
        QueueCard(
          dbCard: card,
          entryId: card.entryId,
          headword: card.headword,
          pos: card.pos,
          isNew: false,
        ),
      );
    }

    // 2. New cards (subtract already-learned-today from limit)
    final newLearnedToday = await _dao.countNewLearnedToday();
    final newLimit = (newCardsPerDay - newLearnedToday).clamp(
      0,
      newCardsPerDay,
    );

    if (newLimit > 0 && !filter.isEmpty) {
      final newIds = await _resolveNewCardIds(
        filter: filter,
        newCardsPerDay: newCardsPerDay,
        cardOrder: cardOrder,
        newLimit: newLimit,
        randomOrder: randomOrder,
      );

      if (newIds.isNotEmpty) {
        final entries = await _dao.getEntryDetails(newIds);
        for (final entry in entries) {
          _queue.add(
            QueueCard(
              entryId: entry['id'] as int,
              headword: entry['headword'] as String,
              pos: (entry['pos'] as String?) ?? '',
              isNew: true,
            ),
          );
        }
      }
    }

    _isLoaded = true;
  }

  /// Try to resume from persisted queue, otherwise generate fresh.
  Future<List<int>> _resolveNewCardIds({
    required ReviewFilter filter,
    required int newCardsPerDay,
    required String cardOrder,
    required int newLimit,
    required bool randomOrder,
  }) async {
    final currentHash = filter.queueHash(
      newCardsPerDay: newCardsPerDay,
      cardOrder: cardOrder,
    );

    // Try persisted queue
    final persisted = await _settingsDao.getNewCardsQueue();
    if (persisted != null && persisted['hash'] == currentHash) {
      final allIds = (persisted['ids'] as List).cast<int>();
      final position = persisted['position'] as int;
      var resumeIds = allIds.skip(position).take(newLimit).toList();

      // Remove IDs that have since been reviewed
      if (resumeIds.isNotEmpty) {
        final existing = await _dao.getAllReviewedEntryIds();
        resumeIds.removeWhere((id) => existing.contains(id));
      }

      if (resumeIds.isNotEmpty) return resumeIds;
    }

    // Generate fresh queue
    final newIds = await _dao.getNewEntryIds(
      cefrLevels: filter.cefrLevels.toList(),
      ox3000: filter.ox3000,
      ox5000: filter.ox5000,
      limit: newLimit,
      randomOrder: randomOrder,
    );

    // Persist for session resumption
    if (newIds.isNotEmpty) {
      await _settingsDao.setNewCardsQueue(newIds, 0, currentHash);
    }

    return newIds;
  }

  /// Advance the persisted queue position after a new card is reviewed.
  Future<void> _advanceQueuePosition() async {
    final persisted = await _settingsDao.getNewCardsQueue();
    if (persisted == null) return;
    final allIds = (persisted['ids'] as List).cast<int>();
    final position = (persisted['position'] as int) + 1;
    final hash = persisted['hash'] as String;
    await _settingsDao.setNewCardsQueue(allIds, position, hash);
  }

  /// Rate the current card and advance. Returns the updated/created ReviewCard.
  Future<void> rateCurrentCard(fsrs.Rating rating) async {
    final card = currentCard;
    if (card == null) return;

    if (card.isNew && card.dbCard == null) {
      // New card — first review ever
      final result = _service.reviewNewCard(
        entryId: card.entryId,
        headword: card.headword,
        pos: card.pos,
        rating: rating,
      );
      await _dao.upsertCard(result.card);
      await _dao.insertLog(result.log);
      // Fire-and-forget sync to Supabase
      _syncService?.pushLatestReviewCard(result.card.id.value);
      _syncService?.pushLatestReviewLog(result.log.id.value);
      stats.newLearned++;
      await _advanceQueuePosition();
    } else {
      // Existing card
      final result = _service.reviewCard(dbCard: card.dbCard!, rating: rating);
      await _dao.upsertCard(result.card);
      await _dao.insertLog(result.log);
      // Fire-and-forget sync to Supabase
      _syncService?.pushLatestReviewCard(result.card.id.value);
      _syncService?.pushLatestReviewLog(result.log.id.value);
    }

    stats.reviewed++;
    if (rating == fsrs.Rating.again) stats.againCount++;

    // Check if the card is still due within this session (learning/relearning steps).
    // If the card's new due time is within the next 20 minutes, re-queue it.
    // We do this by checking the FSRS result — if still in learning/relearning state,
    // add it back near the end of the queue.
    if (card.dbCard != null || card.isNew) {
      final fsrsCard = card.dbCard != null
          ? _service.toFsrsCard(card.dbCard!)
          : _service.newFsrsCard(card.entryId);
      final preview = _service.scheduler.reviewCard(fsrsCard, rating);
      final interval = preview.card.due.difference(DateTime.now().toUtc());

      if (interval.inMinutes < 20 && preview.card.state != fsrs.State.review) {
        // Re-fetch the updated card from DB and re-queue
        final updatedCard = await _dao.getCardByEntryId(card.entryId);
        if (updatedCard != null) {
          _queue.add(
            QueueCard(
              dbCard: updatedCard,
              entryId: card.entryId,
              headword: card.headword,
              pos: card.pos,
              isNew: false,
            ),
          );
        }
      }
    }

    _currentIndex++;
  }

  /// Preview intervals for the current card.
  Map<fsrs.Rating, String> previewCurrentIntervals() {
    final card = currentCard;
    if (card == null) return {};
    return _service.previewIntervals(card.dbCard, entryId: card.entryId);
  }
}
