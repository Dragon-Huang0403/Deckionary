import 'package:drift/drift.dart';

// ── User data tables (read-write, local user.db, synced to Supabase) ─────────

class ReviewCards extends Table {
  TextColumn get id => text()();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get headword => text()();
  TextColumn get pos => text().withDefault(const Constant(''))();
  TextColumn get due => text()();
  RealColumn get stability => real().withDefault(const Constant(0))();
  RealColumn get difficulty => real().withDefault(const Constant(0))();
  IntColumn get elapsedDays =>
      integer().named('elapsed_days').withDefault(const Constant(0))();
  IntColumn get scheduledDays =>
      integer().named('scheduled_days').withDefault(const Constant(0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  IntColumn get state => integer().withDefault(const Constant(0))();
  IntColumn get step => integer().nullable()();
  TextColumn get lastReview => text().named('last_review').nullable()();
  TextColumn get createdAt => text()
      .named('created_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get updatedAt => text()
      .named('updated_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get synced => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'review_cards';
}

class ReviewLogs extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text().named('card_id')();
  IntColumn get rating => integer()();
  IntColumn get state => integer()();
  TextColumn get due => text()();
  RealColumn get stability => real()();
  RealColumn get difficulty => real()();
  IntColumn get elapsedDays => integer().named('elapsed_days')();
  IntColumn get scheduledDays => integer().named('scheduled_days')();
  IntColumn get reviewDuration =>
      integer().named('review_duration').nullable()();
  TextColumn get reviewedAt => text()
      .named('reviewed_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get updatedAt => text().named('updated_at').nullable()();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get synced => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'review_logs';
}

class VocabularyLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get createdAt => text()
      .named('created_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get updatedAt => text()
      .named('updated_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get synced => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'vocabulary_lists';
}

class VocabularyListEntries extends Table {
  TextColumn get id => text()();
  TextColumn get listId => text().named('list_id')();
  IntColumn get entryId => integer().named('entry_id')();
  TextColumn get headword => text()();
  TextColumn get pos => text().withDefault(const Constant(''))();
  TextColumn get addedAt => text()
      .named('added_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get updatedAt => text().named('updated_at').nullable()();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get synced => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'vocabulary_list_entries';
}

class SearchHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().withDefault(const Constant(''))();
  TextColumn get query => text()();
  IntColumn get entryId => integer().named('entry_id').nullable()();
  TextColumn get headword => text().nullable()();
  TextColumn get pos => text().withDefault(const Constant(''))();
  TextColumn get searchedAt => text()
      .named('searched_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get updatedAt => text().named('updated_at').nullable()();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get synced => integer().withDefault(const Constant(0))();

  @override
  String get tableName => 'search_history';
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'settings';
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'sync_meta';
}

@DataClassName('SpeakingResultRow')
class SpeakingResults extends Table {
  TextColumn get id => text()();
  TextColumn get topic => text()();
  BoolColumn get isCustomTopic =>
      boolean().named('is_custom_topic').withDefault(const Constant(false))();
  TextColumn get transcript => text()();
  TextColumn get correctionsJson => text().named('corrections_json')();
  TextColumn get naturalVersion => text().named('natural_version')();
  TextColumn get overallNote => text().named('overall_note').nullable()();
  TextColumn get sessionId => text().named('session_id').nullable()();
  IntColumn get attemptNumber => integer().named('attempt_number').nullable()();
  TextColumn get audioLocalPath =>
      text().named('audio_local_path').nullable()();
  TextColumn get audioStorageKey =>
      text().named('audio_storage_key').nullable()();
  TextColumn get pronunciationIssuesJson =>
      text().named('pronunciation_issues_json').nullable()();
  TextColumn get createdAt => text()
      .named('created_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get updatedAt => text()
      .named('updated_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get synced => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'speaking_results';
}
