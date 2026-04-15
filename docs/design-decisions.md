# Design Decisions

Key architectural decisions in Deckionary and the reasoning behind them.

---

## Two Separate SQLite Databases

**Decision**: use a read-only DictionaryDatabase (bundled asset) and a read-write UserDatabase (Drift-managed) instead of a single database.

**Why**:
- Dictionary data (~80MB, 76K entries) is immutable at runtime. Bundling it as a pre-built asset avoids expensive initialization and enables atomic updates by replacing the file.
- User data (review cards, settings, search history) needs migrations, sync, and write access — different lifecycle from dictionary data.
- SQLite cannot JOIN across attached databases with Drift. Cross-database queries are done in Dart (fetch candidate IDs from dict DB, subtract existing IDs from user DB in memory).

**Trade-off**: cross-DB queries require Dart-side joining instead of SQL. Acceptable because the join patterns are simple (ID set subtraction for new card discovery).

> See [database.md](database.md) for the full dictionary schema and build pipeline.

---

## Offline-First Sync

**Decision**: all data lives locally in SQLite first. Sync to Supabase is optional and non-blocking.

**Why**:
- App must work without internet (airplane mode, spotty connections).
- Network latency should never block UI — reviews, searches, and settings changes are instant.
- Graceful degradation: if `supabaseAnonKey` is empty, `syncEnabled=false` and the app runs purely local.

**Implementation**:
- `synced` column (0/1) on mutable rows tracks push state.
- Fire-and-forget push after each mutation; retry unsynced rows on next cycle.
- Incremental pull using `updated_at` watermarks per table — no full resync needed.
- `sync_code_version` in sync_meta detects protocol changes and forces full resync when bumped.

---

## Cursor-Based Incremental Pull

**Decision**: use `updated_at` timestamp watermarks instead of server-side change tracking or event sourcing.

**Why**:
- Simple: each table stores one watermark in `sync_meta`. Next pull queries `WHERE updated_at >= cursor`.
- No server-side infrastructure needed beyond Supabase's default `updated_at` column.
- Resume-safe: interrupted pulls just retry from the same watermark.

**Trade-off**: relies on clock ordering. Acceptable because Supabase server timestamps are authoritative and conflict resolution uses last-write-wins.

---

## Last-Write-Wins Conflict Resolution

**Decision**: resolve conflicts by comparing `updated_at` timestamps. No merge logic.

**Why**:
- Review cards have a single owner editing sequentially — concurrent edits to the same card are rare.
- Merge logic for FSRS state (stability, difficulty, intervals) is undefined — there's no meaningful way to merge two divergent review histories.
- Simplicity: last-write-wins is predictable and easy to debug.

**Exception**: review logs are append-only with UUID dedup — no conflicts possible.

---

## Soft Deletes

**Decision**: set `deleted_at` instead of hard-deleting rows. Garbage collect after 30 days.

**Why**:
- Tombstones must propagate to other devices. If device A deletes a search history entry, device B needs to learn about the deletion on next pull.
- Hard-delete + sync creates a "phantom row" problem: device B would re-push the deleted row because it doesn't know it was intentionally removed.
- 30-day retention balances sync correctness with storage cost.

---

## Lazy Card Creation

**Decision**: FSRS review cards are created on first encounter during a review session, not bulk-imported from the dictionary.

**Why**:
- 76K dictionary entries x card metadata = large upfront write + sync overhead for cards the user may never study.
- Creating on-demand means only studied words consume storage and sync bandwidth.
- New card discovery uses a cross-DB query: fetch entry IDs matching the filter from dict DB, subtract existing card IDs from user DB.

> See [review.md](review.md) for the full card model, lifecycle, and FSRS scheduling details.

---

## Multi-Tier Search Pipeline

**Decision**: five search tiers in fallback order (exact -> variant -> suffix strip -> prefix -> fuzzy) plus FTS5 on definitions.

