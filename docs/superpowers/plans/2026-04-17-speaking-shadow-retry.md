# Speaking Coach — Shadow & Try-Again Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Speaking Coach result screen into a practice loop — shadow-record the natural version locally, re-attempt the same topic, and view attempt-by-attempt history synced across devices.

**Architecture:** Extend `speaking_results` with `session_id` + `attempt_number` (Drift v9 → v10 + Supabase migration) so multiple rows can be grouped into one session. Add a `SpeakingSessionNotifier` (Riverpod) that owns the in-memory attempt stack, writes each new attempt to the DB immediately, and clears on session end. Replace the single-result result screen with a stacked attempt UI that also powers the history detail screen in read-only mode. Shadow audio is local-only, temp files.

**Tech Stack:** Flutter, Riverpod, Drift ORM, Supabase (Postgres + edge functions), `record` package (audio capture), `path_provider` (temp dir), `uuid`.

**Spec:** [`docs/superpowers/specs/2026-04-17-speaking-shadow-retry-design.md`](../specs/2026-04-17-speaking-shadow-retry-design.md)

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `app/lib/features/speaking/domain/speaking_attempt.dart` | Domain types: `SpeakingAttempt`, `SpeakingSessionState` |
| `app/lib/features/speaking/providers/speaking_session_notifier.dart` | Riverpod notifier owning the active session |
| `app/lib/features/speaking/presentation/widgets/shadow_block.dart` | Play-model + record-self + play-self controls |
| `app/lib/features/speaking/presentation/widgets/attempt_card.dart` | Single attempt (expanded or collapsed variant) |
| `app/lib/features/speaking/presentation/widgets/attempt_stack.dart` | Ordered list of AttemptCards with collapse state |
| `app/test/features/speaking/speaking_service_test.dart` | Drift-backed service tests for session persistence |
| `app/test/features/speaking/speaking_session_notifier_test.dart` | Notifier behavior tests |
| `supabase/migrations/20260417010000_add_session_to_speaking.sql` | Remote schema migration |

### Modified files

| Path | Change |
|---|---|
| `app/lib/core/database/user_tables.dart` | Add `sessionId`, `attemptNumber` columns to `SpeakingResults` |
| `app/lib/core/database/app_database.dart` | Bump schema to 10; add v10 migration step |
| `app/lib/core/sync/speaking_sync.dart` | Include new columns in push upsert + pull INSERT/UPDATE SQL |
| `app/lib/features/speaking/domain/speaking_service.dart` | `saveResult` gains `sessionId`/`attemptNumber`/returns id; add `getAttemptsBySessionId`; `deleteSession(sessionId)` replaces `deleteResult(id)` |
| `app/lib/features/speaking/providers/speaking_providers.dart` | Drop the ad-hoc `analyzeRecording`/`analyzeText` helpers in favor of notifier methods; rework `speakingHistoryProvider` to group by `session_id`; add `speakingSessionByIdProvider` |
| `app/lib/features/speaking/presentation/widgets/correction_card.dart` | Remove per-correction TTS button + state |
| `app/lib/features/speaking/presentation/speaking_result_screen.dart` | Render `AttemptStack`; Try-again and Done buttons; wire session notifier |
| `app/lib/features/speaking/presentation/speaking_record_screen.dart` | Call `sessionNotifier.addAttempt` instead of `analyzeRecording/Text` helpers; pop or pushReplacement based on `isRetry` flag |
| `app/lib/features/speaking/presentation/speaking_home_screen.dart` | Call `sessionNotifier.startSession(...)` before navigating to record screen |
| `app/lib/features/speaking/presentation/speaking_history_screen.dart` | Show attempt count when > 1; swipe-to-delete calls `deleteSession` |
| `app/lib/features/speaking/presentation/speaking_history_detail_screen.dart` | Render `AttemptStack` in read-only mode; delete button uses `deleteSession` |

---

## Task 1: Drift schema — add session_id and attempt_number

**Files:**
- Modify: `app/lib/core/database/user_tables.dart:144-168`
- Modify: `app/lib/core/database/app_database.dart:35` (schemaVersion) and `app/lib/core/database/app_database.dart:84-86` (migration block)
- Regenerate: `app/lib/core/database/app_database.g.dart` (via build_runner)
- Test: `app/test/features/speaking/speaking_service_test.dart` (new)

- [ ] **Step 1: Add the columns to the Drift table**

In `app/lib/core/database/user_tables.dart`, extend the `SpeakingResults` class. Insert these two column declarations right after the `overallNote` line (currently line 153):

```dart
  TextColumn get sessionId => text().named('session_id').nullable()();
  IntColumn get attemptNumber => integer().named('attempt_number').nullable()();
```

Full block after change (lines starting at `class SpeakingResults`):

```dart
@DataClassName('SpeakingResultRow')
class SpeakingResults extends Table {
  TextColumn get id => text()();
  TextColumn get topic => text()();
  BoolColumn get isCustomTopic =>
      boolean().named('is_custom_topic').withDefault(const Constant(false))();
  TextColumn get transcript => text()();
  TextColumn get correctionsJson => text().named('corrections_json')();
  TextColumn get naturalVersion => text().named('natural_version')();
  TextColumn get overallNote => text().named('overall_note').nullable()();
  TextColumn get sessionId => text().named('session_id').nullable()();
  IntColumn get attemptNumber => integer().named('attempt_number').nullable()();
  TextColumn get createdAt => text()
      .named('created_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get updatedAt => text()
      .named('updated_at')
      .withDefault(Constant(DateTime.now().toIso8601String()))();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();
  IntColumn get synced => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'speaking_results';
}
```

- [ ] **Step 2: Bump the schema version and wire the migration**

In `app/lib/core/database/app_database.dart`:

Change line 35:
```dart
  int get schemaVersion => 10;
```

At the end of the `onUpgrade` block (right before the closing `}` of `onUpgrade`, currently around line 86), add:

```dart
      if (from < 10) {
        await m.addColumn(speakingResults, speakingResults.sessionId);
        await m.addColumn(speakingResults, speakingResults.attemptNumber);
        // Backfill: treat each existing row as a single-attempt session
        await customStatement(
          'UPDATE speaking_results SET session_id = id, attempt_number = 1 '
          'WHERE session_id IS NULL',
        );
      }
```

- [ ] **Step 3: Regenerate Drift code**

Run from `app/`:
```bash
cd app && dart run build_runner build --delete-conflicting-outputs
```

Expected: `app_database.g.dart` regenerated with `sessionId` and `attemptNumber` on `SpeakingResultRow` and `SpeakingResultsCompanion`.

- [ ] **Step 4: Write the failing schema test**

