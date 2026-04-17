import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config.dart';
import '../../../core/database/app_database.dart';
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
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('$supabaseUrl/functions/v1/speaking-analyze');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['topic'] = topic
      ..files.add(
        http.MultipartFile.fromBytes(
          'audio',
          audioBytes,
          filename: 'recording.m4a',
        ),
      );

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Analysis failed (${streamed.statusCode}): $body');
    }

    return SpeakingResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Analyze typed text. Sends text to the speaking-analyze edge function.
  Future<SpeakingResult> analyzeText(String text, String topic) async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Not authenticated');

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
      throw Exception(
        'Analysis failed (${response.statusCode}): ${response.body}',
      );
    }

    return SpeakingResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Persist a speaking result to local DB for sync.
  Future<void> saveResult({
    required String topic,
    required bool isCustomTopic,
    required SpeakingResult result,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db
        .into(_db.speakingResults)
        .insert(
          SpeakingResultsCompanion.insert(
            id: const Uuid().v4(),
            topic: topic,
            isCustomTopic: Value(isCustomTopic),
            transcript: result.transcript,
            correctionsJson: jsonEncode(result.toJson()['corrections']),
            naturalVersion: result.naturalVersion,
            overallNote: Value(result.overallNote),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  /// Fetch past speaking results (most recent first, excludes soft-deleted).
  Future<List<SpeakingResultRow>> getHistory({int limit = 50}) async {
    return (_db.select(_db.speakingResults)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Soft-delete a speaking result.
  Future<void> deleteResult(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(
      _db.speakingResults,
    )..where((t) => t.id.equals(id))).write(
      SpeakingResultsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        synced: const Value(0),
      ),
    );
  }
}
