import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:deckionary/core/audio/audio_service.dart';
import 'package:deckionary/core/network/http_retry.dart';

AudioDb createTestAudioDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AudioDb.forTesting(NativeDatabase.memory());
}

/// Build a minimal valid tar archive containing [files].
Uint8List buildTar(Map<String, Uint8List> files) {
  final chunks = <int>[];
  for (final entry in files.entries) {
    final header = Uint8List(512);
    final nameBytes = utf8.encode(entry.key);
    header.setRange(0, nameBytes.length, nameBytes);
    final sizeOctal = entry.value.length.toRadixString(8).padLeft(11, '0');
    final sizeBytes = utf8.encode(sizeOctal);
    header.setRange(124, 124 + sizeBytes.length, sizeBytes);
    chunks.addAll(header);
    chunks.addAll(entry.value);
    final remainder = entry.value.length % 512;
    if (remainder > 0) chunks.addAll(Uint8List(512 - remainder));
  }
  chunks.addAll(Uint8List(1024)); // end-of-archive marker
  return Uint8List.fromList(chunks);
}

String buildManifest(List<String> packNames) =>
    jsonEncode(packNames.map((n) => {'name': n}).toList());

/// Mock HTTP client serving a manifest + pack tars with optional timing gates.
http.Client createFakeClient({
  required List<String> packNames,
  required Map<String, Uint8List> packContents,
  Map<String, Completer<void>>? packGates,
}) {
  final manifest = buildManifest(packNames);
  return http_testing.MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('manifest.json')) {
      return http.Response(manifest, 200);
    }
    final packName = path.split('/').last;
    final content = packContents[packName];
    if (content == null) return http.Response('Not found', 404);
    if (packGates != null && packGates.containsKey(packName)) {
      await packGates[packName]!.future;
    }
    return http.Response.bytes(content, 200);
  });
}

