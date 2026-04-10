import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';
import 'review_dao.dart';
import 'search_history_dao.dart';
import 'settings_dao.dart';

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

/// Settings DAO
final settingsDaoProvider = Provider<SettingsDao>((ref) {
  return SettingsDao(ref.read(userDbProvider));
});

/// Review DAO
final reviewDaoProvider = Provider<ReviewDao>((ref) {
  return ReviewDao(
    db: ref.read(userDbProvider),
    dictDb: ref.read(dictionaryDbProvider),
  );
});

/// Initialize databases. Call before runApp.
Future<void> initDatabases() async {
  globalUserDb = UserDatabase();
  await Future.wait([
    DictionaryDatabase.open().then((db) => globalDictDb = db),
    globalUserDb.warmUp(),
  ]);
}