Create `app/test/features/speaking/speaking_service_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/database/app_database.dart';

import '../../test_helpers.dart';

void main() {
  group('SpeakingResults schema v10', () {
    late UserDatabase db;

    setUp(() {
      db = createTestUserDb();
    });

    tearDown(() async {
      await db.close();
    });

    test('inserts a row with session_id and attempt_number', () async {
      await db.into(db.speakingResults).insert(
            SpeakingResultsCompanion.insert(
              id: 'row-1',
              topic: 'weekend plans',
              transcript: 'I go store',
              correctionsJson: '[]',
              naturalVersion: 'I will go to the store',
              sessionId: const Value('session-A'),
              attemptNumber: const Value(1),
            ),
          );

      final rows = await db.select(db.speakingResults).get();
      expect(rows, hasLength(1));
      expect(rows.first.sessionId, 'session-A');
      expect(rows.first.attemptNumber, 1);
    });

    test('allows multiple rows sharing the same session_id', () async {
      for (var i = 1; i <= 3; i++) {
        await db.into(db.speakingResults).insert(
              SpeakingResultsCompanion.insert(
                id: 'row-$i',
                topic: 'weekend plans',
                transcript: 'attempt $i',
                correctionsJson: '[]',
                naturalVersion: 'natural $i',
                sessionId: const Value('session-B'),
                attemptNumber: Value(i),
              ),
            );
      }

      final rows = await (db.select(db.speakingResults)
            ..where((t) => t.sessionId.equals('session-B'))
            ..orderBy([(t) => OrderingTerm.asc(t.attemptNumber)]))
          .get();
      expect(rows.map((r) => r.attemptNumber).toList(), [1, 2, 3]);
    });
  });
}
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
cd app && flutter test test/features/speaking/speaking_service_test.dart
```

Expected: both tests pass.

- [ ] **Step 6: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: no warnings.

- [ ] **Step 7: Commit**

```bash
git add app/lib/core/database/user_tables.dart \
        app/lib/core/database/app_database.dart \
        app/lib/core/database/app_database.g.dart \
        app/test/features/speaking/speaking_service_test.dart
git commit -m "feat(speaking): add session_id and attempt_number to speaking_results (schema v10)"
```

---

## Task 2: SpeakingService — session-aware persistence

**Files:**
- Modify: `app/lib/features/speaking/domain/speaking_service.dart`
- Test: `app/test/features/speaking/speaking_service_test.dart` (extend)

- [ ] **Step 1: Write failing tests for the new service methods**

Append to `app/test/features/speaking/speaking_service_test.dart`:

```dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:deckionary/features/speaking/domain/speaking_result.dart';
import 'package:deckionary/features/speaking/domain/speaking_service.dart';

// At top of file, keep existing imports. Add the above.

// Inside the existing main() {}, add a new group:
  group('SpeakingService.saveAttempt / getAttemptsBySessionId / deleteSession', () {
    late UserDatabase db;
    late SpeakingService service;

    setUp(() {
      db = createTestUserDb();
      // SupabaseClient not used by these methods; pass a dummy via a stub.
      service = SpeakingService(
        db: db,
        supabase: SupabaseClient('http://localhost', 'anon'),
      );
    });

    tearDown(() async {
      await db.close();
    });

    SpeakingResult sampleResult(String suffix) => SpeakingResult(
          transcript: 'transcript-$suffix',
          corrections: const [],
          naturalVersion: 'natural-$suffix',
          overallNote: null,
        );

    test('saveAttempt persists all session fields and returns the row id',
        () async {
      final id = await service.saveAttempt(
        sessionId: 'session-1',
        topic: 'travel',
        isCustomTopic: false,
        attemptNumber: 2,
        result: sampleResult('a'),
      );

      expect(id, isNotEmpty);
      final rows = await db.select(db.speakingResults).get();
      expect(rows, hasLength(1));
      expect(rows.first.id, id);
      expect(rows.first.sessionId, 'session-1');
      expect(rows.first.attemptNumber, 2);
      expect(rows.first.topic, 'travel');
      expect(rows.first.synced, 0);
    });

    test('getAttemptsBySessionId returns attempts in order', () async {
      await service.saveAttempt(
        sessionId: 'session-2',
        topic: 'travel',
        isCustomTopic: false,
        attemptNumber: 1,
        result: sampleResult('a'),
      );
      await service.saveAttempt(
        sessionId: 'session-2',
        topic: 'travel',
        isCustomTopic: false,
        attemptNumber: 2,
        result: sampleResult('b'),
      );

      final rows = await service.getAttemptsBySessionId('session-2');
      expect(rows.map((r) => r.attemptNumber).toList(), [1, 2]);
      expect(rows.first.transcript, 'transcript-a');
    });

    test('deleteSession soft-deletes every row sharing the session_id',
        () async {
      await service.saveAttempt(
        sessionId: 'session-3',
        topic: 'food',
        isCustomTopic: true,
        attemptNumber: 1,
        result: sampleResult('a'),
      );
      await service.saveAttempt(
        sessionId: 'session-3',
        topic: 'food',
        isCustomTopic: true,
        attemptNumber: 2,
        result: sampleResult('b'),
      );

      await service.deleteSession('session-3');

      final rows = await db.select(db.speakingResults).get();
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.deletedAt != null), isTrue);
      expect(rows.every((r) => r.synced == 0), isTrue);
    });

    test('getHistory excludes soft-deleted rows from any session', () async {
      await service.saveAttempt(
        sessionId: 'session-4',
        topic: 'work',
        isCustomTopic: false,
        attemptNumber: 1,
        result: sampleResult('a'),
      );
      await service.deleteSession('session-4');
      final rows = await service.getHistory();
      expect(rows, isEmpty);
    });
  });
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd app && flutter test test/features/speaking/speaking_service_test.dart
```

Expected: compilation failure on `saveAttempt`, `getAttemptsBySessionId`, `deleteSession`.

- [ ] **Step 3: Refactor `SpeakingService`**

Replace the body of `app/lib/features/speaking/domain/speaking_service.dart` with:

```dart
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
    final token = _supabase.auth.currentSession?.accessToken ??
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
      throw Exception('Analysis failed (${streamed.statusCode}): $body');
    }

    return SpeakingResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Analyze typed text.
  Future<SpeakingResult> analyzeText(String text, String topic) async {
    final token = _supabase.auth.currentSession?.accessToken ??
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
      throw Exception(
        'Analysis failed (${response.statusCode}): ${response.body}',
      );
    }

    return SpeakingResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Persist one attempt to the DB. Returns the newly created row id.
  Future<String> saveAttempt({
    required String sessionId,
    required String topic,
    required bool isCustomTopic,
    required int attemptNumber,
    required SpeakingResult result,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final id = const Uuid().v4();
    await _db.into(_db.speakingResults).insert(
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
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  /// Most recent rows, excluding soft-deleted. Callers are responsible for
  /// grouping by session_id.
  Future<List<SpeakingResultRow>> getHistory({int limit = 200}) async {
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
          ..where(
            (t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.attemptNumber)]))
        .get();
  }

  /// Backward-compatible lookup by row id (history detail loaded before
  /// grouping refactor). Prefer getAttemptsBySessionId.
  Future<SpeakingResultRow?> getResultById(String id) async {
    final rows = await (_db.select(_db.speakingResults)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Soft-delete every attempt in a session.
  Future<void> deleteSession(String sessionId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(_db.speakingResults)
          ..where((t) => t.sessionId.equals(sessionId)))
        .write(
      SpeakingResultsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        synced: const Value(0),
      ),
    );
  }
}
```

Note: the old `saveResult` and `deleteResult(id)` methods are removed. Call sites are updated in later tasks.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd app && flutter test test/features/speaking/speaking_service_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/speaking/domain/speaking_service.dart \
        app/test/features/speaking/speaking_service_test.dart
git commit -m "feat(speaking): add session-aware saveAttempt, getAttemptsBySessionId, deleteSession"
```

---

## Task 3: Sync layer — include new columns

**Files:**
- Modify: `app/lib/core/sync/speaking_sync.dart:37-51` (push payload) and `:97-116`, `:138-158` (pull SQL)

- [ ] **Step 1: Update push payload**

In `app/lib/core/sync/speaking_sync.dart`, replace the `_supabase.from('speaking_results').upsert({...})` block (around line 39) to include the new fields:

```dart
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
          'created_at': data['created_at'],
          'updated_at': data['updated_at'],
          'deleted_at': data['deleted_at'],
        });