void _noop(int a, int b, int c, int d, int e, int f) {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---- AudioDb baseline tests ----

  group('AudioDb', () {
    late AudioDb db;

    setUp(() async {
      db = createTestAudioDb();
      await db.init();
    });

    tearDown(() => db.close());

    test('put and get round-trip', () async {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      await db.put('test.mp3', data);
      final result = await db.get('test.mp3');
      expect(result, data);
    });

    test('get returns null for missing file', () async {
      expect(await db.get('missing.mp3'), isNull);
    });

    test('putBatch inserts multiple files', () async {
      await db.putBatch([
        ('a.mp3', Uint8List.fromList([1])),
        ('b.mp3', Uint8List.fromList([2])),
      ]);
      expect(await db.fileCount(), 2);
      expect(await db.get('a.mp3'), Uint8List.fromList([1]));
    });

    test('markPackComplete and getCompletedPacks', () async {
      await db.markPackComplete('pack_00.tar');
      await db.markPackComplete('pack_01.tar');
      await db.markPackComplete('pack_01.tar'); // duplicate — ignored
      final packs = await db.getCompletedPacks();
      expect(packs, {'pack_00.tar', 'pack_01.tar'});
    });

    test('clear removes all data', () async {
      await db.put('test.mp3', Uint8List.fromList([1]));
      await db.markPackComplete('pack_00.tar');
      await db.setMeta('key', 'value');
      await db.clear();
      expect(await db.fileCount(), 0);
      expect(await db.getCompletedPacks(), isEmpty);
      expect(await db.getMeta('key'), isNull);
    });
  });

  // ---- Facade methods ----

  group('AudioService facade', () {
    late AudioDb db;
    late AudioService service;

    setUp(() async {
      db = createTestAudioDb();
      await db.init();
      service = AudioService(db: db);
    });

    tearDown(() => db.close());

    test('wasDownloadRequested / markDownloadRequested / clear', () async {
      expect(await service.wasDownloadRequested(), isFalse);
      await service.markDownloadRequested();
      expect(await service.wasDownloadRequested(), isTrue);
      await service.clearDownloadRequested();
      expect(await service.wasDownloadRequested(), isFalse);
    });

    test('getCompletedPackCount', () async {
      expect(await service.getCompletedPackCount(), 0);
      await db.markPackComplete('pack_00.tar');
      await db.markPackComplete('pack_01.tar');
      expect(await service.getCompletedPackCount(), 2);
    });
  });

  // ---- Bug 6: pack with 0 files not marked complete ----

  group('Bug 6: extraction validation', () {
    late AudioDb db;
    late AudioService service;

    setUp(() async {
      db = createTestAudioDb();
      await db.init();
      service = AudioService(db: db);
    });

    tearDown(() => db.close());

    test('pack with invalid content is not marked complete', () async {
      final badContent = Uint8List.fromList(utf8.encode('<html>Error</html>'));
      final client = createFakeClient(
        packNames: ['pack_00.tar'],
        packContents: {'pack_00.tar': badContent},
      );

      var gotProgress = false;
      // Cancel after first progress to avoid retry delays
      await service.downloadAll(
        client: client,
        onProgress: (a, b, c, d, e, failed) {
          gotProgress = true;
        },
        isCancelled: () => gotProgress,
      );

      expect(await db.getCompletedPacks(), isEmpty);
    });

    test('pack with valid tar content is marked complete', () async {
      final tar = buildTar({
        'hello.mp3': Uint8List.fromList([1, 2, 3]),
      });
      final client = createFakeClient(
        packNames: ['pack_00.tar'],
        packContents: {'pack_00.tar': tar},
      );

      await service.downloadAll(client: client, onProgress: _noop);

      expect(await db.getCompletedPacks(), {'pack_00.tar'});
      expect(await db.get('hello.mp3'), Uint8List.fromList([1, 2, 3]));
    });
  });

  // ---- Bug 1: stale download skips DB writes after clear ----

  group('Bug 1: clear during download', () {
    test('in-flight downloads do not write after clearCache', () async {
      final db = createTestAudioDb();
      await db.init();
      final service = AudioService(db: db);

      final tar = buildTar({
        'audio.mp3': Uint8List.fromList([1, 2, 3]),
      });
      final gate = Completer<void>();
      final client = createFakeClient(
        packNames: ['pack_00.tar', 'pack_01.tar'],
        packContents: {'pack_00.tar': tar, 'pack_01.tar': tar},
        packGates: {'pack_01.tar': gate},
      );

      final downloadFuture = service.downloadAll(
        client: client,
        onProgress: _noop,
      );

      // Wait for pack_00 to complete, pack_01 blocked at gate
      await Future.delayed(const Duration(milliseconds: 50));

      // Clear while pack_01 is in-flight — increments generation
      await service.clearCache();

      // Release pack_01
      gate.complete();
      await downloadFuture;

      // DB should be empty — pack_01's write skipped due to stale generation
      expect(await db.fileCount(), 0);
      expect(await db.getCompletedPacks(), isEmpty);

      await db.close();
    });
  });

  // ---- Bug 4: cancel + re-download race ----

  group('Bug 4: cancel + re-download', () {
    test('old download stops when generation changes', () async {
      final db = createTestAudioDb();
      await db.init();
      final service = AudioService(db: db);

      final tar = buildTar({
        'a.mp3': Uint8List.fromList([1]),
      });
      final gate = Completer<void>();
      final client = createFakeClient(
        packNames: ['pack_00.tar'],
        packContents: {'pack_00.tar': tar},
        packGates: {'pack_00.tar': gate},
      );

      final first = service.downloadAll(client: client, onProgress: _noop);
      await Future.delayed(const Duration(milliseconds: 20));

      // Cancel — increments generation
      service.cancelDownload();
      gate.complete();
      await first;

      // Pack should NOT be marked complete — generation changed
      expect(await db.getCompletedPacks(), isEmpty);

      await db.close();
    });

    test('new download completes independently after cancel', () async {
      final db = createTestAudioDb();
      await db.init();
      final service = AudioService(db: db);

      final tar = buildTar({
        'a.mp3': Uint8List.fromList([1]),
      });

      // First download: cancelled mid-flight
      final gate = Completer<void>();
      final client1 = createFakeClient(
        packNames: ['pack_00.tar'],
        packContents: {'pack_00.tar': tar},
        packGates: {'pack_00.tar': gate},
      );
      final first = service.downloadAll(client: client1, onProgress: _noop);
      await Future.delayed(const Duration(milliseconds: 20));
      service.cancelDownload();
      gate.complete();
      await first;

      // Second download: should complete normally
      final client2 = createFakeClient(
        packNames: ['pack_00.tar'],
        packContents: {'pack_00.tar': tar},
      );
      await service.downloadAll(client: client2, onProgress: _noop);

      expect(await db.getCompletedPacks(), {'pack_00.tar'});
      expect(await db.get('a.mp3'), isNotNull);

      await db.close();
    });
  });

  // ---- Bug 7: sliding window pool ----

  group('Bug 7: sliding window pool', () {
    test('pool fills idle slots immediately', () async {
      final db = createTestAudioDb();
      await db.init();
      final service = AudioService(db: db);

      final tar = buildTar({
        'x.mp3': Uint8List.fromList([1]),
      });
      final slowGate = Completer<void>();
      final completionOrder = <String>[];

      final client = http_testing.MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('manifest.json')) {
          return http.Response(
            buildManifest(['pack_00.tar', 'pack_01.tar', 'pack_02.tar']),
            200,
          );
        }
        final packName = path.split('/').last;
        if (packName == 'pack_00.tar') await slowGate.future;
        completionOrder.add(packName);
        return http.Response.bytes(tar, 200);
      });

      final downloadFuture = service.downloadAll(
        client: client,
        onProgress: _noop,
      );

      // Let fast packs complete
      await Future.delayed(const Duration(milliseconds: 50));

      // pack_01 and pack_02 completed before pack_00 (no idle waiting)
      expect(completionOrder, containsAll(['pack_01.tar', 'pack_02.tar']));
      expect(completionOrder, isNot(contains('pack_00.tar')));

      slowGate.complete();
      await downloadFuture;

      expect(completionOrder, contains('pack_00.tar'));
      expect(await db.getCompletedPacks(), hasLength(3));

      await db.close();
    });
  });

  // ---- Initial progress fires immediately ----

  group('Initial progress', () {
    test('onProgress fires with totalPacks before any pack completes',
        () async {
      final db = createTestAudioDb();
      await db.init();
      final service = AudioService(db: db);

      final tar = buildTar({'a.mp3': Uint8List.fromList([1])});
      final gate = Completer<void>();
      final client = createFakeClient(
        packNames: ['pack_00.tar'],
        packContents: {'pack_00.tar': tar},
        packGates: {'pack_00.tar': gate},
      );

      final progressCalls = <(int, int)>[];
      final downloadFuture = service.downloadAll(
        client: client,
        onProgress: (completed, total, _, __, ___, ____) {
          progressCalls.add((completed, total));
        },
      );

      // Wait for manifest fetch + initial progress, but pack is still blocked
      await Future.delayed(const Duration(milliseconds: 50));

      // Should have initial progress with totalPacks before any pack completes
      expect(progressCalls, isNotEmpty);
      expect(progressCalls.first.$1, 0); // 0 completed
      expect(progressCalls.first.$2, 1); // 1 total pack

      gate.complete();
      await downloadFuture;
      await db.close();
    });

    test('initial progress shows already-completed pack count', () async {
      final db = createTestAudioDb();
      await db.init();
      // Pre-mark one pack as complete
      await db.markPackComplete('pack_00.tar');
      final service = AudioService(db: db);

      final tar = buildTar({'b.mp3': Uint8List.fromList([2])});
      final client = createFakeClient(
        packNames: ['pack_00.tar', 'pack_01.tar'],
        packContents: {'pack_00.tar': tar, 'pack_01.tar': tar},
      );

      final progressCalls = <(int, int)>[];
      await service.downloadAll(
        client: client,
        onProgress: (completed, total, _, __, ___, ____) {
          progressCalls.add((completed, total));
        },
      );

      // First progress call should show 1 already completed out of 2
      expect(progressCalls.first.$1, 1);
      expect(progressCalls.first.$2, 2);
      await db.close();
    });
  });

  // ---- httpGetWithRetry cancellation ----

  group('httpGetWithRetry', () {
    test('throws CancelledException when cancelled before attempt', () async {
      final client = http_testing.MockClient(
        (_) async => http.Response('ok', 200),
      );

      await expectLater(
        httpGetWithRetry(
          client,
          Uri.parse('https://example.com/test'),
          isCancelled: () => true,
        ),
        throwsA(isA<CancelledException>()),
      );
    });

    test('retries on 500 and returns last response', () async {
      var attempts = 0;
      final client = http_testing.MockClient((_) async {
        attempts++;
        return http.Response('error', 500);
      });

      final res = await httpGetWithRetry(
        client,
        Uri.parse('https://example.com/test'),
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 1),
        maxBackoff: const Duration(milliseconds: 5),
      );

      expect(res.statusCode, 500);
      expect(attempts, 3);
    });

    test('retries on transient network errors', () async {
      var attempts = 0;
      final client = http_testing.MockClient((_) async {
        attempts++;
        if (attempts < 3) {
          throw const SocketException('Connection refused');
        }
        return http.Response('ok', 200);
      });

      final res = await httpGetWithRetry(
        client,
        Uri.parse('https://example.com/test'),
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 1),
        maxBackoff: const Duration(milliseconds: 5),
      );

      expect(res.statusCode, 200);
      expect(attempts, 3);
    });

    test('does not retry 4xx errors', () async {
      var attempts = 0;
      final client = http_testing.MockClient((_) async {
        attempts++;
        return http.Response('not found', 404);
      });

      final res = await httpGetWithRetry(
        client,
        Uri.parse('https://example.com/test'),
        maxAttempts: 3,
      );

      expect(res.statusCode, 404);
      expect(attempts, 1);
    });

    test('cancellation stops retries between attempts', () async {
      var attempts = 0;
      var cancelled = false;
      final client = http_testing.MockClient((_) async {
        attempts++;
        return http.Response('error', 500);
      });

      await expectLater(
        httpGetWithRetry(
          client,
          Uri.parse('https://example.com/test'),
          maxAttempts: 5,
          baseDelay: const Duration(milliseconds: 1),
          maxBackoff: const Duration(milliseconds: 5),
          isCancelled: () {
            // Cancel after first attempt completes
            if (attempts >= 1) cancelled = true;
            return cancelled;
          },
        ),
        throwsA(isA<CancelledException>()),
      );
      // Should have only made 1 attempt, then cancelled before attempt 2
      expect(attempts, 1);
    });
  });

  // ---- Circuit breaker ----

  group('Circuit breaker', () {
    test('stops pool after 5 consecutive failures', () async {
      final db = createTestAudioDb();
      await db.init();
      final service = AudioService(db: db);

      // 20 packs, all fail instantly with 404 (no retries for 4xx)
      final packNames = List.generate(
        20,
        (i) => 'pack_${i.toString().padLeft(2, '0')}.tar',
      );
      final attemptedPacks = <String>[];
      final client = http_testing.MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          return http.Response(buildManifest(packNames), 200);
        }
        attemptedPacks.add(request.url.path.split('/').last);
        // 404 = no retries, fails fast
        return http.Response('not found', 404);
      });

      // Cancel after first round to avoid retry delays
      var roundSeen = false;
      await service.downloadAll(
        client: client,
        onProgress: (_, __, ___, ____, round, ______) {
          if (round > 0) roundSeen = true;
        },
        isCancelled: () => roundSeen,
      );

      // Circuit breaker trips at 5 consecutive failures. With concurrency and
      // instant mock responses, some extra packs may be dispatched before the
      // stale check runs. Without the circuit breaker, all 20 would be attempted.
      expect(attemptedPacks.length, greaterThanOrEqualTo(5));
      expect(attemptedPacks.length, lessThan(15));
      await db.close();
    });

    test('circuit breaker resets on success', () async {
      final db = createTestAudioDb();
      await db.init();
      final service = AudioService(db: db);

      final tar = buildTar({'a.mp3': Uint8List.fromList([1])});
      // 12 packs, all fail with 404 (fast, no retries) except pack_04
      // which succeeds. With concurrency 3, pack_04 resets the counter.
      // Without the reset, 5 consecutive failures would trip the breaker
      // and later packs would never be attempted.
      final packNames = List.generate(
        12,
        (i) => 'pack_${i.toString().padLeft(2, '0')}.tar',
      );
      final attemptedPacks = <String>[];
      final client = http_testing.MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          return http.Response(buildManifest(packNames), 200);
        }
        final name = request.url.path.split('/').last;
        attemptedPacks.add(name);
        if (name == 'pack_04.tar') {
          return http.Response.bytes(tar, 200);
        }
        return http.Response('not found', 404);
      });

      var cancelAfterRound0 = false;
      await service.downloadAll(
        client: client,
        onProgress: (_, __, ___, ____, round, ______) {
          if (round > 0) cancelAfterRound0 = true;
        },
        isCancelled: () => cancelAfterRound0,
      );

      // pack_04 succeeded — if the reset works, packs after pack_04 are
      // also attempted. Without reset, circuit would trip at pack_04's
      // neighbors and later packs would be skipped.
      expect(await db.getCompletedPacks(), contains('pack_04.tar'));
      // At least some packs after pack_04 were attempted (proves reset worked)
      expect(
        attemptedPacks.where((p) => int.parse(p.substring(5, 7)) > 4),
        isNotEmpty,
      );
      await db.close();
    });
  });

  // ---- Resume download ----

  group('Resume download', () {
    test('skips already-completed packs', () async {
      final db = createTestAudioDb();
      await db.init();
      await db.markPackComplete('pack_00.tar');
      final service = AudioService(db: db);

      final tar = buildTar({'b.mp3': Uint8List.fromList([2])});
      final downloadedPacks = <String>[];
      final client = http_testing.MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          return http.Response(
            buildManifest(['pack_00.tar', 'pack_01.tar']),
            200,
          );
        }
        downloadedPacks.add(request.url.path.split('/').last);
        return http.Response.bytes(tar, 200);
      });

      await service.downloadAll(client: client, onProgress: _noop);

      // Only pack_01 should have been downloaded
      expect(downloadedPacks, ['pack_01.tar']);
      expect(await db.getCompletedPacks(), {'pack_00.tar', 'pack_01.tar'});
      await db.close();
    });
  });
}
