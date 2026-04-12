import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/app_database.dart';

/// Cross-reference data
class XrefInfo {
  final String xrefType;
  final String targetWord;
  XrefInfo({required this.xrefType, required this.targetWord});
}

/// Full entry data loaded from dictionary
class DictEntry {
  final Map<String, dynamic> entry;
  final List<Map<String, dynamic>> pronunciations;
  final List<Map<String, dynamic>> verbForms;
  final List<SenseGroupWithSenses> groups;
  final List<Map<String, dynamic>> synonyms;
  final Map<String, dynamic>? wordOrigin;
  final List<Map<String, dynamic>> wordFamily;
  final List<Map<String, dynamic>> collocations;
  final List<XrefInfo> xrefs;
  final List<Map<String, dynamic>> phrasalVerbs;
  final List<Map<String, dynamic>> extraExamples;
  final List<IdiomEntry> idioms;

  DictEntry({
    required this.entry,
    required this.pronunciations,
    required this.verbForms,
    required this.groups,
    required this.synonyms,
    this.wordOrigin,
    required this.wordFamily,
    required this.collocations,
    required this.xrefs,
    required this.phrasalVerbs,
    required this.extraExamples,
    this.idioms = const [],
  });

  String get headword => entry['headword'] as String? ?? '';
  String get pos => entry['pos'] as String? ?? '';
  String get cefrLevel => entry['cefr_level'] as String? ?? '';
  bool get ox3000 => (entry['ox3000'] as int? ?? 0) == 1;
  bool get ox5000 => (entry['ox5000'] as int? ?? 0) == 1;
  int get id => entry['id'] as int? ?? 0;
}

class SenseGroupWithSenses {
  final Map<String, dynamic> group;
  final List<SenseWithExamples> senses;
  final List<XrefInfo> xrefs;

  SenseGroupWithSenses({
    required this.group,
    required this.senses,
    this.xrefs = const [],
  });

  String get topicEn => group['topic_en'] as String? ?? '';
  String get topicZh => group['topic_zh'] as String? ?? '';
}

class SenseWithExamples {
  final Map<String, dynamic> sense;
  final List<Map<String, dynamic>> examples;
  final List<XrefInfo> xrefs;

  SenseWithExamples({
    required this.sense,
    required this.examples,
    this.xrefs = const [],
  });
}

/// Lightweight idiom data (phrase + senses only)
class IdiomEntry {
  final String phrase;
  final List<SenseGroupWithSenses> groups;

  IdiomEntry({required this.phrase, required this.groups});
}