**Why**:
- Fast path for the common case: most searches are exact headword matches (tier 1), resolved in microseconds.
- Each subsequent tier handles a specific failure mode: misspellings (variants), inflections (suffix strip), partial input (prefix), typos (Levenshtein), concept search (FTS5).
- Tiers are ordered by cost — expensive Levenshtein and FTS only run if cheaper tiers fail.

**Trade-off**: Levenshtein computes edit distance against all 62K headwords. Acceptable because it only runs when the first 3 tiers return nothing, and the computation is fast on modern devices.

---

## Tar Pack Audio Downloads

**Decision**: bundle audio files into 65 tar archives (~4,000 files each) on Cloudflare R2 instead of serving 217K individual files.

**Why**:
- HTTP request overhead dominates per-file download. 217K requests would take hours even on fast connections.
- Tar packs reduce connections to 65. Each pack is ~35MB — reasonable for mobile networks.
- Resume on failure: completed packs tracked in audio.db. App restarts from next incomplete pack.
- Tar parsing in pure Dart avoids native dependencies.

**Trade-off**: can't download individual files on-demand from packs. Mitigated by the separate on-demand single-file fetch path for immediate playback.

> See [r2-export.md](r2-export.md) for the R2 bucket structure and export workflow.

---

## Firebase + Supabase Auth

**Decision**: Google Sign-In via Firebase, then token exchange to Supabase for database auth.

**Why**:
- Firebase handles OAuth complexity (platform-specific Google Sign-In flows, token refresh).
- Supabase provides the sync database with Row-Level Security (RLS) keyed on `user_id`.
- Token exchange (`signInWithIdToken`) bridges the two — one sign-in, both services authenticated.

**Trade-off**: two auth systems add configuration complexity (firebase_options.dart + env.json). Acceptable because Firebase and Supabase serve different roles (auth flow vs. data backend).

---

## Riverpod for State Management

**Decision**: use Riverpod (Provider, FutureProvider, AsyncNotifier, StreamProvider) instead of BLoC, GetX, or setState.

**Why**:
- Declarative: providers automatically cache and invalidate. `ref.watch` rebuilds widgets when dependencies change.
- Type-safe: no stringly-typed lookups or runtime errors.
- Testable: providers can be overridden in tests without widget tree gymnastics.
- Fits the data flow: databases as Provider singletons, computed values as FutureProvider, mutable state as AsyncNotifier, auth as StreamProvider.

---

## macOS Overlay via Native Method Channel

**Decision**: use a native Swift method channel (`com.deckionary/window`) for window level control instead of pure Flutter.

**Why**:
- Flutter's `window_manager` cannot set macOS window levels (overlay above all apps, hide from Mission Control, etc.).
- Native code required for: `NSWindow.level = .floating`, dock visibility toggle, Space-independent window behavior.
- Method channel keeps the native surface small (4 methods: setNormalMode, setOverlayMode, prepareForShow, resetLevel).

---

## Settings Auto-Push

**Decision**: settings changes automatically push to Supabase via a callback hook on SettingsDao. No explicit save/sync button for settings.

**Why**:
- Settings are key-value pairs with trivial conflict resolution (last-write-wins).
- Users expect preferences to "just sync" without manual intervention.
- The callback hook in SettingsDao fires `sync.pushSetting(key, value)` on every write — minimal code, no UI needed.

---

## Tab Navigation (No Router)

**Decision**: use IndexedStack with a BottomNavigationBar instead of GoRouter or Navigator 2.0.

**Why**:
- Two tabs (Dictionary, Review) + modal screens (Settings, Account). Routing complexity is minimal.
- IndexedStack preserves tab state across switches (search results, scroll position).
- GoRouter is a dependency but unused — the app doesn't need deep linking or URL-based navigation.

---

## File Size Limit: 500 Lines

**Decision**: keep Dart files under 500 lines. Split via widget extraction, Dart extensions, or domain-specific modules.

**Why**:
- Long files are hard to navigate and review.
- Widget extraction naturally follows Flutter's composition model.
- Extensions keep related logic close to the type without bloating the main file (e.g., dictionary search methods as extensions on DictionaryDatabase).
