import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import '../logging/logging_service.dart';
import 'table_sync.dart';

class VocabularyListSync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;
  final TableSync _tableSync;

  VocabularyListSync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
    required TableSync tableSync,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId,
       _tableSync = tableSync;

  // ── Push ───────────────────────────────────────────────────────────────────

  Future<int> pushAllUnsyncedLists() async {
    if (_getUserId() == null) return 0;
    final unsynced = await _db
        .customSelect(
          'SELECT * FROM vocabulary_lists WHERE synced = 0',
          readsFrom: {_db.vocabularyLists},
        )
        .get();
    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      final data = row.data;
      try {
        await _supabase.from('vocabulary_lists').upsert({
          'id': data['id'],
          'user_id': _getUserId(),
          'name': data['name'],
          'description': data['description'],
          'created_at': data['created_at'],
          'updated_at': data['updated_at'],
          'deleted_at': data['deleted_at'],
        });
        await _db.customUpdate(
          'UPDATE vocabulary_lists SET synced = 1 WHERE id = ?',
          variables: [Variable.withString(data['id'] as String)],
          updates: {_db.vocabularyLists},
        );
        pushed++;
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          // Remote already has a list with the same (user_id, name).
          // Merge local entries into the remote list and delete the duplicate.
          try {
            final remote = await _supabase
                .from('vocabulary_lists')
                .select('id')
                .eq('name', data['name'] as String)
                .limit(1);
            if (remote.isNotEmpty) {
              await _mergeAndReplace(
                data['id'] as String,
                remote[0]['id'] as String,
              );
            }
          } catch (mergeErr) {
            globalTalker.error(
              '[Sync] Push list "${data['name']}": merge failed: $mergeErr',
            );
          }
        } else {
          globalTalker.error('[Sync] Push list "${data['name']}" failed: $e');
          // Soft-deleted list that can't be pushed — stop retrying.
          if (data['deleted_at'] != null) {
            await _db.customUpdate(
              'UPDATE vocabulary_lists SET synced = 1 WHERE id = ?',
              variables: [Variable.withString(data['id'] as String)],
              updates: {_db.vocabularyLists},
            );
          }
        }
      } catch (e) {
        globalTalker.error('[Sync] Push list "${data['name']}" failed: $e');
      }
    }
    return pushed;
  }

  Future<int> pushAllUnsyncedEntries() async {
    if (_getUserId() == null) return 0;
    final unsynced = await _db
        .customSelect(
          'SELECT * FROM vocabulary_list_entries WHERE synced = 0',
          readsFrom: {_db.vocabularyListEntries},
        )
        .get();
    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      final data = row.data;
      try {
        await _supabase.from('vocabulary_list_entries').upsert({
          'id': data['id'],
          'user_id': _getUserId(),
          'list_id': data['list_id'],
          'entry_id': data['entry_id'],
          'headword': data['headword'],
          'pos': data['pos'],
          'added_at': data['added_at'],
          'updated_at': data['updated_at'],
          'deleted_at': data['deleted_at'],
        });
        await _db.customUpdate(
          'UPDATE vocabulary_list_entries SET synced = 1 WHERE id = ?',
          variables: [Variable.withString(data['id'] as String)],
          updates: {_db.vocabularyListEntries},
        );
        pushed++;
      } catch (e) {
        globalTalker.error(
          '[Sync] Push entry "${data['headword']}" (list=${data['list_id']}) failed: $e',
        );
      }
    }
    return pushed;
  }

  // ── Pull ───────────────────────────────────────────────────────────────────

  Future<int> pullLists() => _tableSync.pull(
    remoteTable: 'vocabulary_lists',
    watermarkKey: 'vocabulary_lists',
    processRow: _processListRow,
  );

  Future<int> pullEntries() => _tableSync.pull(
    remoteTable: 'vocabulary_list_entries',
    watermarkKey: 'vocabulary_list_entries',
    processRow: _processEntryRow,
  );

  Future<bool> _processListRow(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdatedAt = row['updated_at'] as String;
    final remoteDeletedAt = row['deleted_at'] as String?;

    final existing = await _db
        .customSelect(
          'SELECT id, updated_at FROM vocabulary_lists WHERE id = ?',
          variables: [Variable.withString(id)],
          readsFrom: {_db.vocabularyLists},
        )
        .get();

    if (existing.isEmpty) {
      if (remoteDeletedAt != null) return false;

      // Check for a local list with the same name but different ID.
      // Happens when two devices independently create "My Words".
      final remoteName = row['name'] as String;
      final duplicates = await _db
          .customSelect(
            'SELECT id FROM vocabulary_lists WHERE name = ? AND id != ? AND deleted_at IS NULL',
            variables: [
              Variable.withString(remoteName),
              Variable.withString(id),
            ],
            readsFrom: {_db.vocabularyLists},
          )
          .get();
      for (final dup in duplicates) {
        await _mergeAndReplace(dup.data['id'] as String, id);
      }

      await _db.customInsert(
        '''INSERT INTO vocabulary_lists
           (id, name, description, created_at, updated_at, synced)
           VALUES (?, ?, ?, ?, ?, 1)''',
        variables: [
          Variable.withString(id),
          Variable.withString(remoteName),
          Variable.withString((row['description'] as String?) ?? ''),
          Variable.withString(row['created_at'] as String),
          Variable.withString(remoteUpdatedAt),
        ],
        updates: {_db.vocabularyLists},
      );
      return true;
    }

    final localUpdatedAt = existing.first.data['updated_at'] as String;
    if (remoteUpdatedAt.compareTo(localUpdatedAt) > 0) {
      if (remoteDeletedAt != null) {
        await _db.customUpdate(
          'UPDATE vocabulary_lists SET deleted_at = ?, updated_at = ?, synced = 1 WHERE id = ?',
          variables: [
            Variable.withString(remoteDeletedAt),
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.vocabularyLists},
        );
      } else {
        await _db.customUpdate(
          '''UPDATE vocabulary_lists SET
             name = ?, description = ?, updated_at = ?, synced = 1
             WHERE id = ?''',
          variables: [
            Variable.withString(row['name'] as String),
            Variable.withString((row['description'] as String?) ?? ''),
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.vocabularyLists},
        );
      }
      return true;
    }
    return false;
  }

  Future<bool> _processEntryRow(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final remoteUpdatedAt = row['updated_at'] as String;
    final remoteDeletedAt = row['deleted_at'] as String?;

    final existing = await _db
        .customSelect(
          'SELECT id, updated_at FROM vocabulary_list_entries WHERE id = ?',
          variables: [Variable.withString(id)],
          readsFrom: {_db.vocabularyListEntries},
        )
        .get();

    if (existing.isEmpty) {
      if (remoteDeletedAt != null) return false;

      // Remove any reassigned local entry for the same word (from list merge).
      // The remote entry takes precedence since it's already synced.
      await _db.customUpdate(
        '''DELETE FROM vocabulary_list_entries
           WHERE list_id = ? AND entry_id = ? AND deleted_at IS NULL''',
        variables: [
          Variable.withString(row['list_id'] as String),
          Variable.withInt(row['entry_id'] as int),
        ],
        updates: {_db.vocabularyListEntries},
      );

      await _db.customInsert(
        '''INSERT INTO vocabulary_list_entries
           (id, list_id, entry_id, headword, pos, added_at, updated_at, synced)
           VALUES (?, ?, ?, ?, ?, ?, ?, 1)''',
        variables: [
          Variable.withString(id),
          Variable.withString(row['list_id'] as String),
          Variable.withInt(row['entry_id'] as int),
          Variable.withString(row['headword'] as String),
          Variable.withString((row['pos'] as String?) ?? ''),
          Variable.withString(row['added_at'] as String),
          Variable.withString(remoteUpdatedAt),
        ],
        updates: {_db.vocabularyListEntries},
      );
      return true;
    }

    final localUpdatedAt = existing.first.data['updated_at'] as String;
    if (remoteUpdatedAt.compareTo(localUpdatedAt) > 0) {
      if (remoteDeletedAt != null) {
        await _db.customUpdate(
          'UPDATE vocabulary_list_entries SET deleted_at = ?, updated_at = ?, synced = 1 WHERE id = ?',
          variables: [
            Variable.withString(remoteDeletedAt),
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.vocabularyListEntries},
        );
      } else {
        await _db.customUpdate(
          '''UPDATE vocabulary_list_entries SET
             list_id = ?, entry_id = ?, headword = ?, pos = ?,
             added_at = ?, updated_at = ?, synced = 1
             WHERE id = ?''',
          variables: [
            Variable.withString(row['list_id'] as String),
            Variable.withInt(row['entry_id'] as int),
            Variable.withString(row['headword'] as String),
            Variable.withString((row['pos'] as String?) ?? ''),
            Variable.withString(row['added_at'] as String),
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.vocabularyListEntries},
        );
      }
      return true;
    }
    return false;
  }

  // ── List merge ─────────────────────────────────────────────────────────────

  /// Merge a local duplicate list into the canonical remote list.
  ///
  /// The local list was never pushed (Supabase UNIQUE(user_id, name) rejected
  /// it), so we can hard-delete it. Entries are reassigned to [remoteId];
  /// duplicate words are cleaned up later in [_processEntryRow] when remote
  /// entries are pulled.
  Future<void> _mergeAndReplace(String localId, String remoteId) async {
    // Reassign local entries to the remote list.
    await _db.customUpdate(
      '''UPDATE vocabulary_list_entries
         SET list_id = ?, synced = 0
         WHERE list_id = ?''',
      variables: [Variable.withString(remoteId), Variable.withString(localId)],
      updates: {_db.vocabularyListEntries},
    );

    // Hard-delete the local duplicate list.
    await _db.customUpdate(
      'DELETE FROM vocabulary_lists WHERE id = ?',
      variables: [Variable.withString(localId)],
      updates: {_db.vocabularyLists},
    );
  }

  // ── Orchestration ──────────────────────────────────────────────────────────

  /// Sync order: push first, then pull. See ReviewSync.syncReviewData for
  /// the rationale.
  Future<void> syncVocabularyData() async {
    await pushAllUnsyncedLists();
    await pushAllUnsyncedEntries();
    await pullLists();
    await pullEntries();
  }

  Future<void> cleanupSoftDeletes({int retentionDays = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toUtc()
        .toIso8601String();
    await _db.customUpdate(
      'DELETE FROM vocabulary_list_entries WHERE deleted_at IS NOT NULL AND synced = 1 AND deleted_at < ?',
      variables: [Variable.withString(cutoff)],
      updates: {_db.vocabularyListEntries},
    );
    await _db.customUpdate(
      'DELETE FROM vocabulary_lists WHERE deleted_at IS NOT NULL AND synced = 1 AND deleted_at < ?',
      variables: [Variable.withString(cutoff)],
      updates: {_db.vocabularyLists},
    );
  }
}
