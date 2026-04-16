import '../providers/search_provider.dart';
import '../../../core/database/database_provider.dart';

/// Standalone search pipeline — usable from both Riverpod providers and
/// non-provider contexts (e.g. LookupSheetController).
Future<List<SearchResult>> searchEntries(
  DictionaryDatabase db,
  String query,
) async {
  if (query.isEmpty) return [];

  // 1. Exact match (includes all POS for a word)
  var rows = await db.lookupWord(query);

  // 2. Variant spelling
  if (rows.isEmpty) {
    rows = await db.lookupVariant(query);
  }

  // 3. Suffix strip — always run, append base form after exact/variant match
  final baseRows = await db.suffixStrip(query);
  if (baseRows.isNotEmpty) {
    final existingIds = rows.map((r) => r['id'] as int).toSet();
    rows.addAll(baseRows.where((r) => !existingIds.contains(r['id'])));
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

  // Load headword-match entries
  final headwordIds = rows.map((r) => r['id'] as int).toSet();
  final entries = await Future.wait(rows.map((row) => loadFullEntry(db, row)));
  final results = entries.map((e) => SearchResult(e)).toList();

  // Always append FTS results (definitions/examples) if query is 2+ chars
  if (query.length >= 2) {
    final ftsRows = await db.searchDefinitions(query, limit: 15);
    final newFtsRows = ftsRows
        .where((r) => !headwordIds.contains(r['id'] as int))
        .toList();
    if (newFtsRows.isNotEmpty) {
      final ftsEntries = await Future.wait(
        newFtsRows.map((row) => loadFullEntry(db, row)),
      );
      results.addAll(ftsEntries.map((e) => buildFtsResult(e, query)));
    }
  }

  return results;
}

/// Find the best matching snippet for a FTS result.
SearchResult buildFtsResult(DictEntry entry, String query) {
  final q = query.toLowerCase();
  // Check definitions first
  for (final group in entry.groups) {
    for (final sense in group.senses) {
      final def = sense.sense['definition'] as String? ?? '';
      if (def.toLowerCase().contains(q)) {
        return SearchResult(
          entry,
          source: SearchMatchSource.definition,
          snippet: def,
        );
      }
    }
  }
  // Check examples
  for (final group in entry.groups) {
    for (final sense in group.senses) {
      for (final ex in sense.examples) {
        final text = ex['text_plain'] as String? ?? '';
        if (text.toLowerCase().contains(q)) {
          return SearchResult(
            entry,
            source: SearchMatchSource.example,
            snippet: text,
          );
        }
      }
    }
  }
  // Fallback: first definition
  final firstDef =
      entry.groups.firstOrNull?.senses.firstOrNull?.sense['definition']
          as String? ??
      '';
  return SearchResult(
    entry,
    source: SearchMatchSource.definition,
    snippet: firstDef,
  );
}
