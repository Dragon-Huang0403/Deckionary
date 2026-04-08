import 'dart:io' show File, GZipCodec;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'user_tables.dart';

part 'app_database.g.dart';

// ── User database (read-write, Drift-managed) ────────────────────────────────

@DriftDatabase(tables: [
  ReviewCards,
  ReviewLogs,
  VocabularyLists,
  VocabularyListEntries,
  SearchHistory,
  AudioCache,
  Settings,
  SyncQueue,
  SyncMeta,
])
class UserDatabase extends _$UserDatabase {
  UserDatabase() : super(driftDatabase(name: 'user'));
  UserDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;
}

// ── Dictionary database (read-only, opened from pre-built file) ──────────────

class DictionaryDatabase {
  final Database _db;

  DictionaryDatabase._(this._db);

  static Future<DictionaryDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/dictionary.db';

    // Decompress from assets on first launch
    if (!File(dbPath).existsSync()) {
      final compressed = await rootBundle.load('assets/dictionary.db.gz');
      final decompressed = GZipCodec().decode(compressed.buffer.asUint8List());
      await File(dbPath).writeAsBytes(decompressed);
    }

    final db = Database(NativeDatabase(File(dbPath)));
    // Make read-only
    await db.customStatement('PRAGMA query_only = ON');
    return DictionaryDatabase._(db);
  }

  // ── Search ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchPrefix(String query, {int limit = 20}) async {
    final results = await _db.customSelect(
      '''SELECT e.* FROM entries_fts fts
         JOIN entries e ON e.id = fts.rowid
         WHERE fts.headword MATCH ?
         LIMIT ?''',
      variables: [Variable.withString('$query*'), Variable.withInt(limit)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> lookupWord(String headword) async {
    final results = await _db.customSelect(
      'SELECT * FROM entries WHERE headword = ? ORDER BY entry_index',
      variables: [Variable.withString(headword.toLowerCase().trim())],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> lookupVariant(String headword) async {
    final results = await _db.customSelect(
      '''SELECT e.* FROM entries e
         JOIN variants v ON v.entry_id = e.id
         WHERE v.variant = ?
         ORDER BY e.entry_index''',
      variables: [Variable.withString(headword.toLowerCase().trim())],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> fuzzyLookup(String headword) async {
    final key = headword.toLowerCase().trim();

    // 1. Exact match
    var results = await lookupWord(key);
    if (results.isNotEmpty) return results;

    // 2. Variant
    results = await lookupVariant(key);
    if (results.isNotEmpty) return results;

    // 3. Suffix stripping
    const suffixes = ['s', 'es', 'ies', 'ed', 'ing', 'ly'];
    for (final suffix in suffixes) {
      if (!key.endsWith(suffix)) continue;
      final base = key.substring(0, key.length - suffix.length);
      results = await lookupWord(base);
      if (results.isNotEmpty) return results;
      if (suffix == 'ies') {
        results = await lookupWord('${base}y');
        if (results.isNotEmpty) return results;
      }
      if (suffix == 'ed') {
        results = await lookupWord('${base}e');
        if (results.isNotEmpty) return results;
      }
    }

    return [];
  }

  // ── Entry detail loading ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPronunciations(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM pronunciations WHERE entry_id = ?',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getVerbForms(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM verb_forms WHERE entry_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSenseGroups(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM sense_groups WHERE entry_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSenses(int senseGroupId) async {
    final results = await _db.customSelect(
      'SELECT * FROM senses WHERE sense_group_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(senseGroupId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getExamples(int senseId) async {
    final results = await _db.customSelect(
      'SELECT * FROM examples WHERE sense_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(senseId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSynonyms(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM synonyms WHERE entry_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> getWordOrigin(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM word_origins WHERE entry_id = ?',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.isEmpty ? null : results.first.data;
  }

  Future<List<Map<String, dynamic>>> getWordFamily(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM word_family WHERE entry_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getCollocations(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM collocations WHERE entry_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getXrefs(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM xrefs WHERE entry_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getPhrasalVerbs(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM phrasal_verbs WHERE entry_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getExtraExamples(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM extra_examples WHERE entry_id = ? ORDER BY sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  // ── Filters ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEntriesByCefr(String level, {int limit = 100, int offset = 0}) async {
    final results = await _db.customSelect(
      'SELECT * FROM entries WHERE cefr_level = ? ORDER BY headword LIMIT ? OFFSET ?',
      variables: [Variable.withString(level), Variable.withInt(limit), Variable.withInt(offset)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getOxfordEntries({bool ox3000 = false, bool ox5000 = false, int limit = 100, int offset = 0}) async {
    final conditions = <String>[];
    if (ox3000) conditions.add('ox3000 = 1');
    if (ox5000) conditions.add('ox5000 = 1');
    if (conditions.isEmpty) return [];
    final results = await _db.customSelect(
      'SELECT * FROM entries WHERE ${conditions.join(' OR ')} ORDER BY headword LIMIT ? OFFSET ?',
      variables: [Variable.withInt(limit), Variable.withInt(offset)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  Future<int> countEntries({String? cefrLevel, bool? ox3000, bool? ox5000}) async {
    final conditions = <String>[];
    final vars = <Variable>[];
    if (cefrLevel != null) {
      conditions.add('cefr_level = ?');
      vars.add(Variable.withString(cefrLevel));
    }
    if (ox3000 == true) conditions.add('ox3000 = 1');
    if (ox5000 == true) conditions.add('ox5000 = 1');
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final result = await _db.customSelect(
      'SELECT COUNT(*) as cnt FROM entries $where',
      variables: vars,
    ).getSingle();
    return result.data['cnt'] as int;
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
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {},
  );
}
