import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart' hide isNull;
import 'package:supabase/supabase.dart';
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/core/sync/settings_sync.dart';
import 'package:deckionary/core/sync/table_sync.dart';

import 'sync_test_helpers.dart';

void main() {
  late SupabaseClient supabase;
  late UserDatabase db;
  late SettingsSync settingsSync;
  late String userId;

  setUp(() async {
    supabase = createTestSupabase();
    db = createTestDb();
    userId = await createTestUser(supabase);
    final tableSync = TableSync(
      db: db,
      supabase: supabase,
      getUserId: () => userId,
    );
    settingsSync = SettingsSync(
      db: db,
      supabase: supabase,
      getUserId: () => userId,
      tableSync: tableSync,
    );
  });

  tearDown(() async {
    await deleteTestUser(supabase, userId);
    await db.close();
  });

  /// Helper: read a setting from local DB.
  Future<String?> getLocalSetting(String key) async {
    final rows = await db
        .customSelect(
          'SELECT value FROM settings WHERE key = ?',
          variables: [Variable.withString(key)],
          readsFrom: {db.settings},
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.first.data['value'] as String;
  }

  /// Helper: set a setting in local DB (bypassing sync callback).
  Future<void> setLocalSetting(String key, String value) async {
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value),
        );
  }

  /// Helper: mark a setting as dirty in sync_meta.
  Future<void> markDirty(String key) async {
    final rows = await db
        .customSelect(
          "SELECT value FROM sync_meta WHERE key = 'dirty_settings'",
          readsFrom: {db.syncMeta},
        )
        .get();
    final existing =
        rows.isEmpty ? <String>{} : (rows.first.data['value'] as String).split(',').where((s) => s.isNotEmpty).toSet();
    existing.add(key);
    await db
        .into(db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            key: 'dirty_settings',
            value: existing.join(','),
          ),
        );
  }

  /// Helper: push a setting directly to Supabase.
  Future<void> pushRemoteSetting(String key, String value, String updatedAt) async {
    await supabase.from('user_settings').upsert({
      'user_id': userId,
      'key': key,
      'value': value,
      'updated_at': updatedAt,
    });
  }

  group('SettingsSync.pullSettings', () {
    test('pulls remote settings into local DB', () async {
      await pushRemoteSetting(
        'new_cards_per_day',
        '25',
        '2026-04-12T10:00:00.000+00:00',
      );

      final pulled = await settingsSync.pullSettings();

      expect(pulled, 1);
      expect(await getLocalSetting('new_cards_per_day'), '25');
    });

    test('always pulls all settings (no watermark)', () async {
      final t1 = '2026-04-10T10:00:00.000+00:00';
      final t2 = '2026-04-12T10:00:00.000+00:00';

      await pushRemoteSetting('new_cards_per_day', '20', t1);
      await pushRemoteSetting('audio_dialect', 'us', t2);

      // First pull
      await settingsSync.pullSettings();
      expect(await getLocalSetting('new_cards_per_day'), '20');
      expect(await getLocalSetting('audio_dialect'), 'us');

      // Push another setting with OLD timestamp (simulates late push from device)
      await pushRemoteSetting('max_reviews_per_day', '100', t1);

      // Second pull — must still get it (no watermark filtering)
      final pulled = await settingsSync.pullSettings();
      expect(pulled, greaterThanOrEqualTo(1));
      expect(await getLocalSetting('max_reviews_per_day'), '100');
    });

    test('skips non-synced setting keys', () async {
      await pushRemoteSetting(
        'some_unknown_key',
        'value',
        '2026-04-12T10:00:00.000+00:00',
      );

      final pulled = await settingsSync.pullSettings();

      expect(pulled, 0);
      expect(await getLocalSetting('some_unknown_key'), null);
    });

    test('does NOT overwrite locally dirty settings', () async {
      // Local has a dirty setting (user changed it, push pending)
      await setLocalSetting('audio_dialect', 'uk');
      await markDirty('audio_dialect');

      // Remote has a different value
      await pushRemoteSetting(
        'audio_dialect',
        'us',
        '2026-04-12T10:00:00.000+00:00',
      );

      // Pull should skip dirty key
      await settingsSync.pullSettings();

      // Local value preserved (not overwritten by remote)
      expect(await getLocalSetting('audio_dialect'), 'uk');
    });

    test('pulls non-dirty settings while skipping dirty ones', () async {
      // One setting is dirty locally
      await setLocalSetting('audio_dialect', 'uk');
      await markDirty('audio_dialect');

      // Remote has both settings
      await pushRemoteSetting(
        'audio_dialect',
        'us',
        '2026-04-12T10:00:00.000+00:00',
      );
      await pushRemoteSetting(
        'new_cards_per_day',
        '30',
        '2026-04-12T10:00:00.000+00:00',
      );

      await settingsSync.pullSettings();

      // Dirty setting preserved, non-dirty pulled
      expect(await getLocalSetting('audio_dialect'), 'uk');
      expect(await getLocalSetting('new_cards_per_day'), '30');
    });
  });

  group('SettingsSync.pushDirtySettings', () {
    test('pushes dirty settings to remote', () async {
      await setLocalSetting('new_cards_per_day', '15');
      await markDirty('new_cards_per_day');

      await settingsSync.pushDirtySettings();

      // Verify pushed to remote
      final remote = await supabase
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .eq('key', 'new_cards_per_day');
      expect(remote, hasLength(1));
      expect(remote.first['value'], '15');
    });

    test('continues pushing remaining settings after one fails', () async {
      // Set up two dirty settings
      await setLocalSetting('new_cards_per_day', '10');
      await setLocalSetting('audio_dialect', 'uk');
      await markDirty('nonexistent_but_dirty'); // will be removed (no local row)
      await markDirty('new_cards_per_day');
      await markDirty('audio_dialect');

      // Push — nonexistent key is skipped, remaining should still push
      await settingsSync.pushDirtySettings();

      // Both valid settings should be in remote
      final remote = await supabase
          .from('user_settings')
          .select()
          .eq('user_id', userId);
      final keys = remote.map((r) => r['key'] as String).toSet();
      expect(keys, contains('new_cards_per_day'));
      expect(keys, contains('audio_dialect'));
    });
  });

  group('Settings two-device sync', () {
    test('setting changed on device A appears on device B after pull', () async {
      // Device A pushes a setting
      await pushRemoteSetting(
        'review_card_order',
        'random',
        '2026-04-12T10:00:00.000+00:00',
      );

      // Device B pulls
      await settingsSync.pullSettings();

      expect(await getLocalSetting('review_card_order'), 'random');
    });

    test('dirty setting on device B is not overwritten by pull then pushed', () async {
      // Remote has a setting
      await pushRemoteSetting(
        'auto_pronounce',
        'false',
        '2026-04-10T10:00:00.000+00:00',
      );

      // Device B changes it locally (newer)
      await setLocalSetting('auto_pronounce', 'true');
      await markDirty('auto_pronounce');

      // Pull → push cycle (the correct order)
      await settingsSync.pullSettings();
      await settingsSync.pushDirtySettings();

      // Local should still be 'true' (dirty was preserved)
      expect(await getLocalSetting('auto_pronounce'), 'true');

      // Remote should now be 'true' (pushed)
      final remote = await supabase
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .eq('key', 'auto_pronounce');
      expect(remote.first['value'], 'true');
    });
  });
}
