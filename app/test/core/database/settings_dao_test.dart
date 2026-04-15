import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/core/database/settings_dao.dart';
import '../../test_helpers.dart';

void main() {
  late UserDatabase db;
  late SettingsDao dao;

  setUp(() {
    db = createTestUserDb();
    dao = SettingsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('get/set', () {
    test('returns null for missing key', () async {
      final value = await dao.get('nonexistent_key');
      expect(value, isNull);
    });

    test('set then get returns stored value', () async {
      await dao.set('test_key', 'test_value');
      final value = await dao.get('test_key');
      expect(value, 'test_value');
    });

    test('overwrite updates existing value', () async {
      await dao.set('test_key', 'first');
      await dao.set('test_key', 'second');
      final value = await dao.get('test_key');
      expect(value, 'second');
    });
  });

  group('getAll', () {
    test('returns empty map when no settings stored', () async {
      final all = await dao.getAll();
      expect(all, isEmpty);
    });

    test('returns all stored settings', () async {
      await dao.set('key_a', 'value_a');
      await dao.set('key_b', 'value_b');
      final all = await dao.getAll();
      expect(all, {'key_a': 'value_a', 'key_b': 'value_b'});
    });
  });

  group('typed getters with defaults', () {
    test('getDialect returns us by default', () async {
      expect(await dao.getDialect(), 'us');
    });

    test('getAutoPronounce returns true by default', () async {
      expect(await dao.getAutoPronounce(), isTrue);
    });

    test('getAutoPronounce returns false when set to false', () async {
      await dao.setAutoPronounce(false);
      expect(await dao.getAutoPronounce(), isFalse);
    });

    test('getNewCardsPerDay returns 20 by default', () async {
      expect(await dao.getNewCardsPerDay(), 20);
    });

    test('getNewCardsPerDay returns set value', () async {
      await dao.setNewCardsPerDay(30);
      expect(await dao.getNewCardsPerDay(), 30);
    });

    test('getNewCardsPerDay returns default for non-numeric value', () async {
      await dao.set('new_cards_per_day', 'not_a_number');
      expect(await dao.getNewCardsPerDay(), 20);
    });

    test('getMaxReviewsPerDay returns 200 by default', () async {
      expect(await dao.getMaxReviewsPerDay(), 200);
    });

    test('getMaxReviewsPerDay returns set value', () async {
      await dao.setMaxReviewsPerDay(100);
      expect(await dao.getMaxReviewsPerDay(), 100);
    });

    test('getMaxReviewsPerDay returns default for non-numeric value', () async {
      await dao.set('max_reviews_per_day', 'not_a_number');
      expect(await dao.getMaxReviewsPerDay(), 200);
    });

    test('getThemeMode returns system by default', () async {
      expect(await dao.getThemeMode(), 'system');
    });

    test('getThemeMode returns set value', () async {
      await dao.setThemeMode('dark');
      expect(await dao.getThemeMode(), 'dark');
    });

    test('getShowTrayIcon returns true by default', () async {
      expect(await dao.getShowTrayIcon(), isTrue);
    });

    test('getShowTrayIcon returns false when set to false', () async {
      await dao.setShowTrayIcon(false);
      expect(await dao.getShowTrayIcon(), isFalse);
    });

    test('getShowInDock returns true by default', () async {
      expect(await dao.getShowInDock(), isTrue);
    });

    test('getShowInDock returns false when set to false', () async {
      await dao.setShowInDock(false);
      expect(await dao.getShowInDock(), isFalse);
    });

    test('getReviewCardOrder returns random by default', () async {
      expect(await dao.getReviewCardOrder(), 'random');
    });

    test('getReviewCardOrder returns set value', () async {
      await dao.setReviewCardOrder('alphabetical');
      expect(await dao.getReviewCardOrder(), 'alphabetical');
    });
  });

  group('reviewAutoPlayMode migration', () {
    test('returns pronunciation by default when no key set', () async {
      expect(await dao.getReviewAutoPlayMode(), 'pronunciation');
    });

    test('direct set works correctly', () async {
      await dao.setReviewAutoPlayMode('off');
      expect(await dao.getReviewAutoPlayMode(), 'off');

      await dao.setReviewAutoPlayMode('sentence_pronunciation');
      expect(await dao.getReviewAutoPlayMode(), 'sentence_pronunciation');
    });

    test('old review_auto_pronounce=false migrates to off', () async {
      await dao.set('review_auto_pronounce', 'false');
      expect(await dao.getReviewAutoPlayMode(), 'off');
      // Migration should persist the new value
      expect(await dao.get('review_auto_play_mode'), 'off');
    });

    test(
      'old review_auto_pronounce=true falls back to pronunciation default',
      () async {
        await dao.set('review_auto_pronounce', 'true');
        expect(await dao.getReviewAutoPlayMode(), 'pronunciation');
      },
    );

    test('new key takes precedence over old key when both present', () async {
      await dao.set('review_auto_pronounce', 'false');
      await dao.set('review_auto_play_mode', 'sentence_pronunciation');
      expect(await dao.getReviewAutoPlayMode(), 'sentence_pronunciation');
    });
  });

  group('showOnScreen', () {
    test('returns mouse by default', () async {
      expect(await dao.getShowOnScreen(), 'mouse');
    });

    test('round-trips activeWindow', () async {
      await dao.setShowOnScreen('activeWindow');
      expect(await dao.getShowOnScreen(), 'activeWindow');
    });

    test('round-trips primaryScreen', () async {
      await dao.setShowOnScreen('primaryScreen');
      expect(await dao.getShowOnScreen(), 'primaryScreen');
    });

    test('overwrite updates value', () async {
      await dao.setShowOnScreen('activeWindow');
      await dao.setShowOnScreen('primaryScreen');
      expect(await dao.getShowOnScreen(), 'primaryScreen');
    });
  });

  group('onSettingChanged callback', () {
    test('fires on set with correct key and value', () async {
      String? capturedKey;
      String? capturedValue;
      dao.onSettingChanged = (key, value) {
        capturedKey = key;
        capturedValue = value;
      };

      await dao.set('audio_dialect', 'gb');

      expect(capturedKey, 'audio_dialect');
      expect(capturedValue, 'gb');
    });

    test('fires on every set call', () async {
      final calls = <(String, String)>[];
      dao.onSettingChanged = (key, value) => calls.add((key, value));

      await dao.set('key_1', 'val_1');
      await dao.set('key_2', 'val_2');
      await dao.set('key_1', 'val_3');

      expect(calls.length, 3);
      expect(calls[0], ('key_1', 'val_1'));
      expect(calls[1], ('key_2', 'val_2'));
      expect(calls[2], ('key_1', 'val_3'));
    });

    test('no exception when callback is null', () async {
      dao.onSettingChanged = null;
      // Should not throw
      await expectLater(dao.set('some_key', 'some_value'), completes);
    });
  });
}
