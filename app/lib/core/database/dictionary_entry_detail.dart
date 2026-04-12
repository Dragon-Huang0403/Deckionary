import 'package:drift/drift.dart';
import 'app_database.dart';

extension DictionaryEntryDetail on DictionaryDatabase {
  Future<List<Map<String, dynamic>>> getPronunciations(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM pronunciations WHERE entry_id = ?',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getVerbForms(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM verb_forms WHERE entry_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSenseGroups(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM sense_groups WHERE entry_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSenses(int senseGroupId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM senses WHERE sense_group_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(senseGroupId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getExamples(int senseId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM examples WHERE sense_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(senseId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getAllSensesForEntry(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM senses WHERE entry_id = ? ORDER BY sense_group_id, sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getAllExamplesForEntry(int entryId) async {
    final results = await db
        .customSelect(
          '''SELECT ex.* FROM examples ex
         JOIN senses s ON ex.sense_id = s.id
         WHERE s.entry_id = ?
         ORDER BY ex.sense_id, ex.sort_order''',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSynonyms(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM synonyms WHERE entry_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<Map<String, dynamic>?> getWordOrigin(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM word_origins WHERE entry_id = ?',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.isEmpty ? null : results.first.data;
  }

  Future<List<Map<String, dynamic>>> getWordFamily(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM word_family WHERE entry_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getCollocations(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM collocations WHERE entry_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getXrefs(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM xrefs WHERE entry_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getPhrasalVerbs(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM phrasal_verbs WHERE entry_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getExtraExamples(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM extra_examples WHERE entry_id = ? ORDER BY sort_order',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> getIdioms(int entryId) async {
    final results = await db
        .customSelect(
          'SELECT * FROM entries WHERE parent_entry_id = ? ORDER BY entry_index',
          variables: [Variable.withInt(entryId)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }
}