/// Load full entry data from dictionary DB
Future<DictEntry> loadFullEntry(
  DictionaryDatabase db,
  Map<String, dynamic> entry,
) async {
  final entryId = entry['id'] as int;

  // Fetch all entry-level data in parallel (12 queries -> 1 round-trip)
  final results = await Future.wait([
    db.getPronunciations(entryId), // [0]
    db.getVerbForms(entryId), // [1]
    db.getSenseGroups(entryId), // [2]
    db.getXrefs(entryId), // [3]
    db.getAllSensesForEntry(entryId), // [4]
    db.getAllExamplesForEntry(entryId), // [5]
    db.getSynonyms(entryId), // [6]
    db.getWordFamily(entryId), // [7]
    db.getCollocations(entryId), // [8]
    db.getPhrasalVerbs(entryId), // [9]
    db.getExtraExamples(entryId), // [10]
  ]);
  final wordOrigin = await db.getWordOrigin(entryId);

  final pronunciations = results[0];
  final verbForms = results[1];
  final senseGroupRows = results[2];
  final allXrefRows = results[3];
  final allSenses = results[4];
  final allExamples = results[5];
  final synonyms = results[6];
  final wordFamily = results[7];
  final collocations = results[8];
  final phrasalVerbs = results[9];
  final extraExamples = results[10];

  // Partition xrefs by level
  final senseXrefs = <int, List<XrefInfo>>{};
  final groupXrefs = <int, List<XrefInfo>>{};
  final entryXrefs = <XrefInfo>[];

  for (final xr in allXrefRows) {
    final info = XrefInfo(
      xrefType: xr['xref_type'] as String? ?? '',
      targetWord: xr['target_word'] as String? ?? '',
    );
    final senseId = xr['sense_id'] as int?;
    final groupId = xr['sense_group_id'] as int?;
    if (senseId != null) {
      senseXrefs.putIfAbsent(senseId, () => []).add(info);
    } else if (groupId != null) {
      groupXrefs.putIfAbsent(groupId, () => []).add(info);
    } else {
      entryXrefs.add(info);
    }
  }

  // Group examples by sense_id
  final examplesBySense = <int, List<Map<String, dynamic>>>{};
  for (final ex in allExamples) {
    final sId = ex['sense_id'] as int;
    examplesBySense.putIfAbsent(sId, () => []).add(ex);
  }

  // Group senses by sense_group_id
  final sensesByGroup = <int, List<Map<String, dynamic>>>{};
  for (final s in allSenses) {
    final sgId = s['sense_group_id'] as int;
    sensesByGroup.putIfAbsent(sgId, () => []).add(s);
  }

  // Assemble sense group hierarchy
  final groups = <SenseGroupWithSenses>[];
  for (final sg in senseGroupRows) {
    final sgId = sg['id'] as int;
    final senseRows = sensesByGroup[sgId] ?? [];
    final senses = senseRows.map((s) {
      final sId = s['id'] as int;
      return SenseWithExamples(
        sense: s,
        examples: examplesBySense[sId] ?? [],
        xrefs: senseXrefs[sId] ?? [],
      );
    }).toList();
    groups.add(
      SenseGroupWithSenses(
        group: sg,
        senses: senses,
        xrefs: groupXrefs[sgId] ?? [],
      ),
    );
  }

  // Load idioms (child entries with parent_entry_id = this entry)
  final idiomRows = await db.getIdioms(entryId);
  final idioms = await Future.wait(idiomRows.map((row) async {
    final idiomId = row['id'] as int;
    final results = await Future.wait([
      db.getSenseGroups(idiomId),
      db.getAllSensesForEntry(idiomId),
      db.getAllExamplesForEntry(idiomId),
    ]);
    final idiomSenseGroupRows = results[0];
    final idiomAllSenses = results[1];
    final idiomAllExamples = results[2];

    final idiomExamplesBySense = <int, List<Map<String, dynamic>>>{};
    for (final ex in idiomAllExamples) {
      final sId = ex['sense_id'] as int;
      idiomExamplesBySense.putIfAbsent(sId, () => []).add(ex);
    }

    final idiomSensesByGroup = <int, List<Map<String, dynamic>>>{};
    for (final s in idiomAllSenses) {
      final sgId = s['sense_group_id'] as int;
      idiomSensesByGroup.putIfAbsent(sgId, () => []).add(s);
    }

    final idiomGroups = <SenseGroupWithSenses>[];
    for (final sg in idiomSenseGroupRows) {
      final sgId = sg['id'] as int;
      final senseRows = idiomSensesByGroup[sgId] ?? [];
      idiomGroups.add(SenseGroupWithSenses(
        group: sg,
        senses: senseRows.map((s) {
          final sId = s['id'] as int;
          return SenseWithExamples(
            sense: s,
            examples: idiomExamplesBySense[sId] ?? [],
          );
        }).toList(),
      ));
    }

    return IdiomEntry(
      phrase: row['headword'] as String? ?? '',
      groups: idiomGroups,
    );
  }));

  return DictEntry(
    entry: entry,
    pronunciations: pronunciations,
    verbForms: verbForms,
    groups: groups,
    synonyms: synonyms,
    wordOrigin: wordOrigin,
    wordFamily: wordFamily,
    collocations: collocations,
    xrefs: entryXrefs,
    phrasalVerbs: phrasalVerbs,
    extraExamples: extraExamples,
    idioms: idioms,
  );
}

/// Search query
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

/// Search results: full entries for the query
final searchResultsProvider = FutureProvider<List<DictEntry>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  final db = ref.read(dictionaryDbProvider);

  // 1. Exact match (includes all POS for a word)
  var rows = await db.lookupWord(query);

  // 2. Variant spelling
  if (rows.isEmpty) {
    rows = await db.lookupVariant(query);
  }

  // 3. Fuzzy (suffix stripping)
  if (rows.isEmpty) {
    rows = await db.fuzzyLookup(query);
  }

  // 4. Prefix autocomplete (LIKE)
  if (rows.isEmpty) {
    rows = await db.searchPrefix(query, limit: 15);
    final headwords = <String>{};
    final expanded = <Map<String, dynamic>>[];
    for (final r in rows) {
      final hw = r['headword'] as String;
      if (headwords.add(hw)) {
        expanded.addAll(await db.lookupWord(hw));
      }
    }
    rows = expanded;
  }

  // 5. Fuzzy search (Levenshtein) for typo tolerance
  if (rows.isEmpty && query.length >= 3) {
    rows = await db.fuzzySearch(query, limit: 10, maxDistance: 2);
  }

  // 6. Definition/example FTS search
  if (rows.isEmpty && query.length >= 2) {
    debugPrint('[Search] tier 6: FTS query="$query"');
    rows = await db.searchDefinitions(query, limit: 15);
    debugPrint('[Search] tier 6: ${rows.length} results');
  }

  // Load full entry data in parallel
  return Future.wait(rows.map((row) => loadFullEntry(db, row)));
});

/// Autocomplete suggestions (lightweight - just headwords, no full load)
final autocompleteSuggestionsProvider = FutureProvider<List<String>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  if (query.length < 2) return [];

  final db = ref.read(dictionaryDbProvider);

  // Prefix matches first
  final prefixRows = await db.searchPrefix(query, limit: 8);
  final seen = <String>{};
  final results = prefixRows
      .map((r) => r['headword'] as String)
      .where((hw) => seen.add(hw))
      .toList();

  // If few prefix results and query is 3+ chars, add fuzzy matches
  if (results.length < 3 && query.length >= 3) {
    final fuzzyRows = await db.fuzzySearch(query, limit: 5, maxDistance: 2);
    for (final r in fuzzyRows) {
      final hw = r['headword'] as String;
      if (seen.add(hw) && results.length < 8) {
        results.add(hw);
      }
    }
  }

  return results;
});
