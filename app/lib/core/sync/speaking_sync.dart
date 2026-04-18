import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../logging/logging_service.dart';
import 'table_sync.dart';

class SpeakingSync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;
  final TableSync _tableSync;

  SpeakingSync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
    required TableSync tableSync,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId,
       _tableSync = tableSync;

  // ── Push ───────────────────────────────────────────────────────────────────

  Future<int> pushAllUnsynced() async {
    if (_getUserId() == null) return 0;
    final unsynced = await _db
        .customSelect(
          'SELECT * FROM speaking_results WHERE synced = 0',
          readsFrom: {_db.speakingResults},
        )
        .get();
    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      final data = row.data;
      try {
        await _supabase.from('speaking_results').upsert({
          'id': data['id'],
          'user_id': _getUserId(),
          'topic': data['topic'],
          'is_custom_topic': data['is_custom_topic'] == 1,
          'transcript': data['transcript'],
          'corrections_json': data['corrections_json'],
          'natural_version': data['natural_version'],
          'overall_note': data['overall_note'],
          'session_id': data['session_id'],
          'attempt_number': data['attempt_number'],
          'audio_storage_key': data['audio_storage_key'],
          'created_at': data['created_at'],
          'updated_at': data['updated_at'],
          'deleted_at': data['deleted_at'],
        });
        await _db.customUpdate(
          'UPDATE speaking_results SET synced = 1 WHERE id = ?',
          variables: [Variable.withString(data['id'] as String)],
          updates: {_db.speakingResults},
        );
        pushed++;
      } catch (e) {
        globalTalker.error(
          '[Sync] Push speaking result "${data['id']}" failed: $e',
        );
      }
    }
    return pushed;
  }

  // ── Pull ───────────────────────────────────────────────────────────────────

  Future<int> pullSpeakingResults() => _tableSync.pull(
    remoteTable: 'speaking_results',
    watermarkKey: 'speaking_results',
    processRow: _processRow,
  );

  Future<bool> _processRow(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdatedAt = row['updated_at'] as String;
    final remoteDeletedAt = row['deleted_at'] as String?;

    final existing = await _db
        .customSelect(
          'SELECT id, updated_at FROM speaking_results WHERE id = ?',
          variables: [Variable.withString(id)],
          readsFrom: {_db.speakingResults},
        )
        .get();

    if (existing.isEmpty) {
      if (remoteDeletedAt != null) return false;

      // Convert JSONB to text for local storage
      final correctionsJson = row['corrections_json'];
      final correctionsText = correctionsJson is String
          ? correctionsJson
          : correctionsJson.toString();

      await _db.customInsert(
        '''INSERT INTO speaking_results
           (id, topic, is_custom_topic, transcript, corrections_json,
            natural_version, overall_note, session_id, attempt_number,
            audio_storage_key, created_at, updated_at, synced)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)''',
        variables: [
          Variable.withString(id),
          Variable.withString(row['topic'] as String),
          Variable.withBool(row['is_custom_topic'] as bool? ?? false),
          Variable.withString(row['transcript'] as String),
          Variable.withString(correctionsText),
          Variable.withString(row['natural_version'] as String),
          row['overall_note'] != null
              ? Variable.withString(row['overall_note'] as String)
              : const Variable(null),
          row['session_id'] != null
              ? Variable.withString(row['session_id'] as String)
              : const Variable(null),
          row['attempt_number'] != null
              ? Variable.withInt(row['attempt_number'] as int)
              : const Variable(null),
          row['audio_storage_key'] != null
              ? Variable.withString(row['audio_storage_key'] as String)
              : const Variable(null),
          Variable.withString(row['created_at'] as String),
          Variable.withString(remoteUpdatedAt),
        ],
        updates: {_db.speakingResults},
      );
      return true;
    }

    final localUpdatedAt = existing.first.data['updated_at'] as String;
    if (remoteUpdatedAt.compareTo(localUpdatedAt) > 0) {
      if (remoteDeletedAt != null) {
        await _db.customUpdate(
          'UPDATE speaking_results SET deleted_at = ?, updated_at = ?, synced = 1 WHERE id = ?',
          variables: [
            Variable.withString(remoteDeletedAt),
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.speakingResults},
        );
      } else {
        final correctionsJson = row['corrections_json'];
        final correctionsText = correctionsJson is String
            ? correctionsJson
            : correctionsJson.toString();

        await _db.customUpdate(
          '''UPDATE speaking_results SET
             topic = ?, is_custom_topic = ?, transcript = ?,
             corrections_json = ?, natural_version = ?, overall_note = ?,
             session_id = ?, attempt_number = ?, audio_storage_key = ?,
             updated_at = ?, synced = 1
             WHERE id = ?''',
          variables: [
            Variable.withString(row['topic'] as String),
            Variable.withBool(row['is_custom_topic'] as bool? ?? false),
            Variable.withString(row['transcript'] as String),
            Variable.withString(correctionsText),
            Variable.withString(row['natural_version'] as String),
            row['overall_note'] != null
                ? Variable.withString(row['overall_note'] as String)
                : const Variable(null),
            row['session_id'] != null
                ? Variable.withString(row['session_id'] as String)
                : const Variable(null),
            row['attempt_number'] != null
                ? Variable.withInt(row['attempt_number'] as int)
                : const Variable(null),
            row['audio_storage_key'] != null
                ? Variable.withString(row['audio_storage_key'] as String)
                : const Variable(null),
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.speakingResults},
        );
      }
      return true;
    }
    return false;
  }

  // ── Orchestration ──────────────────────────────────────────────────────────

  Future<void> syncSpeakingData() async {
    await pullSpeakingResults();
    await pushAllUnsynced();
  }

  Future<void> cleanupSoftDeletes({int retentionDays = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toUtc()
        .toIso8601String();
    await _db.customUpdate(
      'DELETE FROM speaking_results WHERE deleted_at IS NOT NULL AND synced = 1 AND deleted_at < ?',
      variables: [Variable.withString(cutoff)],
      updates: {_db.speakingResults},
    );
  }
}
