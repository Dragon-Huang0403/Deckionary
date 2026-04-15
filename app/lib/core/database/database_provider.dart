import 'package:flutter_riverpod/flutter_riverpod.dart';
export 'app_database.dart';
import 'app_database.dart';
import 'review_dao.dart';
import 'search_history_dao.dart';
import 'settings_dao.dart';
import 'vocabulary_list_dao.dart';
import '../sync/sync_provider.dart';

/// Global provider for the read-only dictionary database.
late final DictionaryDatabase globalDictDb;

final dictionaryDbProvider = Provider<DictionaryDatabase>((ref) {
  return globalDictDb;
});

/// Global provider for the read-write user database.
late final UserDatabase globalUserDb;

final userDbProvider = Provider<UserDatabase>((ref) {
  return globalUserDb;
});

/// Search history DAO
final searchHistoryDaoProvider = Provider<SearchHistoryDao>((ref) {
  return SearchHistoryDao(ref.read(userDbProvider));
});

/// Settings DAO — auto-pushes changes to Supabase if sync is available.
final settingsDaoProvider = Provider<SettingsDao>((ref) {
  final dao = SettingsDao(ref.read(userDbProvider));
  final sync = ref.read(syncServiceProvider);
  if (sync != null) {
    dao.onSettingChanged = (key, value) => sync.pushSetting(key, value);
  }
  return dao;
});

/// Which pronunciation dialects to display: 'both', 'us', or 'gb'.
/// Watched by EntryCard and review screen to filter pronunciation/audio visibility.
final pronunciationDisplayProvider = FutureProvider<String>((ref) async {
  return ref.read(settingsDaoProvider).getPronunciationDisplay();
});

/// Review DAO
final reviewDaoProvider = Provider<ReviewDao>((ref) {
  return ReviewDao(
    db: ref.read(userDbProvider),
    dictDb: ref.read(dictionaryDbProvider),
  );
});

/// Vocabulary list DAO (My Words)
final vocabularyListDaoProvider = Provider<VocabularyListDao>((ref) {
  return VocabularyListDao(ref.read(userDbProvider));
});

/// Initialize databases. Call before runApp.
Future<void> initDatabases() async {
  globalUserDb = UserDatabase();
  await Future.wait([
    DictionaryDatabase.open().then((db) => globalDictDb = db),
    globalUserDb.warmUp(),
  ]);
}
