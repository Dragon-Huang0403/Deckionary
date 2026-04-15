import 'dart:convert';
import 'package:drift/drift.dart';
import 'app_database.dart';

/// Callback to push a setting change to remote sync.
typedef SettingSyncCallback = void Function(String key, String value);

/// Data access for app settings
class SettingsDao {
  final UserDatabase _db;
  SettingSyncCallback? onSettingChanged;

  SettingsDao(this._db);

  Future<String?> get(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
    onSettingChanged?.call(key, value);
  }

  /// Fetch all settings in a single query. Returns {key: value}.
  Future<Map<String, String>> getAll() async {
    final rows = await _db.select(_db.settings).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<String> getDialect() async => await get('audio_dialect') ?? 'us';
  Future<void> setDialect(String dialect) => set('audio_dialect', dialect);

  /// Which pronunciations to display: 'both' (default), 'us', or 'gb'
  Future<String> getPronunciationDisplay() async =>
      await get('pronunciation_display') ?? 'both';
  Future<void> setPronunciationDisplay(String value) =>
      set('pronunciation_display', value);

  Future<bool> getAutoPronounce() async =>
      (await get('auto_pronounce')) != 'false';
  Future<void> setAutoPronounce(bool enabled) =>
      set('auto_pronounce', enabled.toString());

  Future<String> getThemeMode() async => await get('theme_mode') ?? 'system';
  Future<void> setThemeMode(String mode) => set('theme_mode', mode);

  // ── Review settings ─────────────────────────────────────────────────────

  Future<int> getNewCardsPerDay() async =>
      int.tryParse(await get('new_cards_per_day') ?? '') ?? 20;
  Future<void> setNewCardsPerDay(int count) =>
      set('new_cards_per_day', count.toString());

  Future<int> getMaxReviewsPerDay() async =>
      int.tryParse(await get('max_reviews_per_day') ?? '') ?? 200;
  Future<void> setMaxReviewsPerDay(int count) =>
      set('max_reviews_per_day', count.toString());

  /// Card order: 'random' (default) or 'alphabetical'
  Future<String> getReviewCardOrder() async =>
      await get('review_card_order') ?? 'random';
  Future<void> setReviewCardOrder(String order) =>
      set('review_card_order', order);

  /// Review auto-play mode: 'off', 'pronunciation' (default), 'sentence_pronunciation'
  /// Migrates from old bool 'review_auto_pronounce' on first read.
  Future<String> getReviewAutoPlayMode() async {
    final mode = await get('review_auto_play_mode');
    if (mode != null) return mode;
    // Migrate from old bool setting
    final oldVal = await get('review_auto_pronounce');
    if (oldVal == 'false') {
      await setReviewAutoPlayMode('off');
      return 'off';
    }
    return 'pronunciation';
  }

  Future<void> setReviewAutoPlayMode(String mode) =>
      set('review_auto_play_mode', mode);

  Future<String?> getReviewFilter() async => await get('review_filter');
  Future<void> setReviewFilter(String json) => set('review_filter', json);

  // ── Quick Search settings (macOS) ──────────────────────────────────────

  /// Stored as JSON: {"keyCode": 458759, "modifiers": ["meta", "shift"], "label": "D"}
  /// Default: Cmd+Shift+D
  static const defaultHotKey =
      '{"keyCode":458759,"modifiers":["meta","shift"],"label":"D"}';

  Future<String> getQuickSearchHotKey() async =>
      await get('quick_search_hotkey') ?? defaultHotKey;
  Future<void> setQuickSearchHotKey(String json) =>
      set('quick_search_hotkey', json);

  Future<bool> getShowTrayIcon() async =>
      (await get('show_tray_icon')) != 'false';
  Future<void> setShowTrayIcon(bool enabled) =>
      set('show_tray_icon', enabled.toString());

  Future<bool> getShowInDock() async => (await get('show_in_dock')) != 'false';
  Future<void> setShowInDock(bool enabled) =>
      set('show_in_dock', enabled.toString());

  /// Which screen to show the overlay on: 'mouse' (default), 'activeWindow', 'primaryScreen'
  Future<String> getShowOnScreen() async =>
      await get('show_on_screen') ?? 'mouse';
  Future<void> setShowOnScreen(String value) => set('show_on_screen', value);

  Future<void> setLaunchOnStartup(bool enabled) =>
      set('launch_on_startup', enabled.toString());

  // ── My Words settings ───────────────────────────────────────────────────

  /// My Words ordering: 'fifo' (default), 'lifo', or 'random'
  Future<String> getMyWordsOrder() async =>
      await get('my_words_order') ?? 'fifo';
  Future<void> setMyWordsOrder(String order) => set('my_words_order', order);

  // ── New cards queue persistence ─────────────────────────────────────────

  static const _newCardsQueueKey = 'new_cards_queue';

  Future<Map<String, dynamic>?> getNewCardsQueue() async {
    final json = await get(_newCardsQueueKey);
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Future<void> setNewCardsQueue(
    List<int> ids,
    int position,
    String hash,
  ) async {
    final json = jsonEncode({'ids': ids, 'position': position, 'hash': hash});
    await set(_newCardsQueueKey, json);
  }

  Future<void> clearNewCardsQueue() async {
    await _db.customUpdate(
      "DELETE FROM settings WHERE key = ?",
      variables: [Variable.withString(_newCardsQueueKey)],
      updates: {_db.settings},
    );
  }

  // ── App update ──────────────────────────────────────────────────────────

  Future<String?> getSkippedVersion() => get('skipped_version');
  Future<void> setSkippedVersion(String version) =>
      set('skipped_version', version);
}
