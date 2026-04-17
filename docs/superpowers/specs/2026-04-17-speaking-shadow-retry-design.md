# Speaking Coach — Shadow & Try-Again Design

## Context

Speaking Coach v1 (shipped) and v1.1 (shipped in d95c3b6 — history list/detail, random topic, home redesign) deliver a one-shot critique loop: record → submit → see corrections + natural version → done. Feedback is single-pass; once the user sees the result there is no in-product way to *practice with it*.

This design turns the result screen into a **practice loop**:
1. **Shadow** the natural version (listen + repeat aloud, record self, compare locally).
2. **Try again** on the same topic and see attempt-by-attempt history in the session.

Shadowing is a well-validated B1→B2 technique for fluency, prosody, and chunking; re-production is where generative output gets trained. Doing both in sequence — shadow to internalize the model, then re-produce from scratch — is the high-value loop.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Per-correction TTS buttons | Removed from `CorrectionCard` (affects live + history detail) | Small text fragments don't benefit from TTS; focus audio on the full natural version |
| Shadow feedback model | Local record + replay, no LLM | Shadowing's value is repetition volume; LLM scoring adds cost and slows the loop |
| "Try again" semantics | Full re-production: navigate back to record screen with topic preserved | Reuses existing record UI, consistent with attempt-1 flow |
| Attempt history UI | Stacked collapsible cards, newest expanded on top | Mobile-native; surfaces progress without dedicated UI real-estate; lets users expand two for comparison |
| DB persistence of attempts | **All** attempts persisted; grouped by `session_id` | User wants iterative practice visible across devices; shadow practice without persisted retry history loses the progress signal |
| Schema change | Add `session_id` and `attempt_number` columns to `speaking_results` (Drift v9 → v10, plus matching Supabase migration) | Minimal structural change; existing rows backfilled as single-attempt sessions |
| Write timing | Write each attempt to DB immediately after LLM returns | Crash-safe; no "on session end" batch write complexity |
| Record↔Result nav | State preserved across both directions | User can back-out of retry without losing the stack |
| Shadow audio lifecycle | Temp files, deleted when session ends | Never synced; local practice artifact only |
| History list grouping | Group rows by `session_id`; show one card per session with attempt count | Keeps history list uncluttered while preserving iteration signal |
| History detail screen | Refactored to show attempt stack (same layout as live result, read-only) | Lets users review iteration on past sessions |
| Delete in history | Deletes the whole session (all rows with the `session_id`) | Matches user's mental model — one history entry = one session |

## Live Result Screen

### Natural version card — Shadow block

Replaces the current single "listen" icon button. Layout:

```
Natural version                    ▶ Play model
<natural version text>

Shadow practice
  ● Record     (before recording)
  ▶ Play      ⟲ Re-record    (after recording)
```

- **Play model**: existing TTS via `ttsCacheServiceProvider.play(naturalVersion)`, unchanged behavior.
- **Record**: captures local audio using the same recording infrastructure as the record screen (`AudioRecorder` or equivalent). Produces a temp file path.
- **Play shadow**: plays back the local recording.
- **Re-record / clear**: discards the current shadow file and returns the block to pre-recording state.

Shadow audio is local-only: never uploaded, never synced, never sent to the LLM. Each attempt in the stack has its own shadow recording slot because each attempt has its own natural version.

### Correction cards

Remove the per-correction TTS "listen" button in `CorrectionCard`. Text-only: original → natural → explanation. Change applies to both live result screen and history detail screen (shared widget).

### Action buttons (bottom of result screen)

- **Try again** (filled, primary CTA) — navigate back to record screen with current topic preserved. On submit, new attempt pushed to the top of the stack.
- **Done** (outline) — back to home, session ends.

The current result screen's "Practice another topic" and "Done" buttons were redundant (both just navigate home). They collapse into a single **Done**; "Try again" takes the primary slot to nudge iteration over exit.

## Attempt History UI

Within a single session, the result screen shows a stack of attempts on the same topic:

- **Newest attempt**: expanded at top. Full content: transcript, overall note (if any), natural version with shadow block, corrections.
- **Older attempts**: collapsed cards below. One-line summary: `Attempt N · X corrections · HH:MM`. Tap to expand.
- Users can expand multiple simultaneously for side-by-side comparison.

Attempts are numbered in the order recorded (Attempt 1 is the oldest / first, top of stack is the highest-numbered most recent).

## Try-Again Flow

1. User on result screen taps **Try again**.
2. Navigation pushes (or returns to) the existing record screen with the current `topic` and `isCustomTopic` pre-populated.
3. User records and submits as normal.
4. `SpeakingService.analyze(...)` returns a new `SpeakingResult`.
5. New attempt pushed to the top of the in-memory stack.
6. Navigation returns to the result screen, now showing N+1 attempts.

Edge cases:
- **Back from record screen without recording**: stack is unchanged; user returns to result screen with existing attempts intact.
- **Cancel mid-recording**: same as above.
- **Submit fails**: standard error handling from existing flow; no attempt added to the stack.

## State Management

A new Riverpod notifier — `SpeakingSessionNotifier` — holds the active session, backing the result screen's stack view:

```dart
class SpeakingAttempt {
  final String id;              // = speaking_results.id
  final int attemptNumber;      // 1-indexed within the session
  final SpeakingResult result;
  final String? shadowAudioPath;  // local temp file, null until recorded
  final DateTime createdAt;
}

class SpeakingSessionState {
  final String sessionId;        // UUID, generated on start
  final String topic;
  final bool isCustomTopic;
  final List<SpeakingAttempt> attempts;  // index 0 = oldest (attempt 1)
}
```

