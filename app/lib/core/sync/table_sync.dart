import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';
import 'sync_meta_helpers.dart';

/// Shared pull mechanics for all synced tables.
///
/// Handles watermark tracking, `gte` filtering, ordering, and cursor updates.
/// Each sync module provides a [processRow] callback for table-specific logic
/// (conflict resolution, column mapping, insert/update).
class TableSync {
  final UserDatabase _db;
  final SupabaseClient _supabase;
  final String? Function() _getUserId;

  TableSync({
    required UserDatabase db,
    required SupabaseClient supabase,
    required String? Function() getUserId,
  }) : _db = db,
       _supabase = supabase,
       _getUserId = getUserId;

  /// Pull records from [remoteTable] using incremental cursor-based sync.
  ///
  /// [watermarkKey] — sync_meta key for tracking; `null` = fetch all records
  /// (no incremental filter). Use `null` for small tables like settings.
  ///
  /// [processRow] — table-specific handler that receives each Supabase row
  /// and returns `true` if it resulted in a local change.
  Future<int> pull({
    required String remoteTable,
    String? watermarkKey,
    required Future<bool> Function(Map<String, dynamic> row) processRow,
  }) async {
    if (_getUserId() == null) return 0;

    final cursor = watermarkKey != null
        ? await getLastSyncAt(_db, watermarkKey)
        : null;

    var query = _supabase
        .from(remoteTable)
        .select()
        .eq('user_id', _getUserId()!);

    // Watermark uses `server_updated_at` (set by DB trigger at write arrival)
    // rather than client-provided `updated_at`, which can be older than the
    // cursor when a delayed push lands after another device has already pulled.
    if (cursor != null) {
      query = query.gte('server_updated_at', cursor);
    }

    final rows = await query.order('server_updated_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      if (await processRow(row)) pulled++;
    }

    if (watermarkKey != null) {
      await setLastSyncAt(
        _db,
        watermarkKey,
        rows.first['server_updated_at'] as String,
      );
    }

    return pulled;
  }

  /// Clear all sync watermarks to force a full resync on next pull.
  Future<void> clearAllWatermarks() async {
    await _db.customUpdate(
      "DELETE FROM sync_meta WHERE key LIKE '%_last_sync_at'",
      updates: {_db.syncMeta},
    );
  }
}
