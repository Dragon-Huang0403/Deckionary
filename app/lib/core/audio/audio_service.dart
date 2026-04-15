import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../network/http_retry.dart';

/// Top-level function for compute() — parses a tar archive into filename→bytes
/// pairs. Must be top-level (not a method/closure) to run in a separate isolate.
/// Uses MapEntry instead of records for isolate transferability.
List<MapEntry<String, Uint8List>> _parseTar(Uint8List tarBytes) {
  final files = <MapEntry<String, Uint8List>>[];
  var pos = 0;

  while (pos + 512 <= tarBytes.length) {
    final header = Uint8List.sublistView(tarBytes, pos, pos + 512);
    if (header.every((b) => b == 0)) break;

    // Filename: first 100 bytes, null-terminated
    final nameBytes = Uint8List.sublistView(header, 0, 100);
    var nameEnd = nameBytes.indexOf(0);
    if (nameEnd == -1) nameEnd = 100;
    final filename = String.fromCharCodes(
      Uint8List.sublistView(nameBytes, 0, nameEnd),
    ).trim();

    // File size: bytes 124-136, octal
    final sizeStr = String.fromCharCodes(
      Uint8List.sublistView(header, 124, 136),
    ).replaceAll(RegExp(r'[\x00 ]'), '');
    final fileSize =
        sizeStr.isNotEmpty ? int.tryParse(sizeStr, radix: 8) ?? 0 : 0;

    pos += 512;

    if (filename.isNotEmpty &&
        fileSize > 0 &&
        pos + fileSize <= tarBytes.length) {
      files.add(MapEntry(
        filename,
        Uint8List.sublistView(tarBytes, pos, pos + fileSize),
      ));
    }

    // Advance to next 512-byte boundary
    pos += (fileSize + 511) & ~511;
  }

  return files;
}

/// Local SQLite database for cached audio BLOBs.
/// Same schema as the server's audio_files table.
class AudioDb {
  GeneratedDatabase? _db;
  bool _initialized = false;

  AudioDb();

  /// In-memory DB for tests. Follows UserDatabase.forTesting pattern.
  AudioDb.forTesting(QueryExecutor executor) : _db = _RawDb(executor);

