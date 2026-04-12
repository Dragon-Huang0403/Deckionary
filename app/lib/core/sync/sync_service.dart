import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import 'search_history_sync.dart';
import 'review_sync.dart';
import 'settings_sync.dart';

class SyncService {
  final SearchHistorySync _searchHistorySync;
  final ReviewSync _reviewSync;
  final SettingsSync _settingsSync;

  SyncService({required UserDatabase db, required SupabaseClient supabase})
    : _searchHistorySync = SearchHistorySync(
        db: db,
        supabase: supabase,
        getUserId: () => supabase.auth.currentUser?.id,
      ),
      _reviewSync = ReviewSync(
        db: db,
        supabase: supabase,
        getUserId: () => supabase.auth.currentUser?.id,
      ),
      _settingsSync = SettingsSync(
        db: db,
        supabase: supabase,
        getUserId: () => supabase.auth.currentUser?.id,
      );

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

  Future<void> clearRemoteReviewData() => _reviewSync.clearRemoteReviewData();

  // ── Settings ────────────────────────────────────────────────────────────

  Future<void> pushSetting(String key, String value) =>
      _settingsSync.pushSetting(key, value);

  Future<void> pushDirtySettings() => _settingsSync.pushDirtySettings();

  Future<int> pullSettings() => _settingsSync.pullSettings();

  Future<int> pushAllSettings() => _settingsSync.pushAllSettings();
}
