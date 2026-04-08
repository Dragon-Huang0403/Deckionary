import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/app_database.dart';

/// Cross-reference data
class XrefInfo {
  final String xrefType; // "see", "cp", "syn", "opp", etc.
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
  final List<XrefInfo> xrefs; // entry-level only
  final List<Map<String, dynamic>> phrasalVerbs;
  final List<Map<String, dynamic>> extraExamples;

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
  final List<XrefInfo> xrefs; // group-level xrefs

  SenseGroupWithSenses({required this.group, required this.senses, this.xrefs = const []});

  String get topicEn => group['topic_en'] as String? ?? '';
  String get topicZh => group['topic_zh'] as String? ?? '';
}

class SenseWithExamples {
  final Map<String, dynamic> sense;
  final List<Map<String, dynamic>> examples;
  final List<XrefInfo> xrefs; // sense-level xrefs

  SenseWithExamples({required this.sense, required this.examples, this.xrefs = const []});
}

/// Load full entry data from dictionary DB, partitioning xrefs by level
Future<DictEntry> loadFullEntry(DictionaryDatabase db, Map<String, dynamic> entry) async {
  final entryId = entry['id'] as int;

  final pronunciations = await db.getPronunciations(entryId);
  final verbForms = await db.getVerbForms(entryId);
  final senseGroupRows = await db.getSenseGroups(entryId);

  // Load all xrefs at once, partition by level
  final allXrefRows = await db.getXrefs(entryId);
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

  final groups = <SenseGroupWithSenses>[];
  for (final sg in senseGroupRows) {
    final sgId = sg['id'] as int;
    final senseRows = await db.getSenses(sgId);
    final senses = <SenseWithExamples>[];
    for (final s in senseRows) {
      final sId = s['id'] as int;
      final examples = await db.getExamples(sId);
      senses.add(SenseWithExamples(
        sense: s,
        examples: examples,
        xrefs: senseXrefs[sId] ?? [],
      ));
    }
    groups.add(SenseGroupWithSenses(
      group: sg,
      senses: senses,
      xrefs: groupXrefs[sgId] ?? [],
    ));
  }

  final synonyms = await db.getSynonyms(entryId);
  final wordOrigin = await db.getWordOrigin(entryId);
  final wordFamily = await db.getWordFamily(entryId);
  final collocations = await db.getCollocations(entryId);
  final phrasalVerbs = await db.getPhrasalVerbs(entryId);
  final extraExamples = await db.getExtraExamples(entryId);

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
  );
}

/// Search query notifier
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

final searchResultsProvider = FutureProvider<List<DictEntry>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  final db = ref.read(dictionaryDbProvider);

  var rows = await db.fuzzyLookup(query);
  if (rows.isEmpty) {
    rows = await db.searchPrefix(query, limit: 20);
  }

  final entries = <DictEntry>[];
  for (final row in rows) {
    entries.add(await loadFullEntry(db, row));
  }
  return entries;
});
