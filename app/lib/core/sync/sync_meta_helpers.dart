import 'package:drift/drift.dart';
import '../database/app_database.dart';

Future<String?> getLastSyncAt(UserDatabase db, String table) async {
  final rows = await db
      .customSelect(
        'SELECT value FROM sync_meta WHERE key = ?',
        variables: [Variable.withString('${table}_last_sync_at')],
        readsFrom: {db.syncMeta},
      )
      .get();
  if (rows.isEmpty) return null;
  final value = rows.first.data['value'] as String?;
  return (value == null || value.isEmpty) ? null : value;
}

Future<void> setLastSyncAt(
  UserDatabase db,
  String table,
  String timestamp,
) async {
  await db
      .into(db.syncMeta)
      .insertOnConflictUpdate(
        SyncMetaCompanion.insert(
          key: '${table}_last_sync_at',
          value: timestamp,
        ),
      );
}
