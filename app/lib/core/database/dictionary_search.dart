import 'package:drift/drift.dart';
import 'app_database.dart';

int levenshtein(String s, String t) {
  if (s == t) return 0;
  if (s.isEmpty) return t.length;
  if (t.isEmpty) return s.length;

  List<int> prev = List.generate(t.length + 1, (i) => i);
  List<int> curr = List.filled(t.length + 1, 0);

  for (var i = 0; i < s.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < t.length; j++) {
      final cost = s.codeUnitAt(i) == t.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = [
        curr[j] + 1,
        prev[j + 1] + 1,
        prev[j] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[t.length];
}

extension DictionarySearch on DictionaryDatabase {
  /// Fuzzy search using Levenshtein distance.
  /// Only runs when prefix search returns no results.
  Future<List<Map<String, dynamic>>> fuzzySearch(
    String query, {
    int limit = 10,
    int maxDistance = 2,
  }) async {
    final q = query.toLowerCase().trim();
    if (q.length < 3) return [];

    final words = await headwords;

    final candidates = <(String, int)>[];
    for (final w in words) {
      if ((w.length - q.length).abs() > maxDistance) continue;
      final d = levenshtein(q, w.toLowerCase());
      if (d <= maxDistance) {
        candidates.add((w, d));
      }
    }
    candidates.sort((a, b) => a.$2.compareTo(b.$2));

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

  /// Autocomplete: prefix match on headwords, prioritizing shorter/exact matches.
  Future<List<Map<String, dynamic>>> searchPrefix(
    String query, {
    int limit = 20,
  }) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    final results = await db
        .customSelect(
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
            Variable.withInt(limit * 3),
          ],
        )
        .get();

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
  Future<List<Map<String, dynamic>>> searchFts(
    String query, {
    int limit = 20,
  }) async {
    final results = await db
        .customSelect(
          '''SELECT e.* FROM entries_fts fts
         JOIN entries e ON e.id = fts.rowid
         WHERE fts.headword MATCH ?
         LIMIT ?''',
          variables: [Variable.withString('"$query"'), Variable.withInt(limit)],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  /// Search definitions and examples via FTS5.
  /// Returns entry rows ranked by BM25 relevance
  /// (headword > definition > example).
  Future<List<Map<String, dynamic>>> searchDefinitions(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // Sanitize: quote each token to prevent FTS5 syntax injection
    final sanitized = q
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '"${w.replaceAll('"', '')}"')
        .join(' ');
    if (sanitized.isEmpty) return [];

    try {
      final results = await db
          .customSelect(
            '''SELECT e.* FROM dictionary_fts fts
           JOIN entries e ON e.id = fts.rowid
           WHERE dictionary_fts MATCH ?
           ORDER BY bm25(dictionary_fts, 10.0, 5.0, 1.0)
           LIMIT ?''',
            variables: [
              Variable.withString(sanitized),
              Variable.withInt(limit),
            ],
          )
          .get();
      return results.map((r) => r.data).toList();
    } catch (_) {
      return []; // graceful fallback on malformed queries
    }
  }

  Future<List<Map<String, dynamic>>> lookupWord(String headword) async {
    final results = await db
        .customSelect(
          'SELECT * FROM entries WHERE headword = ? ORDER BY entry_index',
          variables: [Variable.withString(headword.toLowerCase().trim())],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> lookupVariant(String headword) async {
    final results = await db
        .customSelect(
          '''SELECT e.* FROM entries e
         JOIN variants v ON v.entry_id = e.id
         WHERE v.variant = ?
         ORDER BY e.entry_index''',
          variables: [Variable.withString(headword.toLowerCase().trim())],
        )
        .get();
    return results.map((r) => r.data).toList();
  }

  /// Strip common English suffixes to find the base/root headword.
  Future<List<Map<String, dynamic>>> suffixStrip(String headword) async {
    final key = headword.toLowerCase().trim();
    List<Map<String, dynamic>> results;

    const suffixes = [
      'iest', 'ier', 'ies', 'ied', // y-form inflections
      'ment', 'ness', 'less', 'able', // derivational
      'ing', 'ful', 'est', // inflectional
      'ed', 'er', 'or', 'es', 'ly', 's', // short suffixes
    ];
    for (final suffix in suffixes) {
      if (!key.endsWith(suffix)) continue;
      final base = key.substring(0, key.length - suffix.length);
      if (base.isEmpty) continue;

      // Direct base lookup
      results = await lookupWord(base);
      if (results.isNotEmpty) return results;

      // base+"y": ies/ied/ier/iest (tries→try, happier→happy)
      if (const {'ies', 'ied', 'ier', 'iest'}.contains(suffix)) {
        results = await lookupWord('${base}y');
        if (results.isNotEmpty) return results;
      }

      // base+"e": ed/ing/er/or/est/ly/able (evolving→evolve, advisor→advise)
      if (const {
        'ed',
        'ing',
        'er',
        'or',
        'est',
        'ly',
        'able',
      }.contains(suffix)) {
        results = await lookupWord('${base}e');
        if (results.isNotEmpty) return results;
      }

      // i→y: ly/ness/ful (happily→happy, happiness→happy, beautiful→beauty)
      if (const {'ly', 'ness', 'ful'}.contains(suffix) && base.endsWith('i')) {
        results = await lookupWord('${base.substring(0, base.length - 1)}y');
        if (results.isNotEmpty) return results;
      }

      // Doubled consonant: ing/ed/er/est (running→run, stopped→stop)
      if (const {'ing', 'ed', 'er', 'est'}.contains(suffix) &&
          base.length >= 2 &&
          base[base.length - 1] == base[base.length - 2]) {
        results = await lookupWord(base.substring(0, base.length - 1));
        if (results.isNotEmpty) return results;
      }
    }
    return [];
  }

  /// Lookup with exact match, variant, then suffix stripping fallback.
  Future<List<Map<String, dynamic>>> fuzzyLookup(String headword) async {
    final key = headword.toLowerCase().trim();
    var results = await lookupWord(key);
    if (results.isNotEmpty) return results;
    results = await lookupVariant(key);
    if (results.isNotEmpty) return results;
    return suffixStrip(key);
  }
}
