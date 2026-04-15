import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../logging/logging_service.dart';
import 'table_sync.dart';

class SettingsSync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;
  final TableSync _tableSync;

  SettingsSync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
    required TableSync tableSync,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId,
       _tableSync = tableSync;

  static const _syncedSettingKeys = [
    'new_cards_per_day',
    'max_reviews_per_day',
    'review_card_order',
    'review_auto_play_mode',
    'review_filter',
    'audio_dialect',
    'pronunciation_display',
    'auto_pronounce',
  ];

  Future<void> pushSetting(String key, String value) async {
    if (_getUserId() == null || !_syncedSettingKeys.contains(key)) return;
    try {
      await _supabase.from('user_settings').upsert({
        'user_id': _getUserId(),
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await _removeDirtySetting(key);
    } catch (e) {
      globalTalker.error('[Sync] Push setting "$key" failed, marking dirty: $e');
      await _addDirtySetting(key);
    }
  }

  /// Push all dirty settings. Continues on error (was previously break).
  Future<void> pushDirtySettings() async {
    if (_getUserId() == null) return;
    final dirty = await _getDirtySettings();
    if (dirty.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    for (final key in dirty) {
      final row = await (_db.select(
        _db.settings,
      )..where((t) => t.key.equals(key))).getSingleOrNull();
      if (row == null) {
        await _removeDirtySetting(key);
        continue;
      }
      try {
        await _supabase.from('user_settings').upsert({
          'user_id': _getUserId(),
          'key': key,
          'value': row.value,
          'updated_at': now,
        });
        await _removeDirtySetting(key);
      } catch (e) {
        continue; // was: break — now continues to attempt remaining keys
      }
    }
  }

  /// Pull all settings (no watermark — only 8 keys, always fetch all).
  /// Skips keys that are locally dirty (local change takes priority).
  Future<int> pullSettings() => _tableSync.pull(
    remoteTable: 'user_settings',
    watermarkKey: null, // always fetch all — small table, no watermark needed
    processRow: _processSettingRow,
  );

  Future<bool> _processSettingRow(Map<String, dynamic> row) async {
    final key = row['key'] as String;
    final value = row['value'] as String;
    if (!_syncedSettingKeys.contains(key)) return false;

    // Don't overwrite locally-dirty settings — they'll be pushed next.
    final dirty = await _getDirtySettings();
    if (dirty.contains(key)) return false;

    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
    return true;
  }

  Future<int> pushAllSettings() async {
    if (_getUserId() == null) return 0;
    var pushed = 0;
    final now = DateTime.now().toUtc().toIso8601String();

    for (final key in _syncedSettingKeys) {
      final row = await (_db.select(
        _db.settings,
      )..where((t) => t.key.equals(key))).getSingleOrNull();
      if (row == null) continue;

      try {
        await _supabase.from('user_settings').upsert({
          'user_id': _getUserId(),
          'key': key,
          'value': row.value,
          'updated_at': now,
        });
        pushed++;
      } catch (e) {
        continue;
      }
    }
    return pushed;
  }

  // ── Dirty settings tracking ─────────────────────────────────────────────

  static const _dirtySettingsKey = 'dirty_settings';

  Future<Set<String>> _getDirtySettings() async {
    final rows = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [Variable.withString(_dirtySettingsKey)],
          readsFrom: {_db.syncMeta},
        )
        .get();
    if (rows.isEmpty) return {};
    final csv = rows.first.data['value'] as String;
    return csv.isEmpty ? {} : csv.split(',').toSet();
  }

  Future<void> _addDirtySetting(String key) async {
    final dirty = await _getDirtySettings();
    dirty.add(key);
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: _dirtySettingsKey,
            value: dirty.join(','),
          ),
        );
  }

  Future<void> _removeDirtySetting(String key) async {
    final dirty = await _getDirtySettings();
    if (!dirty.remove(key)) return;
    await _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: _dirtySettingsKey,
            value: dirty.join(','),
          ),
        );
  }
}