  Future<void> init() async {
    if (_initialized) return;
    if (_db == null) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/audio.db');
      _db = _RawDb(NativeDatabase.createInBackground(file));
    }
    await _createTables();
    _initialized = true;
  }

  Future<void> _createTables() async {
    await _db!.customStatement('''
      CREATE TABLE IF NOT EXISTS audio_files (
        filename TEXT PRIMARY KEY,
        data BLOB NOT NULL
      )
    ''');
    await _db!.customStatement('''
      CREATE TABLE IF NOT EXISTS completed_packs (
        name TEXT PRIMARY KEY
      )
    ''');
    await _db!.customStatement('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<Uint8List?> get(String filename) async {
    await init();
    final rows = await _db!
        .customSelect(
          'SELECT data FROM audio_files WHERE filename = ?',
          variables: [Variable.withString(filename)],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.first.data['data'] as Uint8List;
  }

  Future<void> put(String filename, Uint8List data) async {
    await init();
    await _db!.customInsert(
      'INSERT OR REPLACE INTO audio_files (filename, data) VALUES (?, ?)',
      variables: [Variable.withString(filename), Variable.withBlob(data)],
    );
  }

  /// Insert multiple files in a single transaction.
  Future<void> putBatch(List<(String, Uint8List)> files) async {
    if (files.isEmpty) return;
    await init();
    await _db!.transaction(() async {
      for (final (filename, data) in files) {
        await _db!.customInsert(
          'INSERT OR REPLACE INTO audio_files (filename, data) VALUES (?, ?)',
          variables: [Variable.withString(filename), Variable.withBlob(data)],
        );
      }
    });
  }

  Future<int> fileCount() async {
    await init();
    final row = await _db!
        .customSelect('SELECT COUNT(*) as c FROM audio_files')
        .getSingle();
    return row.data['c'] as int;
  }

  Future<Set<String>> getCachedFilenames() async {
    await init();
    final rows = await _db!
        .customSelect('SELECT filename FROM audio_files')
        .get();
    return rows.map((r) => r.data['filename'] as String).toSet();
  }

  Future<Set<String>> getCompletedPacks() async {
    await init();
    final rows = await _db!
        .customSelect('SELECT name FROM completed_packs')
        .get();
    return rows.map((r) => r.data['name'] as String).toSet();
  }

  Future<void> markPackComplete(String name) async {
    await init();
    await _db!.customInsert(
      'INSERT OR IGNORE INTO completed_packs (name) VALUES (?)',
      variables: [Variable.withString(name)],
    );
  }

  // Hardcoded pack count — must match scripts/export_for_r2.py output.
  // PACK_SIZE=1000, ~257K audio files → 257 tar packs.
  static const totalPacks = 257;

  /// Returns true if all audio packs have been downloaded.
  Future<bool> isDownloadComplete() async {
    await init();
    final row = await _db!
        .customSelect('SELECT COUNT(*) as c FROM completed_packs')
        .getSingle();
    return (row.data['c'] as int) >= totalPacks;
  }

  Future<void> setMeta(String key, String value) async {
    await init();
    await _db!.customInsert(
      'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
      variables: [Variable.withString(key), Variable.withString(value)],
    );
  }

  Future<String?> getMeta(String key) async {
    await init();
    final rows = await _db!
        .customSelect(
          'SELECT value FROM meta WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.first.data['value'] as String;
  }

  Future<void> deleteMeta(String key) async {
    await init();
    await _db!.customUpdate(
      'DELETE FROM meta WHERE key = ?',
      variables: [Variable.withString(key)],
      updates: {},
    );
  }

  Future<void> clear() async {
    await init();
    await _db!.customStatement('DELETE FROM audio_files');
    await _db!.customStatement('DELETE FROM completed_packs');
    await _db!.customStatement('DELETE FROM meta');
    await _db!.customStatement('VACUUM');
  }

  Future<void> close() async {
    if (_initialized) await _db!.close();
  }
}

class _RawDb extends GeneratedDatabase {
  _RawDb(super.e);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {});
}

/// Audio service: plays from local audio.db, fetches from R2 on cache miss.
class AudioService {
  final AudioPlayer _player = AudioPlayer();
  final AudioDb _audioDB;

  static const _r2AudioUrl = '$r2BaseUrl/audio';

  /// Incremented on cancel/clear. Each downloadAll captures its value at start
  /// and stops when stale. Replaces the old boolean flag to prevent race
  /// conditions between cancel, clear, and re-download.
  int _generation = 0;

  void cancelDownload() {
    _generation++;
    debugPrint('[AudioDL] cancel requested, generation=$_generation');
  }

  AudioService({AudioDb? db}) : _audioDB = db ?? AudioDb();

  /// Play audio by filename. Checks local DB first, fetches from API if missing.
  Future<void> play(String filename) async {
    if (filename.isEmpty) return;

    try {
      // Check local audio.db
      var data = await _audioDB.get(filename);

      if (data == null) {
        // Fetch from R2, store in audio.db
        final response = await http.get(Uri.parse('$_r2AudioUrl/$filename'));
        if (response.statusCode == 200) {
          data = response.bodyBytes;
          await _audioDB.put(filename, data);
        } else {
          debugPrint(
            'AudioService: server returned ${response.statusCode} for $filename',
          );
          return;
        }
      }

      // Write to temp file and play (just_audio needs a file path or URL)
      final dir = await getApplicationDocumentsDirectory();
      final tmpFile = File('${dir.path}/_audio_playback.mp3');
      await tmpFile.writeAsBytes(data);
      await _player.setFilePath(tmpFile.path);
      await _player.play();
    } catch (e) {
      debugPrint('AudioService: error $filename: $e');
    }
  }

  /// Play pronunciation for an entry.
  Future<void> playPronunciation(
    List<Map<String, dynamic>> pronunciations, {
    String dialect = 'us',
  }) async {
    if (pronunciations.isEmpty) return;
    final pron =
        pronunciations.where((p) => p['dialect'] == dialect).firstOrNull ??
        pronunciations.first;
    final audioFile = pron['audio_file'] as String? ?? '';
    if (audioFile.isNotEmpty) await play(audioFile);
  }

  // -- Facade methods: hide AudioDb from the notifier --

  Future<bool> wasDownloadRequested() async =>
      await _audioDB.getMeta('download_requested') == '1';

  Future<void> markDownloadRequested() =>
      _audioDB.setMeta('download_requested', '1');

  Future<void> clearDownloadRequested() =>
      _audioDB.deleteMeta('download_requested');

  Future<int> getCompletedPackCount() async =>
      (await _audioDB.getCompletedPacks()).length;

  /// Download all audio via pre-built tar packs from R2.
  /// Fetches manifest, skips completed packs, downloads remaining with a
  /// sliding-window pool. Retries failed packs across multiple rounds.
  Future<void> downloadAll({
    required void Function(
      int completedPacks,
      int totalPacks,
      int filesExtracted,
      int bytesDownloaded,
      int retryRound,
      int failedThisRound,
    )
    onProgress,
    bool Function()? isCancelled,
    http.Client? client,
  }) async {
    final gen = _generation;
    bool stale() => _generation != gen || (isCancelled?.call() ?? false);

    const packsUrl = '$r2BaseUrl/audio-packs';
    final ownClient = client == null;
    final c = client ?? http.Client();

    try {
      final manifestRes = await httpGetWithRetry(
        c,
        Uri.parse('$packsUrl/manifest.json'),
        maxAttempts: 3,
        timeout: const Duration(seconds: 15),
        isCancelled: stale,
      );
      if (manifestRes.statusCode != 200) {
        throw Exception('Failed to fetch manifest: ${manifestRes.statusCode}');
      }
      final manifest = (jsonDecode(manifestRes.body) as List)
          .cast<Map<String, dynamic>>();

      await _audioDB.setMeta('total_packs', manifest.length.toString());

      final initialCompleted = await _audioDB.getCompletedPacks();
      debugPrint(
        '[AudioDL] manifest: ${manifest.length} packs, '
        '${initialCompleted.length} already completed',
      );

      // Fire initial progress so UI shows total packs immediately
      onProgress(initialCompleted.length, manifest.length, 0, 0, 0, 0);

      const maxRounds = 10;
      const roundDelays = [0, 10, 30, 60, 120]; // seconds
      const concurrency = 3;
      var totalFilesExtracted = 0;
      var totalBytesDownloaded = 0;
      var packsCompleted = 0;

      for (var round = 0; round < maxRounds; round++) {
        if (stale()) return;

        final completed = await _audioDB.getCompletedPacks();
        packsCompleted = completed.length;
        final remaining = manifest
            .where((p) => !completed.contains(p['name']))
            .toList();

        debugPrint(
          '[AudioDL] round $round: ${remaining.length} remaining, '
          '$packsCompleted completed',
        );

        if (remaining.isEmpty) {
          onProgress(
            manifest.length,
            manifest.length,
            totalFilesExtracted,
            totalBytesDownloaded,
            round,
            0,
          );
          return;
        }

        // Backoff between retry rounds
        if (round > 0) {
          final delay = roundDelays[round.clamp(0, roundDelays.length - 1)];
          debugPrint(
            'AudioService: round $round, ${remaining.length} packs remaining, '
            'waiting ${delay}s before retry',
          );
          await Future.delayed(Duration(seconds: delay));
          if (stale()) return;
        }

        var failedThisRound = 0;

        await _runPool(
          items: remaining,
          concurrency: concurrency,
          stale: stale,
          process: (pack) async {
            if (stale()) {
              debugPrint('[AudioDL] stale before pack start');
              return;
            }
            final packName = pack['name'] as String;
            final packSw = Stopwatch()..start();
            debugPrint('[AudioDL] pack $packName: downloading...');
            try {
              final res = await httpGetWithRetry(
                c,
                Uri.parse('$packsUrl/$packName'),
                maxAttempts: 3,
                timeout: const Duration(seconds: 120),
                baseDelay: const Duration(seconds: 2),
                isCancelled: stale,
              );
              if (stale()) {
                debugPrint('[AudioDL] pack $packName: stale after download');
                return;
              }
              if (res.statusCode != 200) {
                debugPrint(
                  '[AudioDL] pack $packName: HTTP ${res.statusCode} '
                  '(${packSw.elapsedMilliseconds}ms)',
                );
                failedThisRound++;
              } else {
                debugPrint(
                  '[AudioDL] pack $packName: downloaded '
                  '${res.bodyBytes.length} bytes '
                  '(${packSw.elapsedMilliseconds}ms), extracting...',
                );
                final extractSw = Stopwatch()..start();
                final extracted = await _extractTar(res.bodyBytes);
                extractSw.stop();
                if (stale()) {
                  debugPrint('[AudioDL] pack $packName: stale after extract');
                  return;
                }
                if (extracted == 0) {
                  debugPrint(
                    '[AudioDL] pack $packName: extracted 0 files, skipping',
                  );
                  failedThisRound++;
                } else {
                  debugPrint(
                    '[AudioDL] pack $packName: extracted $extracted files '
                    '(${extractSw.elapsedMilliseconds}ms)',
                  );
                  await _audioDB.markPackComplete(packName);
                  packsCompleted++;
                  totalFilesExtracted += extracted;
                  totalBytesDownloaded += res.bodyBytes.length;
                }
              }
            } catch (e) {
              debugPrint(
                '[AudioDL] pack $packName: error after '
                '${packSw.elapsedMilliseconds}ms: $e',
              );
              failedThisRound++;
            }
            if (!stale()) {
              onProgress(
                packsCompleted,
                manifest.length,
                totalFilesExtracted,
                totalBytesDownloaded,
                round,
                failedThisRound,
              );
            }
          },
        );

        if (stale()) {
          debugPrint('[AudioDL] stale after round $round pool');
          return;
        }
        if (failedThisRound == 0) {
          debugPrint('[AudioDL] round $round: all packs succeeded');
          return;
        }
        debugPrint(
          '[AudioDL] round $round done: $failedThisRound failed, '
          '$packsCompleted/${manifest.length} total completed',
        );
      }

      // Still incomplete after all rounds
      final finalCompleted = await _audioDB.getCompletedPacks();
      final remaining = manifest.length - finalCompleted.length;
      if (remaining > 0) {
        throw Exception(
          '$remaining packs failed after $maxRounds retry rounds',
        );
      }
    } finally {
      if (ownClient) c.close();
    }
  }

  /// Sliding-window concurrency pool. Keeps [concurrency] tasks active at all
  /// times — as soon as one finishes, the next starts. No idle slots.
  static Future<void> _runPool<T>({
    required List<T> items,
    required Future<void> Function(T) process,
    required int concurrency,
    required bool Function() stale,
  }) async {
    final running = <Future<void>>{};
    for (final item in items) {
      if (stale()) return;
      final f = process(item);
      running.add(f);
      f.whenComplete(() => running.remove(f));
      if (running.length >= concurrency) {
        await Future.any(running);
      }
    }
    if (running.isNotEmpty) await Future.wait(running);
  }

  /// Parse tar archive on a background isolate, then batch-insert into audio.db.
  Future<int> _extractTar(Uint8List tarBytes) async {
    final entries = await compute(_parseTar, tarBytes);
    final files = entries
        .map((e) => (e.key, e.value))
        .toList(growable: false);
    await _audioDB.putBatch(files);
    return files.length;
  }

  /// Cached file count from audio.db.
  Future<int> getCachedFileCount() => _audioDB.fileCount();

  /// Whether all audio packs have been downloaded.
  Future<bool> isDownloadComplete() => _audioDB.isDownloadComplete();

  /// Clear all cached audio.
  Future<void> clearCache() async {
    _generation++;
    await _audioDB.clear();
  }

  Future<void> stop() async => await _player.stop();

  void dispose() {
    _player.dispose();
    _audioDB.close();
  }
}
