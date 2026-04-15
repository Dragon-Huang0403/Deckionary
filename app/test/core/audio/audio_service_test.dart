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

  // ---- extractTarFile ----

  group('extractTarFile', () {
    late AudioDb db;
    late AudioService service;
    late Directory tmpDir;

    setUp(() async {
      db = createTestAudioDb();
      await db.init();
      service = AudioService(db: db);
      tmpDir = await Directory.systemTemp.createTemp('audio_test_');
    });

    tearDown(() async {
      await db.close();
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('extracts valid tar and inserts into AudioDb', () async {
      final tar = buildTar({
        'hello.mp3': Uint8List.fromList([1, 2, 3]),
        'world.mp3': Uint8List.fromList([4, 5]),
      });
      final tarFile = File('${tmpDir.path}/pack_00.tar');
      await tarFile.writeAsBytes(tar);

      final count = await service.extractTarFile(tarFile.path);

      expect(count, 2);
      expect(await db.get('hello.mp3'), Uint8List.fromList([1, 2, 3]));
      expect(await db.get('world.mp3'), Uint8List.fromList([4, 5]));
      expect(
        tarFile.existsSync(),
        isFalse,
        reason: 'tar file should be deleted after extraction',
      );
    });

    test('returns 0 for invalid tar content', () async {
      final badContent = Uint8List.fromList(utf8.encode('<html>Error</html>'));
      final tarFile = File('${tmpDir.path}/bad.tar');
      await tarFile.writeAsBytes(badContent);

      final count = await service.extractTarFile(tarFile.path);

      expect(count, 0);
      expect(await db.fileCount(), 0);
      expect(
        tarFile.existsSync(),
        isFalse,
        reason: 'tar file should be deleted even on failure',
      );
    });

    test('returns 0 for empty tar', () async {
      final emptyTar = Uint8List(1024); // just end-of-archive marker
      final tarFile = File('${tmpDir.path}/empty.tar');
      await tarFile.writeAsBytes(emptyTar);

      final count = await service.extractTarFile(tarFile.path);

      expect(count, 0);
      expect(await db.fileCount(), 0);
    });
  });

  // ---- httpGetWithRetry ----

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
}
