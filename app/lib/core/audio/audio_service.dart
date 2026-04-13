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

/// Local SQLite database for cached audio BLOBs.
/// Same schema as the server's audio_files table.
class AudioDb {
  late final GeneratedDatabase _db;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/audio.db');
    _db = _RawDb(NativeDatabase(file));
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS audio_files (
        filename TEXT PRIMARY KEY,
        data BLOB NOT NULL
      )
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS completed_packs (
        name TEXT PRIMARY KEY
      )
    ''');
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    _initialized = true;
  }

  Future<Uint8List?> get(String filename) async {
    await init();
    final rows = await _db
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
    await _db.customInsert(
      'INSERT OR REPLACE INTO audio_files (filename, data) VALUES (?, ?)',
      variables: [Variable.withString(filename), Variable.withBlob(data)],
    );
  }

  /// Insert multiple files in a single transaction.
  Future<void> putBatch(List<(String, Uint8List)> files) async {
    if (files.isEmpty) return;
    await init();
    await _db.transaction(() async {
      for (final (filename, data) in files) {
        await _db.customInsert(
          'INSERT OR REPLACE INTO audio_files (filename, data) VALUES (?, ?)',
          variables: [Variable.withString(filename), Variable.withBlob(data)],
        );
      }
    });
  }

  Future<int> fileCount() async {
    await init();
    final row = await _db
        .customSelect('SELECT COUNT(*) as c FROM audio_files')
        .getSingle();
    return row.data['c'] as int;
  }

  Future<Set<String>> getCachedFilenames() async {
    await init();
    final rows = await _db
        .customSelect('SELECT filename FROM audio_files')
        .get();
    return rows.map((r) => r.data['filename'] as String).toSet();
  }

  Future<Set<String>> getCompletedPacks() async {
    await init();
    final rows = await _db
        .customSelect('SELECT name FROM completed_packs')
        .get();
    return rows.map((r) => r.data['name'] as String).toSet();
  }

  Future<void> markPackComplete(String name) async {
    await init();
    await _db.customInsert(
      'INSERT OR IGNORE INTO completed_packs (name) VALUES (?)',
      variables: [Variable.withString(name)],
    );
  }

  // Hardcoded pack count — must match scripts/export_for_r2.py output.
  // PACK_SIZE=4000, ~260K audio files → 65 tar packs.
  static const totalPacks = 65;

  /// Returns true if all audio packs have been downloaded.
  Future<bool> isDownloadComplete() async {
    await init();
    final row = await _db
        .customSelect('SELECT COUNT(*) as c FROM completed_packs')
        .getSingle();
    return (row.data['c'] as int) >= totalPacks;
  }

  Future<void> setMeta(String key, String value) async {
    await init();
    await _db.customInsert(
      'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
      variables: [Variable.withString(key), Variable.withString(value)],
    );
  }

  Future<String?> getMeta(String key) async {
    await init();
    final rows = await _db
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
    await _db.customUpdate(
      'DELETE FROM meta WHERE key = ?',
      variables: [Variable.withString(key)],
      updates: {},
    );
  }

  Future<void> clear() async {
    await init();
    await _db.customStatement('DELETE FROM audio_files');
    await _db.customStatement('DELETE FROM completed_packs');
    await _db.customStatement('DELETE FROM meta');
    await _db.customStatement('VACUUM');
  }

  Future<void> close() async {
    if (_initialized) await _db.close();
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
  final AudioDb audioDB = AudioDb();

  static const _r2AudioUrl = '$r2BaseUrl/audio';

  bool _downloadCancelled = false;

  void cancelDownload() => _downloadCancelled = true;

  AudioService();

  /// Play audio by filename. Checks local DB first, fetches from API if missing.
  Future<void> play(String filename) async {
    if (filename.isEmpty) return;

    try {
      // Check local audio.db
      var data = await audioDB.get(filename);

      if (data == null) {
        // Fetch from R2, store in audio.db
        final response = await http.get(Uri.parse('$_r2AudioUrl/$filename'));
        if (response.statusCode == 200) {
          data = response.bodyBytes;
          await audioDB.put(filename, data);
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

  /// Download all audio via pre-built tar packs from R2.
  /// Fetches manifest, skips completed packs, downloads remaining in parallel.
  /// Retries failed packs across multiple rounds with increasing backoff.
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
  }) async {
    _downloadCancelled = false;
    const packsUrl = '$r2BaseUrl/audio-packs';
    final client = http.Client();

    bool cancelled() => _downloadCancelled || (isCancelled?.call() ?? false);

    try {
      final manifestRes = await httpGetWithRetry(
        client,
        Uri.parse('$packsUrl/manifest.json'),
        maxAttempts: 3,
        timeout: const Duration(seconds: 15),
      );
      if (manifestRes.statusCode != 200) {
        throw Exception('Failed to fetch manifest: ${manifestRes.statusCode}');
      }
      final manifest = (jsonDecode(manifestRes.body) as List)
          .cast<Map<String, dynamic>>();

      await audioDB.setMeta('total_packs', manifest.length.toString());

      const maxRounds = 10;
      const roundDelays = [0, 10, 30, 60, 120]; // seconds
      const concurrency = 6;
      var totalFilesExtracted = 0;
      var totalBytesDownloaded = 0;

      for (var round = 0; round < maxRounds; round++) {
        if (cancelled()) return;

        final completed = await audioDB.getCompletedPacks();
        final remaining = manifest
            .where((p) => !completed.contains(p['name']))
            .toList();

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
          if (cancelled()) return;
        }

        var packsCompleted = completed.length;
        var failedThisRound = 0;

        for (var i = 0; i < remaining.length; i += concurrency) {
          if (cancelled()) return;
          final end = (i + concurrency).clamp(0, remaining.length);
          final batch = remaining.sublist(i, end);

          final futures = batch.map((pack) async {
            final packName = pack['name'] as String;
            try {
              final res = await httpGetWithRetry(
                client,
                Uri.parse('$packsUrl/$packName'),
                maxAttempts: 3,
                timeout: const Duration(seconds: 120),
                baseDelay: const Duration(seconds: 2),
              );
              if (res.statusCode != 200) {
                debugPrint(
                  'AudioService: pack $packName failed ${res.statusCode}',
                );
                return (0, 0, false);
              }
              final extracted = await _extractTar(res.bodyBytes);
              await audioDB.markPackComplete(packName);
              return (extracted, res.bodyBytes.length, true);
            } catch (e) {
              debugPrint('AudioService: pack $packName error: $e');
              return (0, 0, false);
            }
          });

          final results = await Future.wait(futures);
          for (final (files, bytes, success) in results) {
            if (success) {
              packsCompleted++;
            } else {
              failedThisRound++;
            }
            totalFilesExtracted += files;
            totalBytesDownloaded += bytes;
          }
          onProgress(
            packsCompleted,
            manifest.length,
            totalFilesExtracted,
            totalBytesDownloaded,
            round,
            failedThisRound,
          );
        }

        if (failedThisRound == 0) return; // all succeeded this round
        debugPrint(
          'AudioService: round $round done, $failedThisRound packs failed',
        );
      }

      // Still incomplete after all rounds
      final finalCompleted = await audioDB.getCompletedPacks();
      final remaining = manifest.length - finalCompleted.length;
      if (remaining > 0) {
        throw Exception(
          '$remaining packs failed after $maxRounds retry rounds',
        );
      }
    } finally {
      client.close();
    }
  }

  /// Parse tar archive and insert all files into audio.db in a single transaction.
  Future<int> _extractTar(Uint8List tarBytes) async {
    final files = <(String, Uint8List)>[];
    var pos = 0;

    while (pos + 512 <= tarBytes.length) {
      final header = tarBytes.sublist(pos, pos + 512);
      if (header.every((b) => b == 0)) break;

      // Filename: first 100 bytes, null-terminated
      final nameBytes = header.sublist(0, 100);
      var nameEnd = nameBytes.indexOf(0);
      if (nameEnd == -1) nameEnd = 100;
      final filename = String.fromCharCodes(
        nameBytes.sublist(0, nameEnd),
      ).trim();

      // File size: bytes 124-136, octal
      final sizeStr = String.fromCharCodes(
        header.sublist(124, 136),
      ).replaceAll(RegExp(r'[\x00 ]'), '');
      final fileSize = sizeStr.isNotEmpty
          ? int.tryParse(sizeStr, radix: 8) ?? 0
          : 0;

      pos += 512;

      if (filename.isNotEmpty &&
          fileSize > 0 &&
          pos + fileSize <= tarBytes.length) {
        files.add((
          filename,
          Uint8List.sublistView(tarBytes, pos, pos + fileSize),
        ));
      }

      // Advance to next 512-byte boundary
      pos += (fileSize + 511) & ~511;
    }

    await audioDB.putBatch(files);
    return files.length;
  }

  /// Cached file count from audio.db.
  Future<int> getCachedFileCount() => audioDB.fileCount();

  /// Whether all audio packs have been downloaded.
  Future<bool> isDownloadComplete() => audioDB.isDownloadComplete();

  /// Clear all cached audio.
  Future<void> clearCache() => audioDB.clear();

  Future<void> stop() async => await _player.stop();

  void dispose() {
    _player.dispose();
    audioDB.close();
  }
}
