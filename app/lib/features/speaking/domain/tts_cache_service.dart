import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config.dart';
import '../../../core/logging/logging_service.dart';

/// Local + remote TTS audio cache.
///
/// Flow: local SQLite → Supabase edge function (which checks its own cache
/// before calling OpenAI TTS) → store locally.
class TtsCacheService {
  final SupabaseClient _supabase;
  final AudioPlayer _player = AudioPlayer();
  GeneratedDatabase? _db;
  bool _initialized = false;

  TtsCacheService({required SupabaseClient supabase}) : _supabase = supabase;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/tts_cache.db');
    _db = _RawDb(NativeDatabase.createInBackground(file));
    await _db!.customStatement('''
      CREATE TABLE IF NOT EXISTS tts_cache (
        text_hash TEXT PRIMARY KEY,
        audio_data BLOB NOT NULL
      )
    ''');
    _initialized = true;
  }

  String _hashText(String text) => sha256.convert(utf8.encode(text)).toString();

  /// Get audio bytes for [text]. Checks local cache first, then calls the
  /// speaking-tts edge function (which has its own Supabase-level cache).
  Future<Uint8List> getAudio(String text) async {
    await _ensureInit();
    final hash = _hashText(text);

    // Check local cache
    final rows = await _db!
        .customSelect(
          'SELECT audio_data FROM tts_cache WHERE text_hash = ?',
          variables: [Variable.withString(hash)],
        )
        .get();
    if (rows.isNotEmpty) {
      return rows.first.data['audio_data'] as Uint8List;
    }

    // Fetch from edge function
    final token =
        _supabase.auth.currentSession?.accessToken ??
        (isDevBuild ? supabaseAnonKey : null);
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated — please sign in');
    }

    final uri = Uri.parse('$supabaseUrl/functions/v1/speaking-tts');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'text': text}),
    );

    if (response.statusCode != 200) {
      throw Exception('TTS failed (${response.statusCode})');
    }

    final audioBytes = response.bodyBytes;

    // Cache locally
    await _db!.customInsert(
      'INSERT OR REPLACE INTO tts_cache (text_hash, audio_data) VALUES (?, ?)',
      variables: [Variable.withString(hash), Variable.withBlob(audioBytes)],
    );

    return audioBytes;
  }

  /// Play TTS audio for [text]. Fetches and caches if needed.
  Future<void> play(String text) async {
    try {
      await _player.stop();
      final audioBytes = await getAudio(text);
      final dir = await getApplicationDocumentsDirectory();
      final hash = _hashText(text).substring(0, 12);
      final tmpFile = File('${dir.path}/_tts_$hash.mp3');
      await tmpFile.writeAsBytes(audioBytes);
      await _player.setFilePath(tmpFile.path);
      await _player.play();
      // Clean up temp file after playback finishes
      tmpFile.delete().ignore();
    } catch (e, st) {
      globalTalker.error('[TTS] playback error', e, st);
    }
  }

  Future<void> stop() => _player.stop();

  /// Play a local audio file (e.g. the user's shadow recording).
  Future<void> playLocalFile(String path) async {
    try {
      await _player.stop();
      await _player.setFilePath(path);
      await _player.play();
    } catch (e, st) {
      globalTalker.error('[TTS] local playback error', e, st);
    }
  }

  void dispose() {
    _player.dispose();
    if (_initialized) _db?.close();
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
