import 'dart:io' show Directory, File;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:deckionary/core/database/app_database.dart';

/// Creates an in-memory UserDatabase for testing.
UserDatabase createTestUserDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return UserDatabase.forTesting(NativeDatabase.memory());
}

/// Opens the real dictionary database from assets for testing.
/// Requires oald10.db to be present at app/assets/oald10.db.
DictionaryDatabase createTestDictDb() {
  // Resolve path relative to the test runner (which runs from app/)
  final path = '${Directory.current.path}/assets/oald10.db';
  if (!File(path).existsSync()) {
    // Try from repo root
    final altPath = '${Directory.current.path}/app/assets/oald10.db';
    if (File(altPath).existsSync()) {
      return DictionaryDatabase.forTesting(altPath);
    }
    throw StateError('oald10.db not found at $path or $altPath');
  }
  return DictionaryDatabase.forTesting(path);
}

/// Inserts a review card directly into the DB for testing.
Future<void> insertReviewCard(
  UserDatabase db, {
  required String id,
  required int entryId,
  String headword = 'test',
  String pos = 'noun',
  required String due,
  int state = 0,
  int step = 0,
  double stability = 0,
  double difficulty = 0,
  String? lastReview,
}) async {
  await db
      .into(db.reviewCards)
      .insert(
        ReviewCardsCompanion.insert(
          id: id,
          entryId: entryId,
          headword: headword,
          due: due,
          pos: Value(pos),
          stability: Value(stability),
          difficulty: Value(difficulty),
          state: Value(state),
          step: Value(step),
          lastReview: Value(lastReview),
        ),
      );
}

/// Inserts a review log directly into the DB for testing.
Future<void> insertReviewLog(
  UserDatabase db, {
  required String id,
  required String cardId,
  required String reviewedAt,
}) async {
  await db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          id: id,
          cardId: cardId,
          rating: 3,
          state: 2,
          due: DateTime.now().toUtc().toIso8601String(),
          stability: 0,
          difficulty: 0,
          elapsedDays: 0,
          scheduledDays: 0,
          reviewedAt: Value(reviewedAt),
        ),
      );
}
