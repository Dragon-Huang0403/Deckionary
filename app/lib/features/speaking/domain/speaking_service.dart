import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/logging_service.dart';
import 'speaking_result.dart';

/// Orchestrates speaking analysis: sends audio/text to the edge function,
/// parses results, and persists to local DB.
class SpeakingService {
  final UserDatabase _db;
  final SupabaseClient _supabase;

  SpeakingService({required UserDatabase db, required SupabaseClient supabase})
    : _db = db,
      _supabase = supabase;

  /// Analyze a voice recording. Sends audio to the speaking-analyze edge
  /// function and returns structured corrections.
  Future<SpeakingResult> analyzeRecording(
    Uint8List audioBytes,
    String topic,
  ) async {
    final token =
        _supabase.auth.currentSession?.accessToken ??
        (isDevBuild ? supabaseAnonKey : null);
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated — please sign in');
    }

    final uri = Uri.parse('$supabaseUrl/functions/v1/speaking-analyze');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['topic'] = topic
      ..files.add(
        http.MultipartFile.fromBytes(
          'audio',
          audioBytes,
          filename: 'recording.wav',
        ),
      );

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      globalTalker.error(
        '[Speaking] analyze (audio) failed: '
        '${streamed.statusCode} ${_truncate(body)}',
      );
      throw Exception('Analysis failed (${streamed.statusCode}): $body');
    }

    return SpeakingResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Analyze typed text.
  Future<SpeakingResult> analyzeText(String text, String topic) async {
    final token =
        _supabase.auth.currentSession?.accessToken ??
        (isDevBuild ? supabaseAnonKey : null);
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated — please sign in');
    }

    final uri = Uri.parse('$supabaseUrl/functions/v1/speaking-analyze');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'text': text, 'topic': topic}),
    );

    if (response.statusCode != 200) {
      globalTalker.error(
        '[Speaking] analyze (text) failed: '
        '${response.statusCode} ${_truncate(response.body)}',
      );
      throw Exception(
        'Analysis failed (${response.statusCode}): ${response.body}',
      );
    }

    return SpeakingResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static String _truncate(String s, [int max = 500]) =>
      s.length <= max ? s : '${s.substring(0, max)}… (${s.length} chars)';

  /// Persist one attempt to the DB. Returns the newly created row id.
  Future<String> saveAttempt({
    required String sessionId,
    required String topic,
    required bool isCustomTopic,
    required int attemptNumber,
    required SpeakingResult result,
    String? audioLocalPath,
    String? audioStorageKey,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = const Uuid().v4();
    await _db
        .into(_db.speakingResults)
        .insert(
          SpeakingResultsCompanion.insert(
            id: id,
            topic: topic,
            isCustomTopic: Value(isCustomTopic),
            transcript: result.transcript,
            correctionsJson: jsonEncode(result.toJson()['corrections']),
            naturalVersion: result.naturalVersion,
            overallNote: Value(result.overallNote),
            sessionId: Value(sessionId),
            attemptNumber: Value(attemptNumber),
            audioLocalPath: Value(audioLocalPath),
            audioStorageKey: Value(audioStorageKey),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// Move a freshly-recorded WAV from its temp path into the permanent
  /// per-attempt location, then update the row with the new `audio_local_path`.
  /// Returns the final absolute path.
  Future<String> attachLocalAudio({
    required String attemptId,
    required String tempPath,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/speaking_audio');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }
    final finalPath = '${audioDir.path}/$attemptId.wav';
    try {
      await File(tempPath).rename(finalPath);
    } on FileSystemException {
      // Cross-device rename may fail; fall back to copy+delete.
      await File(tempPath).copy(finalPath);
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
    await (_db.update(_db.speakingResults)
          ..where((t) => t.id.equals(attemptId)))
        .write(SpeakingResultsCompanion(audioLocalPath: Value(finalPath)));
    return finalPath;
  }

  /// Upload a recording to the private `speaking-audio` bucket. Updates the
  /// row with `audio_storage_key` and flips `synced = 0`. Errors are rethrown
  /// so callers can log; callers typically fire-and-forget.
  Future<String> uploadAttemptAudio({
    required String attemptId,
    required Uint8List bytes,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError(
        'uploadAttemptAudio called without an authenticated user',
      );
    }
    final key = '$userId/$attemptId.wav';
    await _supabase.storage
        .from('speaking-audio')
        .uploadBinary(
          key,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'audio/wav',
            upsert: true,
          ),
        );
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(
      _db.speakingResults,
    )..where((t) => t.id.equals(attemptId))).write(
      SpeakingResultsCompanion(
        audioStorageKey: Value(key),
        updatedAt: Value(now),
        synced: const Value(0),
      ),
    );
    return key;
  }

  /// Download a previously uploaded recording to a local file and update the
  /// row with `audio_local_path` (device-local, not synced). Returns the path.
  Future<String> downloadAttemptAudio({
    required String attemptId,
    required String storageKey,
  }) async {
    final bytes = await _supabase.storage
        .from('speaking-audio')
        .download(storageKey);
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${dir.path}/speaking_audio');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }
    final finalPath = '${audioDir.path}/$attemptId.wav';
    await File(finalPath).writeAsBytes(bytes);
    await (_db.update(_db.speakingResults)
          ..where((t) => t.id.equals(attemptId)))
        .write(SpeakingResultsCompanion(audioLocalPath: Value(finalPath)));
    return finalPath;
  }

  /// Most recent rows, excluding soft-deleted. Callers are responsible for
  /// grouping by session_id.
  Future<List<SpeakingResultRow>> getHistory({int limit = 50}) async {
    return (_db.select(_db.speakingResults)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// All attempts for one session, ordered by attempt_number ascending.
  Future<List<SpeakingResultRow>> getAttemptsBySessionId(
    String sessionId,
  ) async {
    return (_db.select(_db.speakingResults)
          ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.attemptNumber)]))
        .get();
  }

  /// Transitional — used only by the legacy history detail screen. Removed
  /// when history providers are rewritten to load sessions by session_id
  /// (see plan Task 15).
  Future<SpeakingResultRow?> getResultById(String id) async {
    final rows = await (_db.select(
      _db.speakingResults,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Soft-delete every attempt in a session and best-effort remove its audio
  /// (local files + remote bucket objects). DB rows stay (soft-delete) so the
  /// deletion syncs.
  Future<void> deleteSession(String sessionId) async {
    final rows = await (_db.select(
      _db.speakingResults,
    )..where((t) => t.sessionId.equals(sessionId))).get();

    for (final row in rows) {
      final localPath = row.audioLocalPath;
      if (localPath != null) {
        try {
          final f = File(localPath);
          if (f.existsSync()) await f.delete();
        } catch (e) {
          globalTalker.error('[Speaking] delete local audio failed: $e');
        }
      }
    }
    final storageKeys = rows
        .map((r) => r.audioStorageKey)
        .whereType<String>()
        .toList();
    if (storageKeys.isNotEmpty) {
      try {
        await _supabase.storage.from('speaking-audio').remove(storageKeys);
      } catch (e) {
        globalTalker.error('[Speaking] delete remote audio failed: $e');
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(
      _db.speakingResults,
    )..where((t) => t.sessionId.equals(sessionId))).write(
      SpeakingResultsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        synced: const Value(0),
      ),
    );
  }
}
