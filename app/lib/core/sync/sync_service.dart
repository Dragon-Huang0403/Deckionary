import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import 'search_history_sync.dart';
import 'review_sync.dart';
import 'settings_sync.dart';
import 'table_sync.dart';

class SyncService {
  final UserDatabase _db;
  final TableSync _tableSync;
  final SearchHistorySync _searchHistorySync;
  final ReviewSync _reviewSync;
  final SettingsSync _settingsSync;

  factory SyncService({
    required UserDatabase db,
    required SupabaseClient supabase,
  }) {
    String? getUserId() => supabase.auth.currentUser?.id;
    final tableSync = TableSync(
      db: db,
      supabase: supabase,
      getUserId: getUserId,
    );
    return SyncService._(
      db: db,
      tableSync: tableSync,
      searchHistorySync: SearchHistorySync(
        db: db,
        supabase: supabase,
        getUserId: getUserId,
        tableSync: tableSync,
      ),
      reviewSync: ReviewSync(
        db: db,
        supabase: supabase,
        getUserId: getUserId,
        tableSync: tableSync,
      ),
      settingsSync: SettingsSync(
        db: db,
        supabase: supabase,
        getUserId: getUserId,
        tableSync: tableSync,
      ),
    );
  }

  SyncService._({
    required UserDatabase db,
    required TableSync tableSync,
    required SearchHistorySync searchHistorySync,
    required ReviewSync reviewSync,
    required SettingsSync settingsSync,
  }) : _db = db,
       _tableSync = tableSync,
       _searchHistorySync = searchHistorySync,
       _reviewSync = reviewSync,
       _settingsSync = settingsSync;

  // ── Search History ──────────────────────────────────────────────────────

  Future<void> pushLatestSearch() => _searchHistorySync.pushLatestSearch();

  Future<int> pushAllUnsynced() => _searchHistorySync.pushAllUnsynced();

  Future<int> pullSearchHistory() => _searchHistorySync.pullSearchHistory();

  Future<({int pushed, int pulled})> syncSearchHistory() =>
      _searchHistorySync.syncSearchHistory();

  // ── Review ──────────────────────────────────────────────────────────────

  Future<void> pushLatestReviewCard(String cardId) =>
      _reviewSync.pushLatestReviewCard(cardId);

  Future<void> pushLatestReviewLog(String logId) =>
      _reviewSync.pushLatestReviewLog(logId);

  Future<void> syncReviewData() => _reviewSync.syncReviewData();

  // ── Settings ────────────────────────────────────────────────────────────

  Future<void> pushSetting(String key, String value) =>
      _settingsSync.pushSetting(key, value);

  Future<void> pushDirtySettings() => _settingsSync.pushDirtySettings();

  Future<int> pullSettings() => _settingsSync.pullSettings();

  Future<int> pushAllSettings() => _settingsSync.pushAllSettings();

  // ── Full Sync & Recovery ────────────────────────────────────────────────

  /// Clear all watermarks and re-sync everything from scratch.
  Future<void> forceFullSync() async {
    await _tableSync.clearAllWatermarks();
    await _settingsSync.pullSettings();
    await _settingsSync.pushDirtySettings();
    await _reviewSync.syncReviewData();
    await _searchHistorySync.syncSearchHistory();
  }

  /// Auto-clear watermarks on first run after a sync bug fix.
  /// Bump [_currentSyncVersion] whenever a fix requires full resync.
  Future<void> init() async {
    const currentSyncVersion = 1;

    final stored = await _db
        .customSelect(
          "SELECT value FROM sync_meta WHERE key = 'sync_code_version'",
          readsFrom: {_db.syncMeta},
        )
        .get();
    final storedVersion =
        stored.isEmpty
            ? 0
            : int.tryParse(stored.first.data['value'] as String) ?? 0;

    if (storedVersion < currentSyncVersion) {
      await _tableSync.clearAllWatermarks();
      await _db
          .into(_db.syncMeta)
          .insertOnConflictUpdate(
            SyncMetaCompanion.insert(
              key: 'sync_code_version',
              value: currentSyncVersion.toString(),
            ),
          );
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────

  Future<void> cleanupSoftDeletes({int retentionDays = 30}) async {
    await _searchHistorySync.cleanupSoftDeletes(retentionDays: retentionDays);
    await _reviewSync.cleanupSoftDeletes(retentionDays: retentionDays);
  }
}