```

- [ ] **Step 2: Update pull INSERT**

Replace the INSERT block (around line 97-116) with:

```dart
      await _db.customInsert(
        '''INSERT INTO speaking_results
           (id, topic, is_custom_topic, transcript, corrections_json,
            natural_version, overall_note, session_id, attempt_number,
            created_at, updated_at, synced)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)''',
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
          Variable.withString(row['created_at'] as String),
          Variable.withString(remoteUpdatedAt),
        ],
        updates: {_db.speakingResults},
      );
```

- [ ] **Step 3: Update pull UPDATE**

Replace the UPDATE block (around line 138-158) with:

```dart
        await _db.customUpdate(
          '''UPDATE speaking_results SET
             topic = ?, is_custom_topic = ?, transcript = ?,
             corrections_json = ?, natural_version = ?, overall_note = ?,
             session_id = ?, attempt_number = ?,
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
            Variable.withString(remoteUpdatedAt),
            Variable.withString(id),
          ],
          updates: {_db.speakingResults},
        );
```

- [ ] **Step 4: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: no warnings.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/sync/speaking_sync.dart
git commit -m "feat(speaking): sync session_id and attempt_number columns"
```

---

## Task 4: Supabase migration

**Files:**
- Create: `supabase/migrations/20260417010000_add_session_to_speaking.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260417010000_add_session_to_speaking.sql`:

```sql
-- Add session_id and attempt_number to speaking_results so multiple attempts
-- on the same topic can be grouped into a single practice session.

ALTER TABLE public.speaking_results
  ADD COLUMN IF NOT EXISTS session_id TEXT,
  ADD COLUMN IF NOT EXISTS attempt_number INTEGER;

-- Backfill: treat every existing row as a one-attempt session.
UPDATE public.speaking_results
   SET session_id = id,
       attempt_number = 1
 WHERE session_id IS NULL;

-- Helpful index for history-by-session queries.
CREATE INDEX IF NOT EXISTS speaking_results_session_id_idx
  ON public.speaking_results(session_id);
```

- [ ] **Step 2: Apply locally and verify**

```bash
supabase db reset
```

Expected: `20260417010000_add_session_to_speaking.sql` applies cleanly. No errors.

Verify columns exist:
```bash
supabase db execute "SELECT column_name FROM information_schema.columns WHERE table_name='speaking_results' AND column_name IN ('session_id','attempt_number');"
```
Expected: two rows.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260417010000_add_session_to_speaking.sql
git commit -m "feat(speaking): add session_id and attempt_number to remote speaking_results"
```

---

## Task 5: Domain types — SpeakingAttempt + SpeakingSessionState

**Files:**
- Create: `app/lib/features/speaking/domain/speaking_attempt.dart`

- [ ] **Step 1: Write the domain types**

Create `app/lib/features/speaking/domain/speaking_attempt.dart`:

```dart
import 'speaking_result.dart';

/// One recorded attempt in a practice session. Pairs the LLM-analyzed result
/// with the optional local shadow-recording path.
class SpeakingAttempt {
  final String id; // = speaking_results.id
  final int attemptNumber; // 1-indexed within the session
  final SpeakingResult result;
  final String? shadowAudioPath; // local temp file; null until recorded
  final DateTime createdAt;

  const SpeakingAttempt({
    required this.id,
    required this.attemptNumber,
    required this.result,
    required this.createdAt,
    this.shadowAudioPath,
  });

  SpeakingAttempt copyWith({String? shadowAudioPath, bool clearShadow = false}) {
    return SpeakingAttempt(
      id: id,
      attemptNumber: attemptNumber,
      result: result,
      createdAt: createdAt,
      shadowAudioPath: clearShadow ? null : (shadowAudioPath ?? this.shadowAudioPath),
    );
  }
}

/// In-memory state for the currently active practice session.
class SpeakingSessionState {
  final String sessionId;
  final String topic;
  final bool isCustomTopic;
  final List<SpeakingAttempt> attempts; // index 0 = oldest (attempt 1)

  const SpeakingSessionState({
    required this.sessionId,
    required this.topic,
    required this.isCustomTopic,
    required this.attempts,
  });

  SpeakingSessionState copyWith({List<SpeakingAttempt>? attempts}) {
    return SpeakingSessionState(
      sessionId: sessionId,
      topic: topic,
      isCustomTopic: isCustomTopic,
      attempts: attempts ?? this.attempts,
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: no warnings.

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/speaking/domain/speaking_attempt.dart
git commit -m "feat(speaking): add SpeakingAttempt and SpeakingSessionState domain types"
```

---

## Task 6: SpeakingSessionNotifier — active session state

**Files:**
- Create: `app/lib/features/speaking/providers/speaking_session_notifier.dart`
- Test: `app/test/features/speaking/speaking_session_notifier_test.dart`

- [ ] **Step 1: Write the failing notifier test**

Create `app/test/features/speaking/speaking_session_notifier_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/core/database/database_provider.dart';
import 'package:deckionary/features/speaking/domain/speaking_result.dart';
import 'package:deckionary/features/speaking/domain/speaking_service.dart';
import 'package:deckionary/features/speaking/providers/speaking_providers.dart';
import 'package:deckionary/features/speaking/providers/speaking_session_notifier.dart';

import '../../test_helpers.dart';

class _FakeSpeakingService extends SpeakingService {
  final SpeakingResult stubbed;
  _FakeSpeakingService({
    required super.db,
    required super.supabase,
    required this.stubbed,
  });

  @override
  Future<SpeakingResult> analyzeRecording(Uint8List audioBytes, String topic) async =>
      stubbed;

  @override
  Future<SpeakingResult> analyzeText(String text, String topic) async => stubbed;
}

void main() {
  group('SpeakingSessionNotifier', () {
    late UserDatabase db;
    late ProviderContainer container;

    SpeakingResult result(String suffix) => SpeakingResult(
          transcript: 'transcript-$suffix',
          corrections: const [],
          naturalVersion: 'natural-$suffix',
        );

    setUp(() {
      db = createTestUserDb();
      container = ProviderContainer(overrides: [
        userDbProvider.overrideWithValue(db),
        speakingServiceProvider.overrideWithValue(
          _FakeSpeakingService(
            db: db,
            supabase: SupabaseClient('http://localhost', 'anon'),
            stubbed: result('stub'),
          ),
        ),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('startSession initializes an empty session', () {
      container
          .read(speakingSessionNotifierProvider.notifier)
          .startSession(topic: 'travel', isCustomTopic: false);
      final state = container.read(speakingSessionNotifierProvider);
      expect(state, isNotNull);
      expect(state!.topic, 'travel');
      expect(state.attempts, isEmpty);
      expect(state.sessionId, isNotEmpty);
    });

    test('addAttemptFromText persists a row and appends to state', () async {
      final notifier = container.read(speakingSessionNotifierProvider.notifier);
      notifier.startSession(topic: 'travel', isCustomTopic: false);
      await notifier.addAttemptFromText('hello world');

      final state = container.read(speakingSessionNotifierProvider)!;
      expect(state.attempts, hasLength(1));
      expect(state.attempts.first.attemptNumber, 1);
      expect(state.attempts.first.result.transcript, 'transcript-stub');

      final dbRows = await db.select(db.speakingResults).get();
      expect(dbRows, hasLength(1));
      expect(dbRows.first.sessionId, state.sessionId);
      expect(dbRows.first.attemptNumber, 1);
    });

    test('second attempt increments attemptNumber and keeps the session id',
        () async {
      final notifier = container.read(speakingSessionNotifierProvider.notifier);
      notifier.startSession(topic: 'food', isCustomTopic: true);
      await notifier.addAttemptFromText('first');
      await notifier.addAttemptFromText('second');

      final state = container.read(speakingSessionNotifierProvider)!;
      expect(state.attempts.map((a) => a.attemptNumber).toList(), [1, 2]);

      final dbRows = await (db.select(db.speakingResults)
            ..orderBy([(t) => OrderingTerm.asc(t.attemptNumber)]))
          .get();
      expect(dbRows, hasLength(2));
      expect(dbRows.every((r) => r.sessionId == state.sessionId), isTrue);
    });

    test('endSession deletes shadow files and clears state', () async {
      final notifier = container.read(speakingSessionNotifierProvider.notifier);
      notifier.startSession(topic: 'work', isCustomTopic: false);
      await notifier.addAttemptFromText('first');

      final tmp = File('${Directory.systemTemp.path}/shadow_dummy.wav');
      await tmp.writeAsBytes([0, 1, 2]);
      final attemptId =
          container.read(speakingSessionNotifierProvider)!.attempts.first.id;
      notifier.setShadowAudio(attemptId: attemptId, path: tmp.path);

      await notifier.endSession();

      expect(container.read(speakingSessionNotifierProvider), isNull);
      expect(tmp.existsSync(), isFalse);
    });
  });
}
```

Note: the test uses Drift's `OrderingTerm`, so keep `import 'package:drift/drift.dart';` at the top if the analyzer complains about the missing import.

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/features/speaking/speaking_session_notifier_test.dart
```

Expected: compilation failure on `speakingSessionNotifierProvider`, `SpeakingSessionNotifier`.

- [ ] **Step 3: Create the notifier**

Create `app/lib/features/speaking/providers/speaking_session_notifier.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/speaking_attempt.dart';
import '../domain/speaking_result.dart';
import 'speaking_providers.dart';

class SpeakingSessionNotifier extends Notifier<SpeakingSessionState?> {
  @override
  SpeakingSessionState? build() => null;

  void startSession({required String topic, required bool isCustomTopic}) {
    state = SpeakingSessionState(
      sessionId: const Uuid().v4(),
      topic: topic,
      isCustomTopic: isCustomTopic,
      attempts: const [],
    );
  }

  /// Record + analyze + persist a voice attempt. Caller is responsible for
  /// navigation. Throws on analysis / persistence failure.
  Future<SpeakingAttempt> addAttemptFromAudio(Uint8List audioBytes) async {
    final session = state;
    if (session == null) {
      throw StateError('addAttemptFromAudio called with no active session');
    }
    final service = ref.read(speakingServiceProvider);
    if (service == null) {
      throw StateError('Speaking service unavailable (sync disabled?)');
    }
    final result = await service.analyzeRecording(audioBytes, session.topic);
    return _appendAttempt(service, session, result);
  }

  /// Same as above but for typed text.
  Future<SpeakingAttempt> addAttemptFromText(String text) async {
    final session = state;
    if (session == null) {
      throw StateError('addAttemptFromText called with no active session');
    }
    final service = ref.read(speakingServiceProvider);
    if (service == null) {
      throw StateError('Speaking service unavailable (sync disabled?)');
    }
    final result = await service.analyzeText(text, session.topic);
    return _appendAttempt(service, session, result);
  }

  Future<SpeakingAttempt> _appendAttempt(
    service,
    SpeakingSessionState session,
    SpeakingResult result,
  ) async {
    final attemptNumber = session.attempts.length + 1;
    final id = await service.saveAttempt(
      sessionId: session.sessionId,
      topic: session.topic,
      isCustomTopic: session.isCustomTopic,
      attemptNumber: attemptNumber,
      result: result,
    );
    final attempt = SpeakingAttempt(
      id: id,
      attemptNumber: attemptNumber,
      result: result,
      createdAt: DateTime.now(),
    );
    state = session.copyWith(attempts: [...session.attempts, attempt]);
    ref.invalidate(speakingHistoryProvider);
    return attempt;
  }

  void setShadowAudio({required String attemptId, required String path}) {
    final session = state;
    if (session == null) return;
    final updated = session.attempts
        .map((a) => a.id == attemptId ? a.copyWith(shadowAudioPath: path) : a)
        .toList(growable: false);
    state = session.copyWith(attempts: updated);
  }

  Future<void> clearShadowAudio(String attemptId) async {
    final session = state;
    if (session == null) return;
    for (final attempt in session.attempts) {
      if (attempt.id == attemptId && attempt.shadowAudioPath != null) {
        final f = File(attempt.shadowAudioPath!);
        if (f.existsSync()) await f.delete();
      }
    }
    final updated = session.attempts
        .map((a) => a.id == attemptId ? a.copyWith(clearShadow: true) : a)
        .toList(growable: false);
    state = session.copyWith(attempts: updated);
  }

  /// Delete all shadow files for the active session and clear state.
  /// DB rows are NOT deleted — they've been persisted per-attempt.
  Future<void> endSession() async {
    final session = state;
    if (session == null) return;
    for (final attempt in session.attempts) {
      final path = attempt.shadowAudioPath;
      if (path != null) {
        final f = File(path);
        if (f.existsSync()) await f.delete();
      }
    }
    state = null;
  }
}

final speakingSessionNotifierProvider =
    NotifierProvider<SpeakingSessionNotifier, SpeakingSessionState?>(
  SpeakingSessionNotifier.new,
);
```

- [ ] **Step 4: Fix the helper signature**

The `_appendAttempt` parameter `service` needs a type. Update:

```dart
  Future<SpeakingAttempt> _appendAttempt(
    SpeakingService service,
    SpeakingSessionState session,
    SpeakingResult result,
  ) async {
```

Add import at top:
```dart
import '../domain/speaking_service.dart';
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd app && flutter test test/features/speaking/speaking_session_notifier_test.dart
```

Expected: all four tests pass.

- [ ] **Step 6: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: no warnings.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/speaking/providers/speaking_session_notifier.dart \
        app/test/features/speaking/speaking_session_notifier_test.dart
git commit -m "feat(speaking): add SpeakingSessionNotifier for in-memory attempt stack"
```

---

## Task 7: History providers — group by session_id

**Files:**
- Modify: `app/lib/features/speaking/providers/speaking_providers.dart`

- [ ] **Step 1: Rewrite the history provider (keep `speakingResultByIdProvider` alive)**

In `app/lib/features/speaking/providers/speaking_providers.dart`, replace the `speakingHistoryProvider` and the `SpeakingHistoryItem` class (currently lines 83-121) with the grouped version below. **Leave `speakingResultByIdProvider` untouched** — the history detail screen still uses it; Task 15 replaces it with the new session-based provider.

```dart
// ── History (grouped by session_id) ─────────────────────────────────────────

final speakingHistoryProvider = FutureProvider<List<SpeakingHistoryItem>>((
  ref,
) async {
  final service = ref.watch(speakingServiceProvider);
  if (service == null) return [];
  final rows = await service.getHistory();

  // Group by session_id; fall back to row id for legacy rows where session_id
  // is null (should not happen post-migration, but defensively handled).
  final Map<String, List<SpeakingResultRow>> bySession = {};
  for (final row in rows) {
    final key = row.sessionId ?? row.id;
    bySession.putIfAbsent(key, () => []).add(row);
  }

  final items = bySession.entries.map((entry) {
    final sessionRows = entry.value
      ..sort((a, b) => (a.attemptNumber ?? 1).compareTo(b.attemptNumber ?? 1));
    final latest = sessionRows.last;
    var count = 0;
    try {
      final list = jsonDecode(latest.correctionsJson);
      if (list is List) count = list.length;
    } catch (_) {}
    return SpeakingHistoryItem(
      sessionId: entry.key,
      topic: latest.topic,
      isCustomTopic: latest.isCustomTopic,
      correctionsCount: count,
      attemptCount: sessionRows.length,
      createdAt: DateTime.parse(latest.createdAt),
    );
  }).toList();

  items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return items;
});

class SpeakingHistoryItem {
  final String sessionId;
  final String topic;
  final bool isCustomTopic;
  final int correctionsCount; // from the latest attempt
  final int attemptCount;
  final DateTime createdAt; // latest attempt's createdAt

  const SpeakingHistoryItem({
    required this.sessionId,
    required this.topic,
    required this.isCustomTopic,
    required this.correctionsCount,
    required this.attemptCount,
    required this.createdAt,
  });
}

/// Loads all attempts for one session (for history detail screen).
final speakingSessionByIdProvider =
    FutureProvider.family<SpeakingHistorySession?, String>((ref, sessionId) async {
  final service = ref.watch(speakingServiceProvider);
  if (service == null) return null;
  final rows = await service.getAttemptsBySessionId(sessionId);
  if (rows.isEmpty) return null;
  final attempts = rows.map(_rowToAttempt).toList();
  return SpeakingHistorySession(
    sessionId: sessionId,
    topic: rows.first.topic,
    isCustomTopic: rows.first.isCustomTopic,
    attempts: attempts,
  );
});

SpeakingAttempt _rowToAttempt(SpeakingResultRow row) {
  final corrections = (jsonDecode(row.correctionsJson) as List)
      .map((e) => SpeakingCorrection.fromJson(e as Map<String, dynamic>))
      .toList();
  final result = SpeakingResult(
    transcript: row.transcript,
    corrections: corrections,
    naturalVersion: row.naturalVersion,
    overallNote: row.overallNote,
  );
  return SpeakingAttempt(
    id: row.id,
    attemptNumber: row.attemptNumber ?? 1,
    result: result,
    createdAt: DateTime.parse(row.createdAt),
  );
}

/// Read-only snapshot of a past session loaded from the DB.
class SpeakingHistorySession {
  final String sessionId;
  final String topic;
  final bool isCustomTopic;
  final List<SpeakingAttempt> attempts;

  const SpeakingHistorySession({
    required this.sessionId,
    required this.topic,
    required this.isCustomTopic,
    required this.attempts,
  });
}
```

- [ ] **Step 2: Remove the old helper functions and orphan imports**

Delete the `analyzeRecording(WidgetRef ref, ...)` and `analyzeText(WidgetRef ref, ...)` top-level functions (currently lines 144-177). They are replaced by the notifier methods.

Add the required imports at the top of the file (keep existing ones):
```dart
import '../domain/speaking_attempt.dart';
import '../../../core/database/app_database.dart' show SpeakingResultRow;
```

- [ ] **Step 3: Update the history list screen for the new item shape**

In `app/lib/features/speaking/presentation/speaking_history_screen.dart`:

- The `Dismissible` key changes from `ValueKey(item.id)` to `ValueKey(item.sessionId)`.
- `confirmDismiss` now calls `await service?.deleteSession(item.sessionId)` (replacing `deleteResult(item.id)`).
- Update the `Navigator.push` inside `onTap` to pass `sessionId` (the history detail constructor still accepts `id`-equivalent — we rename the param here too; Task 15 does the full rewrite):

```dart
onTap: () => Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => SpeakingHistoryDetailScreen(
      id: item.sessionId, // single-attempt legacy rows have sessionId == id
      topic: item.topic,
    ),
  ),
),
```

- Update the correction-count badge to include attempt count when > 1:

```dart
_Badge(
  label: item.attemptCount > 1
      ? '${item.attemptCount} attempts · ${item.correctionsCount} ${item.correctionsCount == 1 ? 'correction' : 'corrections'}'
      : '${item.correctionsCount} ${item.correctionsCount == 1 ? 'correction' : 'corrections'}',
  color: item.correctionsCount >= 2 ? Colors.red : Colors.green,
),
```

This keeps the existing `SpeakingHistoryDetailScreen` working unchanged in this task — Task 15 rewrites it.

- [ ] **Step 4: Fix the analyze-helper removal fallout**

The `analyzeRecording(WidgetRef ref, ...)` / `analyzeText(WidgetRef ref, ...)` removals break `speaking_record_screen.dart`. Temporarily add stubs at the bottom of `speaking_providers.dart` that delegate to the notifier, to keep the file compiling. Task 12 removes these stubs when the record screen is rewritten:

```dart
// Temporary shims — removed in Task 12.
Future<SpeakingResult> analyzeRecording(
  WidgetRef ref, {
  required Uint8List audioBytes,
  required String topic,
  required bool isCustomTopic,
}) async {
  throw UnimplementedError(
    'analyzeRecording(ref, ...) is deprecated — use SpeakingSessionNotifier',
  );
}

Future<SpeakingResult> analyzeText(
  WidgetRef ref, {
  required String text,
  required String topic,
  required bool isCustomTopic,
}) async {
  throw UnimplementedError(
    'analyzeText(ref, ...) is deprecated — use SpeakingSessionNotifier',
  );
}
```

Keep the existing imports (`dart:typed_data`, etc.) intact.

- [ ] **Step 5: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: clean build. (The runtime `UnimplementedError` only fires if someone actually invokes those functions — which currently is the record screen. Don't run the app yet; Task 12 removes this code path.)

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/speaking/providers/speaking_providers.dart \
        app/lib/features/speaking/presentation/speaking_history_screen.dart
git commit -m "feat(speaking): group history by session_id and expose SpeakingHistorySession"
```

---

## Task 8: Remove TTS from CorrectionCard

**Files:**
- Modify: `app/lib/features/speaking/presentation/widgets/correction_card.dart`

- [ ] **Step 1: Rewrite `CorrectionCard` as a stateless text-only widget**

Replace the entire contents of `app/lib/features/speaking/presentation/widgets/correction_card.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../domain/speaking_result.dart';

class CorrectionCard extends StatelessWidget {
  final SpeakingCorrection correction;

  const CorrectionCard({super.key, required this.correction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You said: ', style: textTheme.labelMedium),
                Expanded(
                  child: Text(
                    correction.original,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.error,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('More natural: ', style: textTheme.labelMedium),
                Expanded(
                  child: Text(
                    correction.natural,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Why: ${correction.explanation}',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
```

Notes: removed the `_CorrectionCardState`, the Riverpod dependency, the TTS play button, and the import of `speaking_providers.dart`.

- [ ] **Step 2: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: no new warnings from this file.

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/speaking/presentation/widgets/correction_card.dart
git commit -m "refactor(speaking): make CorrectionCard text-only (drop per-correction TTS)"
```

---

## Task 9: ShadowBlock widget

**Files:**
- Create: `app/lib/features/speaking/presentation/widgets/shadow_block.dart`

- [ ] **Step 1: Write the widget**

Create `app/lib/features/speaking/presentation/widgets/shadow_block.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../providers/speaking_providers.dart';
import '../../providers/speaking_session_notifier.dart';

/// Natural-version playback + local shadow recording controls for a single
/// attempt. Shadow audio is stored on the session notifier and deleted on
/// session end.
class ShadowBlock extends ConsumerStatefulWidget {
  final String attemptId;
  final String naturalVersion;
  final String? shadowAudioPath;

  const ShadowBlock({
    super.key,
    required this.attemptId,
    required this.naturalVersion,
    required this.shadowAudioPath,
  });

  @override
  ConsumerState<ShadowBlock> createState() => _ShadowBlockState();
}

class _ShadowBlockState extends ConsumerState<ShadowBlock> {
  final _recorder = AudioRecorder();
  bool _loadingModel = false;
  bool _isRecording = false;
  bool _isPlayingShadow = false;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _playModel() async {
    final tts = ref.read(ttsCacheServiceProvider);
    if (tts == null) return;
    setState(() => _loadingModel = true);
    try {
      await tts.play(widget.naturalVersion);
    } finally {
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        ref.read(speakingSessionNotifierProvider.notifier).setShadowAudio(
              attemptId: widget.attemptId,
              path: path,
            );
      }
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final shadowDir = Directory('${dir.path}/speaking_shadow');
    if (!shadowDir.existsSync()) shadowDir.createSync(recursive: true);
    final path =
        '${shadowDir.path}/${const Uuid().v4()}.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: path,
    );
    setState(() => _isRecording = true);
  }

  Future<void> _playShadow() async {
    // Minimal playback using the platform default for WAV files via the record
    // package is not supported; use the existing TTS player's underlying
    // AudioPlayer instead? For v1 keep it simple: just emit a snackbar hint if
    // we don't have a player. The room-level solution is to introduce a shared
    // local player; that lives in Task 15 follow-up if needed.
    final path = widget.shadowAudioPath;
    if (path == null || !File(path).existsSync()) return;
    setState(() => _isPlayingShadow = true);
    try {
      // TtsCacheService exposes play(url) for remote audio. For local files
      // we reuse the just_audio path via a lightweight adapter — for this
      // iteration we invoke it through a new helper on TtsCacheService.
      final tts = ref.read(ttsCacheServiceProvider);
      await tts?.playLocalFile(path);
    } finally {
      if (mounted) setState(() => _isPlayingShadow = false);
    }
  }

  Future<void> _clearShadow() async {
    await ref
        .read(speakingSessionNotifierProvider.notifier)
        .clearShadowAudio(widget.attemptId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasShadow = widget.shadowAudioPath != null &&
        File(widget.shadowAudioPath!).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Shadow practice',
              style: textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_loadingModel)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.volume_up),
                tooltip: 'Play model',
                onPressed: _playModel,
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            FilledButton.tonalIcon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Stop' : 'Record'),
              onPressed: _toggleRecord,
            ),
            const SizedBox(width: 8),
            if (hasShadow) ...[
              IconButton(
                icon: Icon(_isPlayingShadow ? Icons.graphic_eq : Icons.play_arrow),
                tooltip: 'Play your shadow',
                onPressed: _isPlayingShadow ? null : _playShadow,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Re-record',
                onPressed: _clearShadow,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Add `playLocalFile` to `TtsCacheService`**

Check if `app/lib/features/speaking/domain/tts_cache_service.dart` already exposes a way to play an arbitrary local file. If not, add:

```dart
  Future<void> playLocalFile(String path) async {
    await _player.setFilePath(path);
    await _player.play();
  }
```

(Adjust to the service's actual player API. `_player` is the internal `AudioPlayer` instance used by `play(text)`.)

- [ ] **Step 3: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: no warnings.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/speaking/presentation/widgets/shadow_block.dart \
        app/lib/features/speaking/domain/tts_cache_service.dart
git commit -m "feat(speaking): add ShadowBlock widget for local shadow recording"
```

---

## Task 10: AttemptCard widget

**Files:**
- Create: `app/lib/features/speaking/presentation/widgets/attempt_card.dart`

- [ ] **Step 1: Write the widget**

Create `app/lib/features/speaking/presentation/widgets/attempt_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/speaking_attempt.dart';
import 'correction_card.dart';
import 'shadow_block.dart';

class AttemptCard extends StatelessWidget {
  final SpeakingAttempt attempt;
  final int totalAttempts;
  final bool expanded;
  final bool readOnly; // true in history detail — suppresses ShadowBlock controls
  final VoidCallback onToggle;

  const AttemptCard({
    super.key,
    required this.attempt,
    required this.totalAttempts,
    required this.expanded,
    required this.readOnly,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final result = attempt.result;
    final corrections = result.corrections;

    if (!expanded) {
      return InkWell(
        onTap: onToggle,
        child: Card(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Attempt ${attempt.attemptNumber}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${corrections.length} ${corrections.length == 1 ? 'correction' : 'corrections'}',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Icon(Icons.expand_more, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  'Attempt ${attempt.attemptNumber} of $totalAttempts',
                  style: textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(Icons.expand_less, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),

        // Transcript
        Card(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your transcript',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  result.transcript,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),

        // Overall note
        if (result.overallNote != null)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.thumb_up_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result.overallNote!,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: cs.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Natural version + shadow block
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Natural version',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(result.naturalVersion, style: textTheme.bodyMedium),
                const SizedBox(height: 12),
                if (readOnly)
                  _ReadOnlyModelPlayer(text: result.naturalVersion)
                else
                  ShadowBlock(
                    attemptId: attempt.id,
                    naturalVersion: result.naturalVersion,
                    shadowAudioPath: attempt.shadowAudioPath,
                  ),
              ],
            ),
          ),
        ),

        // Corrections
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Corrections (${corrections.length} found)',
            style:
                textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (corrections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'No corrections needed -- great job!',
              style: textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          ...corrections.map((c) => CorrectionCard(correction: c)),

        const SizedBox(height: 8),
        const Divider(height: 32),
      ],
    );
  }
}

class _ReadOnlyModelPlayer extends StatefulWidget {
  final String text;
  const _ReadOnlyModelPlayer({required this.text});

  @override
  State<_ReadOnlyModelPlayer> createState() => _ReadOnlyModelPlayerState();
}

class _ReadOnlyModelPlayerState extends State<_ReadOnlyModelPlayer> {
  @override
  Widget build(BuildContext context) {
    // Read-only history view: only a play-model affordance, no record.
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.volume_up),
          tooltip: 'Play model',
          onPressed: () {
            // Intentionally delegates to a Riverpod callsite. We implement
            // a minimal version via a ConsumerStatefulWidget wrapper.
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Replace `_ReadOnlyModelPlayer` with a Consumer-backed version**

The placeholder in Step 1 doesn't actually wire to TTS. Replace the whole `_ReadOnlyModelPlayer` class with a consumer:

```dart
class _ReadOnlyModelPlayer extends ConsumerStatefulWidget {
  final String text;
  const _ReadOnlyModelPlayer({required this.text});

  @override
  ConsumerState<_ReadOnlyModelPlayer> createState() =>
      _ReadOnlyModelPlayerState();
}

class _ReadOnlyModelPlayerState extends ConsumerState<_ReadOnlyModelPlayer> {
  bool _loading = false;

  Future<void> _play() async {
    final tts = ref.read(ttsCacheServiceProvider);
    if (tts == null) return;
    setState(() => _loading = true);
    try {
      await tts.play(widget.text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return IconButton(
      icon: const Icon(Icons.volume_up),
      tooltip: 'Play model',
      onPressed: _play,
    );
  }
}
```

Add at the top of the file:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/speaking_providers.dart';
```

- [ ] **Step 3: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: no warnings.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/speaking/presentation/widgets/attempt_card.dart
git commit -m "feat(speaking): add AttemptCard widget (expanded/collapsed + readOnly)"
```

---

## Task 11: AttemptStack widget

**Files:**
- Create: `app/lib/features/speaking/presentation/widgets/attempt_stack.dart`

- [ ] **Step 1: Write the widget**

Create `app/lib/features/speaking/presentation/widgets/attempt_stack.dart`:

```dart
import 'package:flutter/material.dart';

import '../../domain/speaking_attempt.dart';
import 'attempt_card.dart';

/// Renders a list of attempts with the newest expanded on top and older ones
/// collapsed. Tapping a collapsed card expands it (and collapses the other
/// expanded one — single-expansion model keeps the screen from growing huge).
///
/// readOnly: used by the history detail screen to suppress record controls.
class AttemptStack extends StatefulWidget {
  final List<SpeakingAttempt> attempts; // index 0 = oldest
  final bool readOnly;

  const AttemptStack({
    super.key,
    required this.attempts,
    this.readOnly = false,
  });

  @override
  State<AttemptStack> createState() => _AttemptStackState();
}

class _AttemptStackState extends State<AttemptStack> {
  // Id of the currently expanded attempt. Defaults to the newest.
  String? _expandedId;

  @override
  void didUpdateWidget(covariant AttemptStack old) {
    super.didUpdateWidget(old);
    // When a new attempt arrives, auto-expand it.
    if (widget.attempts.isNotEmpty && widget.attempts.length > old.attempts.length) {
      _expandedId = widget.attempts.last.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordered = [...widget.attempts].reversed.toList(); // newest first
    final expandedId = _expandedId ??
        (ordered.isNotEmpty ? ordered.first.id : null);
    final total = widget.attempts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attempt in ordered)
          AttemptCard(
            key: ValueKey(attempt.id),
            attempt: attempt,
            totalAttempts: total,
            expanded: attempt.id == expandedId,
            readOnly: widget.readOnly,
            onToggle: () {
              setState(() {
                _expandedId = attempt.id == expandedId ? null : attempt.id;
              });
            },
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: no warnings.

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/speaking/presentation/widgets/attempt_stack.dart
git commit -m "feat(speaking): add AttemptStack widget (auto-expand newest)"
```

---

## Task 12: Wire the record screen to the session notifier

**Files:**
- Modify: `app/lib/features/speaking/presentation/speaking_record_screen.dart`

- [ ] **Step 1: Replace navigation and analysis paths**

Rewrite `app/lib/features/speaking/presentation/speaking_record_screen.dart` to read the topic from the session notifier and to pop vs. pushReplacement based on an `isRetry` flag.

Key changes (full rewrite for clarity):

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../providers/speaking_providers.dart';
import '../providers/speaking_session_notifier.dart';
import 'speaking_result_screen.dart';

class SpeakingRecordScreen extends ConsumerStatefulWidget {
  /// true when launched from the result screen's Try-again button — the
  /// result screen is already on the nav stack, so this screen just pops.
  final bool isRetry;

  const SpeakingRecordScreen({super.key, this.isRetry = false});

  @override
  ConsumerState<SpeakingRecordScreen> createState() =>
      _SpeakingRecordScreenState();
}

class _SpeakingRecordScreenState extends ConsumerState<SpeakingRecordScreen> {
  final _recorder = AudioRecorder();
  final _textController = TextEditingController();
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final status = ref.read(recordingStatusProvider);
    if (status == RecordingStatus.recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return;

      final dir = await getApplicationDocumentsDirectory();
      final tempPath = '${dir.path}/_speaking_recording.wav';

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: tempPath,
      );
      _elapsedSeconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsedSeconds++);
      });

      ref.read(recordingStatusProvider.notifier).set(RecordingStatus.recording);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (path == null) return;
    ref.read(recordingStatusProvider.notifier).set(RecordingStatus.processing);

    try {
      final audioBytes = await File(path).readAsBytes();
      await ref
          .read(speakingSessionNotifierProvider.notifier)
          .addAttemptFromAudio(audioBytes);
      _navigateOnSuccess();
    } catch (e) {
      _handleError(e);
    }
  }

  Future<void> _submitText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    ref.read(recordingStatusProvider.notifier).set(RecordingStatus.processing);

    try {
      await ref
          .read(speakingSessionNotifierProvider.notifier)
          .addAttemptFromText(text);
      _navigateOnSuccess();
    } catch (e) {
      _handleError(e);
    }
  }

  void _navigateOnSuccess() {
    if (!mounted) return;
    ref.read(recordingStatusProvider.notifier).set(RecordingStatus.idle);
    if (widget.isRetry) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SpeakingResultScreen()),
      );
    }
  }

  void _handleError(Object error) {
    if (!mounted) return;
    ref.read(recordingStatusProvider.notifier).set(RecordingStatus.idle);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Analysis failed: $error')),
    );
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(speakingSessionNotifierProvider);
    final topicLabel = session?.topic ?? '';
    final inputMode = ref.watch(inputModeProvider);
    final recordingStatus = ref.watch(recordingStatusProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(topicLabel,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: SegmentedButton<InputMode>(
                  segments: const [
                    ButtonSegment(
                      value: InputMode.speaking,
                      label: Text('Speak'),
                      icon: Icon(Icons.mic),
                    ),
                    ButtonSegment(
                      value: InputMode.typing,
                      label: Text('Type'),
                      icon: Icon(Icons.keyboard),
                    ),
                  ],
                  selected: {inputMode},
                  onSelectionChanged: recordingStatus != RecordingStatus.idle
                      ? null
                      : (modes) => ref
                            .read(inputModeProvider.notifier)
                            .set(modes.first),
                ),
              ),
            ),
            Expanded(
              child: recordingStatus == RecordingStatus.processing
                  ? _buildProcessing()
                  : inputMode == InputMode.speaking
                      ? Center(child: _buildSpeakMode(cs, recordingStatus))
                      : _buildTypeMode(cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessing() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Analyzing your response...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSpeakMode(ColorScheme cs, RecordingStatus status) {
    final isRecording = status == RecordingStatus.recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRecording) ...[
          Text(
            _formatDuration(_elapsedSeconds),
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w300,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text('Recording...',
              style: TextStyle(color: cs.error, fontSize: 14)),
        ] else
          Text(
            'Tap to start recording',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
          ),
        const SizedBox(height: 40),
        SizedBox(
          width: 80,
          height: 80,
          child: FloatingActionButton.large(
            heroTag: 'mic_button',
            backgroundColor: isRecording ? cs.error : cs.primary,
            foregroundColor: isRecording ? cs.onError : cs.onPrimary,
            onPressed: _toggleRecording,
            child: Icon(isRecording ? Icons.stop : Icons.mic, size: 36),
          ),
        ),
        const SizedBox(height: 16),
        if (isRecording)
          Text('Tap to stop',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      ],
    );
  }

  Widget _buildTypeMode(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Type your response here...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Submit'),
              onPressed: _submitText,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: `SpeakingResultScreen` constructor mismatch (it still takes the old params). That's fixed in Task 13. Keep going.

- [ ] **Step 3: Do not commit yet — this compiles only after Task 13**

Leave uncommitted until the result screen is updated.

---

## Task 13: Live result screen — AttemptStack + Try again

**Files:**
- Modify: `app/lib/features/speaking/presentation/speaking_result_screen.dart`

- [ ] **Step 1: Rewrite the result screen**

Replace `app/lib/features/speaking/presentation/speaking_result_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/speaking_session_notifier.dart';
import 'speaking_record_screen.dart';
import 'widgets/attempt_stack.dart';

class SpeakingResultScreen extends ConsumerWidget {
  const SpeakingResultScreen({super.key});

  Future<void> _endAndGoHome(BuildContext context, WidgetRef ref) async {
    await ref.read(speakingSessionNotifierProvider.notifier).endSession();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _tryAgain(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SpeakingRecordScreen(isRetry: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(speakingSessionNotifierProvider);

    if (session == null) {
      // Defensive: no active session means the user got here without starting
      // one. Pop back to home.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _endAndGoHome(context, ref);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            session.topic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AttemptStack(attempts: session.attempts),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _endAndGoHome(context, ref),
                        child: const Text('Done'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                        onPressed: () => _tryAgain(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: errors only in call sites that construct `SpeakingResultScreen` with old params. Those are the home screen (Task 14) and possibly history detail (Task 15).

If home/history detail still compile because they don't import `SpeakingResultScreen`, analyzer should be clean here.

- [ ] **Step 3: Commit the combined Task 12 + Task 13 change**

```bash
git add app/lib/features/speaking/presentation/speaking_record_screen.dart \
        app/lib/features/speaking/presentation/speaking_result_screen.dart
git commit -m "feat(speaking): rewrite record+result screens around session notifier"
```

---

## Task 14: Home screen — startSession on navigation

**Files:**
- Modify: `app/lib/features/speaking/presentation/speaking_home_screen.dart`

- [ ] **Step 1: Find every `Navigator.push(... SpeakingRecordScreen ...)` call site**

Search the file for all points where the record screen is pushed. Typical call sites: curated topic tap, custom topic submit, random-topic bottom-sheet "Start Practice".

- [ ] **Step 2: Add `startSession` before each push**

For each call site, wrap the push with:

```dart
ref
    .read(speakingSessionNotifierProvider.notifier)
    .startSession(topic: <topic>, isCustomTopic: <bool>);
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const SpeakingRecordScreen()),
);
```

Remove `topic:` / `isCustomTopic:` args from the `SpeakingRecordScreen()` constructor (they no longer exist).

- [ ] **Step 3: Add the import**

At the top of the file:

```dart
import '../providers/speaking_session_notifier.dart';
```

- [ ] **Step 4: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: history detail may still be wrong; everything else clean.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/speaking/presentation/speaking_home_screen.dart
git commit -m "feat(speaking): start a session before navigating to record screen"
```

---

## Task 15: History detail — full AttemptStack in read-only mode

**Files:**
- Modify: `app/lib/features/speaking/presentation/speaking_history_detail_screen.dart`

- [ ] **Step 1: Rewrite the screen to render the attempt stack**

Replace `app/lib/features/speaking/presentation/speaking_history_detail_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/speaking_providers.dart';
import 'widgets/attempt_stack.dart';

class SpeakingHistoryDetailScreen extends ConsumerWidget {
  final String sessionId;
  final String topic;

  const SpeakingHistoryDetailScreen({
    super.key,
    required this.sessionId,
    required this.topic,
  });

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final service = ref.read(speakingServiceProvider);
    await service?.deleteSession(sessionId);
    ref.invalidate(speakingHistoryProvider);
    ref.invalidate(speakingSessionByIdProvider(sessionId));
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(speakingSessionByIdProvider(sessionId));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          TextButton(
            onPressed: () => _delete(context, ref),
            child: Text('Delete', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (session) {
          if (session == null) {
            return const Center(child: Text('Session not found'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    topic,
                    style: textTheme.titleSmall?.copyWith(color: cs.primary),
                  ),
                ),
                const SizedBox(height: 8),
                AttemptStack(
                  attempts: session.attempts,
                  readOnly: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add app/lib/features/speaking/presentation/speaking_history_detail_screen.dart
git commit -m "feat(speaking): history detail uses AttemptStack in read-only mode"
```

---

## Task 16: End-to-end verification

**Files:** none modified.

- [ ] **Step 1: Full analyzer + test run**

```bash
cd app && flutter analyze --fatal-warnings && flutter test
```

Expected: zero warnings, all tests pass.

- [ ] **Step 2: Manual QA checklist (run the app)**

Start local Supabase (for edge functions + DB migration sanity):
```bash
supabase start
```

Run the app:
```bash
cd app && flutter run --dart-define-from-file=env.json
```

Walk the scenarios:

- [ ] Pick a curated topic → record → see attempt 1. Confirm:
  - Correction cards have no speaker button.
  - Natural version card shows a play-model button AND a "Shadow practice" row with a Record button.
  - Bottom buttons: "Done" (outline) and "Try again" (filled).
- [ ] Tap the model play button → model audio plays.
- [ ] Tap Record in Shadow practice → record a short phrase → Stop. A play button + refresh button appear.
- [ ] Tap play on shadow → your local recording plays back.
- [ ] Tap Try again → record screen shows the same topic → submit a different attempt.
- [ ] Back on result screen: Attempt 2 is expanded at top; Attempt 1 is a collapsed card below. Shadow audio from attempt 1 is still there and playable.
- [ ] Expand Attempt 1; the two attempts can be viewed together.
- [ ] Hit the system back button → session ends; shadow files removed from temp dir.
- [ ] Open history: the session appears as one row showing "2 attempts".
- [ ] Tap the row → history detail shows both attempts in the stack, each with only a "Play model" icon (no record, no refresh). Delete button removes the whole row.
- [ ] Sign in on another device and confirm the 2-attempt session syncs down.

- [ ] **Step 3: Final commit**

No file changes at this stage, just a tag commit if everything passes.

```bash
git commit --allow-empty -m "chore(speaking): shadow + try-again loop verified"
```

- [ ] **Step 4: Update docs**

Append a short entry to `docs/features.md` describing the shadow-practice and try-again loop, and to `docs/design-decisions.md` noting the `session_id`/`attempt_number` addition. Keep each under 10 lines.

```bash
git add docs/features.md docs/design-decisions.md
git commit -m "docs: document speaking shadow + retry loop"
```

---

## Post-Plan Notes

- **Single-expansion attempt stack.** I chose single-expansion (tapping an older attempt collapses the currently expanded one) for the live and history detail screens. The spec said multi-expansion was valuable for comparison; if that matters more than uncluttered scroll, tweak `AttemptStack._expandedId` to a `Set<String>`. Trivial follow-up.
- **Shadow playback via TtsCacheService.** I added `playLocalFile` to the TTS service rather than introducing a new player class. If that feels like a category error, split into a dedicated `LocalAudioPlayer` service later — the widget only depends on a `playLocalFile(String)` method shape.
- **`getResultById` is kept** (Task 2) for backward compat with the old history detail. It's unused after Task 15 — safe to remove in a follow-up cleanup commit.
