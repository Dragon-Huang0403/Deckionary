import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';

/// Global provider for the read-only dictionary database.
late final DictionaryDatabase globalDictDb;

final dictionaryDbProvider = Provider<DictionaryDatabase>((ref) {
  return globalDictDb;
});

/// Global provider for the read-write user database.
final userDbProvider = Provider<UserDatabase>((ref) {
  return UserDatabase();
});

/// Initialize databases. Call before runApp.
Future<void> initDatabases() async {
  globalDictDb = await DictionaryDatabase.open();
}