Operations on the notifier:
- `startSession(topic, isCustomTopic)` — generates a new `sessionId`, called when the user navigates from topic pick (or history detail's "Practice again") to the record screen.
- `addAttempt(SpeakingResult)` — writes a new row to `speaking_results` (with `session_id`, `attempt_number = attempts.length + 1`) and appends the attempt in memory.
- `setShadowAudio(attemptId, path)` — stores the local shadow file path on an attempt (in memory only).
- `clearShadowAudio(attemptId)` — deletes the file and clears the path.
- `endSession()` — deletes all shadow files for the session and clears in-memory state. No DB writes (attempts are already persisted).

The existing record screen reads `topic` and `isCustomTopic` from this notifier instead of route arguments when a session is active. First-time entry passes through topic pick → `startSession` → record screen.

## Persistence

Schema migration (Drift v9 → v10) adds two columns to `speaking_results`:

| Column | Type | Notes |
|---|---|---|
| `session_id` | TEXT, nullable | UUID shared by all attempts in one session |
| `attempt_number` | INTEGER, nullable | 1-indexed, starting at 1 |

Backfill: existing rows get `session_id = id`, `attempt_number = 1` (each historical row becomes a single-attempt session).

A matching Supabase migration adds the same two columns on the remote `speaking_results` table with the same backfill.

Write flow:
- Each attempt is written immediately after the LLM response is received, inside `addAttempt`.
- Row includes `session_id`, `attempt_number`, and existing fields.
- The sync layer (`speaking_sync.dart`) gets a minimal update: the push upsert payload and the pull insert/update SQL both need the two new column names added. No structural change — rows still flow through the existing `synced` flag.

Failure modes:
- **App crash / force-close mid-session**: all attempts written so far are preserved (they're in the DB). In-memory state is lost; on next launch, the user sees those attempts as a session in history. Re-entering the same topic starts a *new* session (different `session_id`).
- **Write fails**: surface error toast, do not add to the in-memory stack. User can retry.

Delete behavior:
- History detail's "Delete" action deletes all rows with the session's `session_id` (one session = one history entry).

## Shadow Audio Lifecycle

- Files stored in `path_provider.getTemporaryDirectory()` under a `speaking_shadow/` subdirectory.
- Filename includes a UUID so concurrent attempts never collide.
- Path is held on the attempt object in memory; never written to any DB.
- Deleted on:
  - Re-record (the old file is replaced).
  - Session end (all shadow files for the session).
- OS-level temp cleanup serves as a final safety net.

## Coexistence With v1.1

The v1.1 agent's shipped code (d95c3b6) assumed one row per topic-session. Persisting all attempts requires updates to v1.1's history UI:

- **Home redesign, random topic**: untouched.
- **`speakingHistoryProvider`**: must group rows by `session_id` instead of returning raw rows. Each aggregated history item exposes: topic, session_id, attempt count, latest correction count, latest timestamp, `isCustom` flag.
- **`speaking_history_screen.dart`**: unchanged structurally, but the card now shows "3 attempts" when `attemptCount > 1`. Swipe-to-delete deletes the whole session.
- **`speaking_history_detail_screen.dart`**: refactor to show the attempt stack (read-only — no shadow record controls, no Try-again button). Reuses the same attempt-stack widget as the live result screen. Delete button deletes all rows in the session.
- **Existing history rows** (single-attempt, backfilled with `session_id = id`, `attempt_number = 1`) render as a one-attempt session — no visible change for existing users.

## Files

### New

| File | Purpose |
|---|---|
| `speaking_session_notifier.dart` (in `features/speaking/providers/`) | Holds active session state: session_id, topic, attempts list, shadow paths |
| `widgets/shadow_block.dart` (in `features/speaking/presentation/`) | Natural version card's play-model + record-self + play-self controls |
| `widgets/attempt_card.dart` (in `features/speaking/presentation/`) | Single attempt card (expanded or collapsed variant); takes a `readOnly` flag to suppress shadow controls in history detail |
| `widgets/attempt_stack.dart` (in `features/speaking/presentation/`) | Ordered list of `AttemptCard` widgets with collapse/expand state; shared by live result + history detail |
| Drift migration v5 → v6 (in `core/database/`) | Add `session_id`, `attempt_number` columns; backfill existing rows |

### Modified

| File | Change |
|---|---|
| `widgets/correction_card.dart` | Remove per-correction TTS button and related state |
| `speaking_result_screen.dart` | Replace single-result layout with `AttemptStack`; add Try-again button; wire session notifier |
| `speaking_record_screen.dart` | Read topic from session notifier; on success, call `addAttempt` and pop back to result |
| `speaking_home_screen.dart` | Call `startSession` when navigating to record screen from topic pick or random bottom sheet |
| `speaking_history_screen.dart` | Update card to show attempt count when > 1; delete acts on session_id |
| `speaking_history_detail_screen.dart` | Replace single-result layout with `AttemptStack` in read-only mode; delete acts on session_id |
| `speaking_service.dart` | Add `getSessionById(sessionId)` returning ordered attempts; update delete to operate on session_id |
| `speaking_providers.dart` | Add `speakingSessionNotifierProvider`; update `speakingHistoryProvider` to group by session_id; add `speakingSessionByIdProvider` |
| `app_database.dart` / `user_tables.dart` | Add `session_id`, `attempt_number` columns to `SpeakingResults`; bump schema version to 10; wire migration |
| `core/sync/speaking_sync.dart` | Include `session_id` and `attempt_number` in push upsert payload and pull INSERT/UPDATE SQL |
| `supabase/migrations/*.sql` (new file) | Add `session_id`, `attempt_number` columns to remote `speaking_results` with backfill |

Sync structure unchanged — rows still flow through the existing `synced` flag; only the column lists get extended.

## Out of Scope

- Audio speed / segment loop controls on model playback.
- Pronunciation scoring or any LLM-side evaluation of the shadow recording.
- Cross-attempt diff highlighting ("you fixed X from last time"). Corrections per attempt already surface this implicitly; explicit diffs are a v2 enhancement if demand emerges.
- Persisting shadow audio across devices (still local-only, temp files).
- "Continue session" from history detail (starting a new session on the same topic is available by picking the topic again; reviving a closed session is deferred).
