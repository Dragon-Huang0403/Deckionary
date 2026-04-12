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

  // ── App update ──────────────────────────────────────────────────────────

  Future<String?> getSkippedVersion() => get('skipped_version');
  Future<void> setSkippedVersion(String version) =>
      set('skipped_version', version);
}
