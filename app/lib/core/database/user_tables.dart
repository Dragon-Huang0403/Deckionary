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
  IntColumn get isPreset =>
      integer().named('is_preset').withDefault(const Constant(0))();
  TextColumn get presetType =>
      text().named('preset_type').withDefault(const Constant(''))();
  TextColumn get createdAt => text()
      .named('created_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get updatedAt => text()
      .named('updated_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();

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
  TextColumn get addedAt => text()
      .named('added_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();

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

class AudioCache extends Table {
  TextColumn get filename => text()();
  TextColumn get filePath => text().named('file_path')();
  IntColumn get sizeBytes => integer().named('size_bytes')();
  TextColumn get downloadedAt => text()
      .named('downloaded_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();

  @override
  Set<Column> get primaryKey => {filename};

  @override
  String get tableName => 'audio_cache';
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'settings';
}

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tableName_ => text().named('table_name')();
  TextColumn get recordId => text().named('record_id')();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  TextColumn get createdAt => text()
      .named('created_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  IntColumn get synced => integer().withDefault(const Constant(0))();

  @override
  String get tableName => 'sync_queue';
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};

  @override
  String get tableName => 'sync_meta';
}
