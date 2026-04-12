import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import 'sync_meta_helpers.dart';

class SettingsSync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;

  SettingsSync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId;

  static const _syncedSettingKeys = [
    'new_cards_per_day',
    'max_reviews_per_day',
    'review_card_order',
    'review_auto_play_mode',
    'review_filter',
    'audio_dialect',
    'pronunciation_display',
    'auto_pronounce',
    'theme_mode',
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
      debugPrint('Push setting "$key" failed, marking dirty: $e');
      await _addDirtySetting(key);
    }
  }

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
        break;
      }
    }
  }

  Future<int> pullSettings() async {
    if (_getUserId() == null) return 0;

    final lastSyncAt = await getLastSyncAt(_db, 'user_settings');

    var filter = _supabase
        .from('user_settings')
        .select()
        .eq('user_id', _getUserId()!);

    if (lastSyncAt != null) {
      filter = filter.gt('updated_at', lastSyncAt);
    }

    final rows = await filter.order('updated_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      final key = row['key'] as String;
      final value = row['value'] as String;
      if (!_syncedSettingKeys.contains(key)) continue;

      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(key: key, value: value),
          );
      pulled++;
    }

    if (rows.isNotEmpty) {
      await setLastSyncAt(
        _db,
        'user_settings',
        rows.first['updated_at'] as String,
      );
    }

    return pulled;
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
