import 'dart:io' show File;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'user_tables.dart';

export 'dictionary_search.dart';
export 'dictionary_entry_detail.dart';
export 'dictionary_filter.dart';

part 'app_database.g.dart';

// ── User database (read-write, Drift-managed) ────────────────────────────────

@DriftDatabase(
  tables: [
    ReviewCards,
    ReviewLogs,
    VocabularyLists,
    VocabularyListEntries,
    SpeakingResults,
    SearchHistory,
    Settings,
    SyncMeta,
  ],
)
class UserDatabase extends _$UserDatabase {
  UserDatabase() : super(driftDatabase(name: 'user'));
  UserDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(searchHistory, searchHistory.uuid);
        await m.addColumn(searchHistory, searchHistory.synced);
      }
      if (from < 3) {
        await m.addColumn(reviewCards, reviewCards.step);
        await m.addColumn(reviewLogs, reviewLogs.reviewDuration);
      }
      if (from < 4) {
        await m.addColumn(reviewCards, reviewCards.synced);
        await m.addColumn(reviewLogs, reviewLogs.synced);
      }
      if (from < 5) {
        await m.addColumn(searchHistory, searchHistory.pos);
      }
      if (from < 6) {
        await m.addColumn(searchHistory, searchHistory.deletedAt);
        await m.addColumn(reviewCards, reviewCards.deletedAt);
        await m.addColumn(reviewLogs, reviewLogs.deletedAt);
        await customStatement(
          'ALTER TABLE search_history ADD COLUMN updated_at TEXT',
        );
        await customStatement(
          'ALTER TABLE review_logs ADD COLUMN updated_at TEXT',
        );
        await customStatement(
          'UPDATE search_history SET updated_at = searched_at',
        );
        await customStatement(
          'UPDATE review_logs SET updated_at = reviewed_at',
        );
      }
      if (from < 7) {
        await customStatement('DROP TABLE IF EXISTS audio_cache');
        await customStatement('DROP TABLE IF EXISTS sync_queue');
      }
      if (from < 8) {
        // Reshape vocabulary tables (previously unused, safe to recreate)
        await customStatement('DROP TABLE IF EXISTS vocabulary_lists');
        await customStatement('DROP TABLE IF EXISTS vocabulary_list_entries');
        await m.createTable(vocabularyLists);
        await m.createTable(vocabularyListEntries);
      }
      if (from < 9) {
        // createTable uses the current schema, which already includes
        // session_id/attempt_number (added in v10). Nothing to do at v10.
        await m.createTable(speakingResults);
      }
      if (from == 9) {
        // Only needed when the table was created at v9 without these columns.
        await m.addColumn(speakingResults, speakingResults.sessionId);
        await m.addColumn(speakingResults, speakingResults.attemptNumber);
        // Backfill: treat each existing row as a single-attempt session
        await customStatement(
          'UPDATE speaking_results SET session_id = id, attempt_number = 1 '
          'WHERE session_id IS NULL',
        );
      }
      if (from < 11) {
        await m.addColumn(speakingResults, speakingResults.audioLocalPath);
        await m.addColumn(speakingResults, speakingResults.audioStorageKey);
      }
      if (from < 12) {
        await m.addColumn(
          speakingResults,
          speakingResults.pronunciationIssuesJson,
        );
      }
    },
  );

  /// Force DB open + migration so first real query is instant.
  Future<void> warmUp() => customSelect('SELECT 1').getSingle();
}

// ── Dictionary database (read-only, opened from pre-built file) ──────────────

class DictionaryDatabase {
  final Database _db;

  /// Expose raw DB for extension methods.
  Database get db => _db;

  DictionaryDatabase._(this._db);

  /// Open a dictionary database from a file path (for tests).
  static DictionaryDatabase forTesting(String dbPath) {
    final db = Database(NativeDatabase(File(dbPath)));
    return DictionaryDatabase._(db);
  }

  /// Must match SCHEMA_VERSION in db/schema.py.
  /// Bump this when the bundled oald10.db is rebuilt with a new schema.
  static const _bundledSchemaVersion = 7;

  static Future<DictionaryDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/dictionary.db';
    final dbFile = File(dbPath);

    if (dbFile.existsSync()) {
      // Re-copy bundled asset if local DB is outdated
      final localVersion = await _readSchemaVersion(dbPath);
      if (localVersion < _bundledSchemaVersion) {
        final bytes = await rootBundle.load('assets/oald10.db');
        await dbFile.writeAsBytes(bytes.buffer.asUint8List());
      }
    } else {
      // First launch: copy from bundled asset
      final bytes = await rootBundle.load('assets/oald10.db');
      await dbFile.writeAsBytes(bytes.buffer.asUint8List());
    }

    final db = Database(NativeDatabase.createInBackground(dbFile));
    // Make read-only
    await db.customStatement('PRAGMA query_only = ON');
    return DictionaryDatabase._(db);
  }

  /// Read schema_version from a SQLite file's meta table.
  static Future<int> _readSchemaVersion(String dbPath) async {
    final db = Database(NativeDatabase.createInBackground(File(dbPath)));
    try {
      final rows = await db
          .customSelect("SELECT value FROM meta WHERE key = 'schema_version'")
          .get();
      if (rows.isEmpty) return 0;
      return int.tryParse(rows.first.data['value'] as String? ?? '') ?? 0;
    } catch (_) {
      return 0;
    } finally {
      await db.close();
    }
  }

  /// Cached headword list for fuzzy search (loaded once, ~1MB)
  List<String>? _headwordCache;

  Future<List<String>> get headwords async {
    if (_headwordCache != null) return _headwordCache!;
    final rows = await _db
        .customSelect('SELECT DISTINCT headword FROM entries ORDER BY headword')
        .get();
    _headwordCache = rows.map((r) => r.data['headword'] as String).toList();
    return _headwordCache!;
  }

  Future<void> close() async {
    await _db.close();
  }
}

// ── Helper: raw NativeDatabase for read-only dictionary ──────────────────────

class Database extends GeneratedDatabase {
  Database(super.e);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => [];

  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {});
}
