import 'package:drift/drift.dart';
import 'app_database.dart';

extension DictionaryFilter on DictionaryDatabase {
  Future<List<Map<String, dynamic>>> getEntriesByCefr(
    String level, {
    int limit = 100,
    int offset = 0,
  }) async {
    final results = await db
        .customSelect(
          'SELECT * FROM entries WHERE cefr_level = ? ORDER BY headword, entry_index LIMIT ? OFFSET ?',
          variables: [
            Variable.withString(level),
            Variable.withInt(limit),
            Variable.withInt(offset),
          ],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getEntriesByOxfordList({
    required bool ox3000,
    int limit = 50,
    int offset = 0,
  }) async {
    final col = ox3000 ? 'ox3000' : 'ox5000';
    final results = await db
        .customSelect(
          'SELECT * FROM entries WHERE $col = 1 ORDER BY headword, entry_index LIMIT ? OFFSET ?',
          variables: [Variable.withInt(limit), Variable.withInt(offset)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getFilteredEntries({
    List<String> cefrLevels = const [],
    bool ox3000 = false,
    bool ox5000 = false,
    int limit = 50,
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
    final results = await db
        .customSelect(
          'SELECT * FROM entries WHERE $where ORDER BY headword, entry_index LIMIT ? OFFSET ?',
          variables: [
            ...vars,
            Variable.withInt(limit),
            Variable.withInt(offset),
          ],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<int> countEntries({
    String? cefrLevel,
    bool? ox3000,
    bool? ox5000,
  }) async {
    final conditions = <String>[];
    final vars = <Variable>[];
    if (cefrLevel != null) {
      conditions.add('cefr_level = ?');
      vars.add(Variable.withString(cefrLevel));
    }
    if (ox3000 == true) conditions.add('ox3000 = 1');
    if (ox5000 == true) conditions.add('ox5000 = 1');
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final result = await db
        .customSelect(
          'SELECT COUNT(*) as cnt FROM entries $where',
          variables: vars,
        )
        .getSingle();
    return result.data['cnt'] as int;
  }

  Future<List<Map<String, dynamic>>> getEntriesByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final results = await db
        .customSelect(
          'SELECT * FROM entries WHERE id IN ($placeholders)',
          variables: ids.map((id) => Variable.withInt(id)).toList(),
        )
        .get();
    return results.map((r) => r.data).toList();
  }

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
    final results = await db
        .customSelect(
          'SELECT id FROM entries WHERE $where ORDER BY headword LIMIT ? OFFSET ?',
          variables: [
            ...vars,
            Variable.withInt(limit),
            Variable.withInt(offset),
          ],
        )
        .get();
    return results.map((r) => r.data['id'] as int).toList();
  }

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
    final result = await db
        .customSelect(
          'SELECT COUNT(*) as cnt FROM entries WHERE $where',
          variables: vars,
        )
        .getSingle();
    return result.data['cnt'] as int;
  }

  Future<List<String>> getDistinctCefrLevelsForFilter({
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
    if (conditions.isEmpty) return [];
    final where = conditions.join(' OR ');
    final results = await db
        .customSelect(
          "SELECT DISTINCT cefr_level FROM entries WHERE ($where) AND cefr_level != '' ORDER BY cefr_level",
          variables: vars,
        )
        .get();
    return results.map((r) => r.data['cefr_level'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> getFilteredEntriesByCefr(
    String cefrLevel, {
    List<String> cefrLevels = const [],
    bool ox3000 = false,
    bool ox5000 = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final filterConditions = <String>[];
    final vars = <Variable>[];
    for (final level in cefrLevels) {
      filterConditions.add('cefr_level = ?');
      vars.add(Variable.withString(level));
    }
    if (ox3000) filterConditions.add('ox3000 = 1');
    if (ox5000) filterConditions.add('ox5000 = 1');
    if (filterConditions.isEmpty) return [];
    final where = filterConditions.join(' OR ');
    final results = await db
        .customSelect(
          'SELECT * FROM entries WHERE ($where) AND cefr_level = ? ORDER BY headword, entry_index LIMIT ? OFFSET ?',
          variables: [
            ...vars,
            Variable.withString(cefrLevel),
            Variable.withInt(limit),
            Variable.withInt(offset),
          ],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<int> countFilteredEntriesByCefr(
    String cefrLevel, {
    List<String> cefrLevels = const [],
    bool ox3000 = false,
    bool ox5000 = false,
  }) async {
    final filterConditions = <String>[];
    final vars = <Variable>[];
    for (final level in cefrLevels) {
      filterConditions.add('cefr_level = ?');
      vars.add(Variable.withString(level));
    }
    if (ox3000) filterConditions.add('ox3000 = 1');
    if (ox5000) filterConditions.add('ox5000 = 1');
    if (filterConditions.isEmpty) return 0;
    final where = filterConditions.join(' OR ');
    final result = await db
        .customSelect(
          'SELECT COUNT(*) as cnt FROM entries WHERE ($where) AND cefr_level = ?',
          variables: [...vars, Variable.withString(cefrLevel)],
        )
        .getSingle();
    return result.data['cnt'] as int;
  }

  Future<List<String>> getAllAudioFilenames() async {
    final rows = await db.customSelect('''
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
}
