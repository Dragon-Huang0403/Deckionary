import 'dart:io' show File;
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
  int get schemaVersion => 3;

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
    },
  );

  /// Force DB open + migration so first real query is instant.
  Future<void> warmUp() => customSelect('SELECT 1').getSingle();
}

// ── Dictionary database (read-only, opened from pre-built file) ──────────────

class DictionaryDatabase {
  final Database _db;

  DictionaryDatabase._(this._db);

  static Future<DictionaryDatabase> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/dictionary.db';

    // Copy from bundled asset on first launch
    if (!File(dbPath).existsSync()) {
      final bytes = await rootBundle.load('assets/oald10.db');
      await File(dbPath).writeAsBytes(bytes.buffer.asUint8List());
    }

    final db = Database(NativeDatabase.createInBackground(File(dbPath)));
    // Make read-only
    await db.customStatement('PRAGMA query_only = ON');
    return DictionaryDatabase._(db);
  }

  // ── Search ───────────────────────────────────────────────────────────────

  /// Cached headword list for fuzzy search (loaded once, ~1MB)
  List<String>? _headwordCache;

  Future<List<String>> get _headwords async {
    if (_headwordCache != null) return _headwordCache!;
    final rows = await _db.customSelect(
      'SELECT DISTINCT headword FROM entries ORDER BY headword',
    ).get();
    _headwordCache = rows.map((r) => r.data['headword'] as String).toList();
    return _headwordCache!;
  }

  /// Fuzzy search using Levenshtein distance.
  /// Only runs when prefix search returns no results.
  Future<List<Map<String, dynamic>>> fuzzySearch(String query, {int limit = 10, int maxDistance = 2}) async {
    final q = query.toLowerCase().trim();
    if (q.length < 3) return []; // too short for fuzzy

    final words = await _headwords;

    // Pre-filter: length within ±maxDistance, then compute Levenshtein
    final candidates = <(String, int)>[];
    for (final w in words) {
      if ((w.length - q.length).abs() > maxDistance) continue;
      final d = _levenshtein(q, w.toLowerCase());
      if (d <= maxDistance) {
        candidates.add((w, d));
      }
    }
    candidates.sort((a, b) => a.$2.compareTo(b.$2));

    // Load entries for top matches
    final results = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final (word, _) in candidates) {
      if (seen.add(word) && results.length < limit) {
        final entries = await lookupWord(word);
        if (entries.isNotEmpty) {
          results.addAll(entries);
        }
      }
    }
    return results;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> prev = List.generate(t.length + 1, (i) => i);
    List<int> curr = List.filled(t.length + 1, 0);

    for (var i = 0; i < s.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final cost = s.codeUnitAt(i) == t.codeUnitAt(j) ? 0 : 1;
        curr[j + 1] = [curr[j] + 1, prev[j + 1] + 1, prev[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[t.length];
  }

  /// Autocomplete: prefix match on headwords, prioritizing shorter/exact matches.
  /// Returns deduplicated headwords with their entries.
  Future<List<Map<String, dynamic>>> searchPrefix(String query, {int limit = 20}) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    final results = await _db.customSelect(
      '''SELECT * FROM entries
         WHERE headword LIKE ?
         ORDER BY
           CASE WHEN headword = ? THEN 0 ELSE 1 END,
           LENGTH(headword),
           headword,
           entry_index
         LIMIT ?''',
      variables: [
        Variable.withString('$q%'),
        Variable.withString(q),
        Variable.withInt(limit * 3), // over-fetch to get variety after dedup
      ],
    ).get();

    // Deduplicate: keep first entry per headword, up to limit
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final r in results) {
      final hw = r.data['headword'] as String;
      if (seen.add(hw) && deduped.length < limit) {
        deduped.add(r.data);
      }
    }
    return deduped;
  }

  /// Search across headwords with FTS (for full-text, not prefix)
  Future<List<Map<String, dynamic>>> searchFts(String query, {int limit = 20}) async {
    final results = await _db.customSelect(
      '''SELECT e.* FROM entries_fts fts
         JOIN entries e ON e.id = fts.rowid
         WHERE fts.headword MATCH ?
         LIMIT ?''',
      variables: [Variable.withString('"$query"'), Variable.withInt(limit)],
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

  /// Batch: all senses for an entry (avoids per-group queries)
  Future<List<Map<String, dynamic>>> getAllSensesForEntry(int entryId) async {
    final results = await _db.customSelect(
      'SELECT * FROM senses WHERE entry_id = ? ORDER BY sense_group_id, sort_order',
      variables: [Variable.withInt(entryId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// Batch: all examples for an entry via JOIN (avoids per-sense queries)
  Future<List<Map<String, dynamic>>> getAllExamplesForEntry(int entryId) async {
    final results = await _db.customSelect(
      '''SELECT ex.* FROM examples ex
         JOIN senses s ON ex.sense_id = s.id
         WHERE s.entry_id = ?
         ORDER BY ex.sense_id, ex.sort_order''',
      variables: [Variable.withInt(entryId)],
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

  /// Look up full entry rows by a list of IDs.
  Future<List<Map<String, dynamic>>> getEntriesByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final results = await _db.customSelect(
      'SELECT * FROM entries WHERE id IN ($placeholders)',
      variables: ids.map((id) => Variable.withInt(id)).toList(),
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// Get entry IDs matching a CEFR/Oxford filter (for review card creation).
  /// [cefrLevels] e.g. ['a1', 'b2'], [ox3000]/[ox5000] booleans.
  /// Returns list of entry IDs matching any of the criteria (OR).
  Future<List<int>> getFilteredEntryIds({
    List<String> cefrLevels = const [],
    bool ox3000 = false,
    bool ox5000 = false,
    int limit = 1000,
    int offset = 0,
  }) async {
    final conditions = <String>[];
    final vars = <Variable>[];
    for (final level in cefrLevels) {
      conditions.add('cefr_level = ?');
      vars.add(Variable.withString(level));
    }
    if (ox3000) conditions.add('ox3000 = 1');
    if (ox5000) conditions.add('ox5000 = 1');
    if (conditions.isEmpty) return [];
    final where = conditions.join(' OR ');
    final results = await _db.customSelect(
      'SELECT id FROM entries WHERE $where ORDER BY headword LIMIT ? OFFSET ?',
      variables: [...vars, Variable.withInt(limit), Variable.withInt(offset)],
    ).get();
    return results.map((r) => r.data['id'] as int).toList();
  }

  /// Count entries matching a CEFR/Oxford filter.
  Future<int> countFilteredEntries({
    List<String> cefrLevels = const [],
    bool ox3000 = false,
    bool ox5000 = false,
  }) async {
    final conditions = <String>[];
    final vars = <Variable>[];
    for (final level in cefrLevels) {
      conditions.add('cefr_level = ?');
      vars.add(Variable.withString(level));
    }
    if (ox3000) conditions.add('ox3000 = 1');
    if (ox5000) conditions.add('ox5000 = 1');
    if (conditions.isEmpty) return 0;
    final where = conditions.join(' OR ');
    final result = await _db.customSelect(
      'SELECT COUNT(*) as cnt FROM entries WHERE $where',
      variables: vars,
    ).getSingle();
    return result.data['cnt'] as int;
  }

  /// All unique audio filenames across pronunciations, verb_forms, examples.
  Future<List<String>> getAllAudioFilenames() async {
    final rows = await _db.customSelect('''
      SELECT DISTINCT audio_file AS f FROM pronunciations WHERE audio_file != ''
      UNION
      SELECT DISTINCT audio_gb FROM verb_forms WHERE audio_gb != ''
      UNION
      SELECT DISTINCT audio_us FROM verb_forms WHERE audio_us != ''
      UNION
      SELECT DISTINCT audio_gb FROM examples WHERE audio_gb != ''
      UNION
      SELECT DISTINCT audio_us FROM examples WHERE audio_us != ''
    ''').get();
    return rows.map((r) => r.data['f'] as String).toList();
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
