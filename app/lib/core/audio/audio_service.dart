import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart' as raw;
import '../config.dart';

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
    final fileSize = sizeStr.isNotEmpty
        ? int.tryParse(sizeStr, radix: 8) ?? 0
        : 0;

    pos += 512;

    if (filename.isNotEmpty &&
        fileSize > 0 &&
        pos + fileSize <= tarBytes.length) {
      files.add(
        MapEntry(
          filename,
          Uint8List.sublistView(tarBytes, pos, pos + fileSize),
        ),
      );
    }

    // Advance to next 512-byte boundary
    pos += (fileSize + 511) & ~511;
  }

  return files;
}

/// Top-level function for compute() — reads tar from a file path on disk,
/// parses and inserts into SQLite, then deletes the tar file.
int _parseTarFileAndInsert((String, String) args) {
  final (tarFilePath, dbPath) = args;
  final tarBytes = File(tarFilePath).readAsBytesSync();
  final db = raw.sqlite3.open(dbPath);
  try {
    final files = _parseTar(tarBytes);
    final stmt = db.prepare(
      'INSERT OR REPLACE INTO audio_files (filename, data) VALUES (?, ?)',
    );
    db.execute('BEGIN TRANSACTION');
    for (final entry in files) {
      stmt.execute([entry.key, entry.value]);
    }
    db.execute('COMMIT');
    stmt.close();
    return files.length;
  } finally {
    db.close();
    File(tarFilePath).deleteSync();
  }
}

/// Local SQLite database for cached audio BLOBs.
/// Same schema as the server's audio_files table.
class AudioDb {
  GeneratedDatabase? _db;
  String? _dbPath;
  bool _initialized = false;

  AudioDb();

  /// In-memory DB for tests. Follows UserDatabase.forTesting pattern.
  AudioDb.forTesting(QueryExecutor executor) : _db = _RawDb(executor);

  Future<void> init() async {
    if (_initialized) return;
    if (_db == null) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/audio.db');
      _dbPath = file.path;
      _db = _RawDb(NativeDatabase.createInBackground(file));
    }
    await _createTables();
    _initialized = true;
  }

  /// Returns the database file path, or null for in-memory test databases.
  Future<String?> getDbPath() async {
    await init();
    return _dbPath;
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
/// Download orchestration is handled by [AudioDownloadManager].
class AudioService {
  final AudioPlayer _player = AudioPlayer();
  final AudioDb _audioDB;

  static const _r2AudioUrl = '$r2BaseUrl/audio';

  AudioService({AudioDb? db}) : _audioDB = db ?? AudioDb();

  /// Expose AudioDb for AudioDownloadManager to use directly.
  AudioDb get audioDB => _audioDB;

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

  /// Extract a tar file from disk into audio.db. Deletes the tar file after.
  /// Falls back to main-thread putBatch for in-memory test databases.
  Future<int> extractTarFile(String tarFilePath) async {
    final dbPath = await _audioDB.getDbPath();
    if (dbPath != null) {
      return compute(_parseTarFileAndInsert, (tarFilePath, dbPath));
    }
    // In-memory test DB — can't open a second connection, use Drift path
    final tarBytes = File(tarFilePath).readAsBytesSync();
    final entries = _parseTar(tarBytes);
    final files = entries.map((e) => (e.key, e.value)).toList(growable: false);
    await _audioDB.putBatch(files);
    File(tarFilePath).deleteSync();
    return files.length;
  }

  /// Cached file count from audio.db.
  Future<int> getCachedFileCount() => _audioDB.fileCount();

  /// Whether all audio packs have been downloaded.
  Future<bool> isDownloadComplete() => _audioDB.isDownloadComplete();

  /// Clear all cached audio.
  Future<void> clearCache() => _audioDB.clear();

  Future<void> stop() async => await _player.stop();

  void dispose() {
    _player.dispose();
    _audioDB.close();
  }
}
