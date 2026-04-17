import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/features/dictionary/domain/search_service.dart';
import 'package:deckionary/features/dictionary/providers/search_provider.dart';

import '../../../test_helpers.dart';

void main() {
  late DictionaryDatabase db;

  setUpAll(() {
    db = createTestDictDb();
  });

  tearDownAll(() async {
    await db.close();
  });

  // ── 1. lookupWord (exact match) ─────────────────────────────────────────

  group('lookupWord', () {
    test('returns entries for a real word', () async {
      final results = await db.lookupWord('hello');
      expect(results, isNotEmpty);
      expect(results.first['headword'], 'hello');
    });

    test('is case-insensitive', () async {
      final lower = await db.lookupWord('hello');
      final upper = await db.lookupWord('Hello');
      final mixed = await db.lookupWord('HELLO');

      expect(lower, isNotEmpty);
      expect(upper.length, lower.length);
      expect(mixed.length, lower.length);
    });

    test('returns empty for unknown word', () async {
      final results = await db.lookupWord('xyzzyplugh');
      expect(results, isEmpty);
    });
  });

  // ── 2. lookupVariant (variant spelling) ─────────────────────────────────

  group('lookupVariant', () {
    test('"organise" finds "organize" via variant table', () async {
      final results = await db.lookupVariant('organise');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => (r['headword'] as String) == 'organize'),
        isTrue,
        reason: 'Should resolve variant "organise" to headword "organize"',
      );
    });

    test('returns empty for word not in variant table', () async {
      final results = await db.lookupVariant('xyzzyplugh');
      expect(results, isEmpty);
    });
  });

  // ── 3. fuzzyLookup (exact → variant → suffix strip) ─────────────────

  group('fuzzyLookup', () {
    test('"tables" finds "table" via -s strip', () async {
      final results = await db.fuzzyLookup('tables');
      expect(results, isNotEmpty);
      expect(results.any((r) => (r['headword'] as String) == 'table'), isTrue);
    });

    test('"carries" finds "carry" via -ies -> -y', () async {
      final results = await db.fuzzyLookup('carries');
      expect(results, isNotEmpty);
      expect(results.any((r) => (r['headword'] as String) == 'carry'), isTrue);
    });

    test('"danced" finds "dance" via -ed -> -e', () async {
      final results = await db.fuzzyLookup('danced');
      expect(results, isNotEmpty);
      expect(results.any((r) => (r['headword'] as String) == 'dance'), isTrue);
    });

    test('returns exact match if word is itself a headword', () async {
      // "running" is its own headword in OALD
      final results = await db.fuzzyLookup('running');
      expect(results, isNotEmpty);
      expect(results.first['headword'], 'running');
    });
  });

  // ── 3b. suffixStrip ────────────────────────────────────────────────────

  group('suffixStrip', () {
    // -s plural
    test('"tables" → "table"', () async {
      final results = await db.suffixStrip('tables');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'table'), isTrue);
    });

    // -es plural
    test('"churches" → "church"', () async {
      final results = await db.suffixStrip('churches');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'church'), isTrue);
    });

    // -ies → base+"y"
    test('"carries" → "carry"', () async {
      final results = await db.suffixStrip('carries');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'carry'), isTrue);
    });

    // -ied → base+"y"
    test('"tried" → "try"', () async {
      final results = await db.suffixStrip('tried');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'try'), isTrue);
    });

    // -ed + base+"e"
    test('"danced" → "dance"', () async {
      final results = await db.suffixStrip('danced');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'dance'), isTrue);
    });

    // -ed doubled consonant
    test('"stopped" → "stop"', () async {
      final results = await db.suffixStrip('stopped');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'stop'), isTrue);
    });

    // -ing + base+"e"
    test('"evolving" → "evolve"', () async {
      final results = await db.suffixStrip('evolving');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'evolve'), isTrue);
    });

    // -ing doubled consonant
    test('"running" → "run"', () async {
      final results = await db.suffixStrip('running');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'run'), isTrue);
    });

    // -er + base+"e"
    test('"nicer" → "nice"', () async {
      final results = await db.suffixStrip('nicer');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'nice'), isTrue);
    });

    // -er doubled consonant
    test('"bigger" → "big"', () async {
      final results = await db.suffixStrip('bigger');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'big'), isTrue);
    });

    // -or direct
    test('"investor" → "invest"', () async {
      final results = await db.suffixStrip('investor');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'invest'), isTrue);
    });

    // -or + base+"e"
    test('"advisor" → "advise"', () async {
      final results = await db.suffixStrip('advisor');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'advise'), isTrue);
    });

    // -est + base+"e"
    test('"nicest" → "nice"', () async {
      final results = await db.suffixStrip('nicest');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'nice'), isTrue);
    });

    // -est doubled consonant
    test('"biggest" → "big"', () async {
      final results = await db.suffixStrip('biggest');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'big'), isTrue);
    });

    // -ier → base+"y"
    test('"happier" → "happy"', () async {
      final results = await db.suffixStrip('happier');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'happy'), isTrue);
    });

    // -iest → base+"y"
    test('"happiest" → "happy"', () async {
      final results = await db.suffixStrip('happiest');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'happy'), isTrue);
    });

    // -ly direct
    test('"quickly" → "quick"', () async {
      final results = await db.suffixStrip('quickly');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'quick'), isTrue);
    });

    // -ly + base+"e"
    test('"truly" → "true"', () async {
      final results = await db.suffixStrip('truly');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'true'), isTrue);
    });

    // -ly + i→y
    test('"happily" → "happy"', () async {
      final results = await db.suffixStrip('happily');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'happy'), isTrue);
    });

    // -ment
    test('"development" → "develop"', () async {
      final results = await db.suffixStrip('development');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'develop'), isTrue);
    });

    // -ness direct
    test('"kindness" → "kind"', () async {
      final results = await db.suffixStrip('kindness');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'kind'), isTrue);
    });

    // -ness + i→y
    test('"happiness" → "happy"', () async {
      final results = await db.suffixStrip('happiness');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'happy'), isTrue);
    });

    // -less
    test('"hopeless" → "hope"', () async {
      final results = await db.suffixStrip('hopeless');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'hope'), isTrue);
    });

    // -able direct
    test('"washable" → "wash"', () async {
      final results = await db.suffixStrip('washable');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'wash'), isTrue);
    });

    // -able + base+"e"
    test('"lovable" → "love"', () async {
      final results = await db.suffixStrip('lovable');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'love'), isTrue);
    });

    // -ful direct
    test('"hopeful" → "hope"', () async {
      final results = await db.suffixStrip('hopeful');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'hope'), isTrue);
    });

    // -ful + i→y
    test('"beautiful" → "beauty"', () async {
      final results = await db.suffixStrip('beautiful');
      expect(results, isNotEmpty);
      expect(results.any((r) => r['headword'] == 'beauty'), isTrue);
    });

    // No suffix match — base form returns empty
    test('"cat" returns empty (already a base form)', () async {
      final results = await db.suffixStrip('cat');
      expect(results, isEmpty);
    });
  });

  // ── 4. searchPrefix ─────────────────────────────────────────────────────

  group('searchPrefix', () {
    test('"hel" returns entries starting with "hel"', () async {
      final results = await db.searchPrefix('hel', limit: 15);
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(
          (r['headword'] as String).toLowerCase().startsWith('hel'),
          isTrue,
        );
      }
      // Should include common words like "hello", "help"
      final headwords = results.map((r) => r['headword'] as String).toSet();
      expect(headwords, contains('hello'));
      expect(headwords, contains('help'));
    });

    test('empty query returns empty', () async {
      final results = await db.searchPrefix('', limit: 15);
      expect(results, isEmpty);
    });

    test('deduplicates headwords', () async {
      final results = await db.searchPrefix('run', limit: 15);
      final headwords = results.map((r) => r['headword'] as String).toList();
      // Each headword should appear only once (deduplication)
      expect(headwords.toSet().length, headwords.length);
    });
  });

  // ── 5. fuzzySearch (Levenshtein) ────────────────────────────────────────

  group('fuzzySearch', () {
    test('"helo" (typo) finds "hello" within distance 1', () async {
      final results = await db.fuzzySearch('helo', limit: 10, maxDistance: 2);
      expect(results, isNotEmpty);
      expect(
        results.any((r) => (r['headword'] as String) == 'hello'),
        isTrue,
        reason: '"helo" should match "hello" via Levenshtein',
      );
    });

    test('query shorter than 3 chars returns empty', () async {
      final results = await db.fuzzySearch('he', limit: 10, maxDistance: 2);
      expect(results, isEmpty);
    });
  });

  // ── 6. searchDefinitions (FTS) ──────────────────────────────────────────

  group('searchDefinitions', () {
    test('"greeting" returns results with matching definitions', () async {
      final results = await db.searchDefinitions('greeting', limit: 15);
      expect(results, isNotEmpty);
      // "hello" should appear since its definition involves greeting
      final headwords = results.map((r) => r['headword'] as String).toSet();
      expect(
        headwords.contains('hello') || headwords.contains('hi'),
        isTrue,
        reason: 'FTS for "greeting" should find words defined with "greeting"',
      );
    });

    test('empty query returns empty', () async {
      final results = await db.searchDefinitions('', limit: 15);
      expect(results, isEmpty);
    });
  });

  // ── 7. searchEntries (full pipeline) ────────────────────────────────────

  group('searchEntries', () {
    test('exact word "hello" returns headword-match results', () async {
      final results = await searchEntries(db, 'hello');
      expect(results, isNotEmpty);
      // First result should be an exact headword match
      expect(results.first.entry.headword, 'hello');
      expect(results.first.source, SearchMatchSource.headword);
    });

    test('typo "helo" returns results via fuzzy fallback', () async {
      final results = await searchEntries(db, 'helo');
      expect(results, isNotEmpty);
      // Should find "hello" through one of the fallback stages
      expect(
        results.any((r) => r.entry.headword == 'hello'),
        isTrue,
        reason: '"helo" should resolve to "hello" via fuzzy pipeline',
      );
    });

    test('empty query returns empty', () async {
      final results = await searchEntries(db, '');
      expect(results, isEmpty);
    });

    test('definition search appends FTS results', () async {
      // "animal" is a real word AND appears in many definitions.
      // The pipeline should return an exact headword match first,
      // then FTS matches for entries whose definitions mention "animal".
      final results = await searchEntries(db, 'animal');
      expect(results, isNotEmpty);
      // First result: exact headword match
      expect(results.first.entry.headword, 'animal');
      expect(results.first.source, SearchMatchSource.headword);
      // Should also have FTS results appended (definitions containing "animal")
      final ftsResults = results.where(
        (r) => r.source != SearchMatchSource.headword,
      );
      expect(
        ftsResults,
        isNotEmpty,
        reason: 'Should append FTS results for definition matches',
      );
    });

    test('variant spelling resolves via pipeline', () async {
      // "organise" is not a headword, but is a variant of "organize"
      final results = await searchEntries(db, 'organise');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.entry.headword == 'organize'),
        isTrue,
        reason: 'Variant "organise" should resolve to "organize"',
      );
    });

    test('suffix-stripped word resolves correctly', () async {
      // "churches" is not a headword -> strip "es" -> "church"
      final results = await searchEntries(db, 'churches');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.entry.headword == 'church'),
        isTrue,
        reason: '"churches" should resolve to "church" via suffix stripping',
      );
    });
  });

  // ── 8. searchEntries — base form appended ──────────────────────────────

  group('searchEntries — base form appended', () {
    test(
      'inflected headword shows exact match first, then base form',
      () async {
        // "running" is a headword AND suffix-strips to "run"
        final results = await searchEntries(db, 'running');
        expect(results, isNotEmpty);

        final headwords = results
            .where((r) => r.source == SearchMatchSource.headword)
            .map((r) => r.entry.headword)
            .toList();
        expect(
          headwords.first,
          'running',
          reason: 'Exact match should come first',
        );
        expect(
          headwords.contains('run'),
          isTrue,
          reason: 'Base form "run" should be appended',
        );
      },
    );

    test('non-headword inflection shows base form', () async {
      // "evolving" is NOT a headword -> suffix strip finds "evolve"
      final results = await searchEntries(db, 'evolving');
      expect(results, isNotEmpty);
      expect(
        results.any(
          (r) =>
              r.entry.headword == 'evolve' &&
              r.source == SearchMatchSource.headword,
        ),
        isTrue,
        reason: '"evolving" should resolve to "evolve" via suffix stripping',
      );
    });

    test('derivational suffix shows exact match + base form', () async {
      // "development" is a headword AND suffix-strips to "develop"
      final results = await searchEntries(db, 'development');
      expect(results, isNotEmpty);

      final headwords = results
          .where((r) => r.source == SearchMatchSource.headword)
          .map((r) => r.entry.headword)
          .toList();
      expect(
        headwords.first,
        'development',
        reason: 'Exact match should come first',
      );
      expect(
        headwords.contains('develop'),
        isTrue,
        reason: 'Base form "develop" should be appended',
      );
    });

    test('base form with no suffix match shows only itself', () async {
      final results = await searchEntries(db, 'cat');
      expect(results, isNotEmpty);

      final headwordResults = results
          .where((r) => r.source == SearchMatchSource.headword)
          .toList();
      // All headword results should be "cat" entries (different POS)
      for (final r in headwordResults) {
        expect(r.entry.headword, 'cat');
      }
    });
  });
}
