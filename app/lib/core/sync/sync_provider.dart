import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../database/database_provider.dart';
import 'sync_service.dart';

final syncServiceProvider = Provider<SyncService?>((ref) {
  if (!syncEnabled) return null;
  return SyncService(
    db: ref.read(userDbProvider),
    supabase: Supabase.instance.client,
  );
});
