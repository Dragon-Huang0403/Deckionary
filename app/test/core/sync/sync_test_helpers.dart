import 'dart:io' show Platform;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';
import 'package:deckionary/core/database/app_database.dart';

const _uuid = Uuid();

// Default local Supabase values (supabase start demo keys — not secrets).
// Override via SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY env vars.
final supabaseUrl =
    Platform.environment['SUPABASE_URL'] ?? 'http://127.0.0.1:54321';
final supabaseServiceRoleKey =
    Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ??
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

/// Creates an in-memory UserDatabase for testing.
UserDatabase createTestDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return UserDatabase.forTesting(NativeDatabase.memory());
}

/// Generates a random UUID for test data.
String testUuid() => _uuid.v4();

/// Creates a SupabaseClient pointing to the local Supabase instance.
SupabaseClient createTestSupabase() =>
    SupabaseClient(supabaseUrl, supabaseServiceRoleKey);

/// Creates a real auth user via admin API. Returns the user's UUID.
/// FK constraints on user_id require real auth.users rows.
Future<String> createTestUser(SupabaseClient supabase) async {
  final email = '${_uuid.v4()}@test.local';
  final res = await supabase.auth.admin.createUser(
    AdminUserAttributes(email: email, password: 'test123456'),
  );
  return res.user!.id;
}

/// Deletes a test auth user and all their data from sync tables.
Future<void> deleteTestUser(SupabaseClient supabase, String userId) async {
  await supabase.from('review_cards').delete().eq('user_id', userId);
  await supabase.from('review_logs').delete().eq('user_id', userId);
  await supabase.from('search_history').delete().eq('user_id', userId);
  await supabase.from('user_settings').delete().eq('user_id', userId);
  await supabase.auth.admin.deleteUser(userId);
}

/// Minimal review card row for Supabase insertion.
Map<String, dynamic> makeReviewCard({
  required String id,
  required String userId,
  int entryId = 1,
  String headword = 'test',
  String pos = 'noun',
  String? updatedAt,
  String? deletedAt,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    'id': id,
    'user_id': userId,
    'entry_id': entryId,
    'headword': headword,
    'pos': pos,
    'due': now,
    'stability': 0.0,
    'difficulty': 0.0,
    'elapsed_days': 0,
    'scheduled_days': 0,
    'reps': 0,
    'lapses': 0,
    'state': 0,
    'created_at': now,
    'updated_at': updatedAt ?? now,
    if (deletedAt != null) 'deleted_at': deletedAt,
  };
}
