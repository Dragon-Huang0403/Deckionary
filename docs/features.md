# Deckionary Features

A dictionary app powered by OALD10 with FSRS spaced repetition, macOS quick-search overlay, and cross-device sync. Targets macOS, iOS, Android.

---

## Dictionary

Multi-tier word lookup with full Oxford entry display.

**Search pipeline** (fallback order):
1. Exact headword match (case-insensitive)
2. Variant spelling redirect (e.g., "colour" -> "color")
3. Suffix stripping (e.g., "running" -> "run")
4. Prefix autocomplete (LIKE query, up to 15 results)
5. Levenshtein fuzzy match (edit distance <= 2, for typos)
6. FTS5 full-text search across definitions and examples (BM25-ranked)

**Entry display**: headword, POS, IPA (GB/US), CEFR level, Oxford 3000/5000 badge, sense groups with topic labels (EN + Chinese), definitions, examples with highlighting, synonyms, collocations, word family, word origin, phrasal verbs, idioms, cross-reference navigation.

**Search history**: recent lookups tracked with deduplication by headword + POS, soft-deletable, synced across devices.

---

## Spaced Repetition (FSRS)

Vocabulary review using the FSRS algorithm with daily session management.

**Card lifecycle**: unseen -> learning (1m, 10m steps) -> review (days/weeks/months) -> relearning on failure. Cards created lazily on first encounter, not bulk-imported.

**Daily queue**: loads due cards (capped at `maxReviewsPerDay`, default 200) + new cards (`newCardsPerDay` minus already-learned-today). Supports random or alphabetical order.

**Filters**: combine CEFR levels (A1-C1) and Oxford 3000/5000 flags with OR (union). Persisted in settings.

**Session UI**: card front/back flip, 4-button rating (Again/Hard/Good/Easy) with interval preview, in-session dictionary lookup via bottom sheet, auto-pronunciation based on settings.

**Study words**: browse and add new words filtered by CEFR/Oxford lists, view word status.

> Deep-dive: [review.md](review.md) covers the card model, FSRS v2 API, queue implementation, and key source files.

---

## Audio Pronunciation

On-demand playback with optional bulk offline download.

**On-demand**: checks local audio.db cache first, fetches from Cloudflare R2 on miss, caches BLOB for future hits. Plays via temp file + just_audio.

**Bulk download**: 65 tar packs (~4,000 files each, ~217K total audio files). 6 concurrent downloads with exponential backoff retry (up to 10 rounds). Completed packs tracked for resume on restart. Tar parsed in pure Dart.

**Dialects**: GB and US pronunciations for words, verb forms, and example sentences.

**Settings**: choose default dialect, toggle pronunciation display, toggle auto-pronounce during review.

> Infrastructure: [r2-export.md](r2-export.md) for R2 bucket structure and upload scripts.

---

## macOS Quick Search Overlay

Raycast-style global hotkey search window (default: Cmd+Shift+D).

**Trigger**: system-wide hotkey via `hotkey_manager`, works from any app. Customizable in settings.

**Overlay window**: frameless, 800px wide, 70% screen height, centered on the monitor where the cursor is. Auto-hides on focus loss.

**Clipboard integration**: reads clipboard on trigger, auto-fills search bar if text looks like a word (1-50 chars, letters/numbers/apostrophes). Snapshots clipboard on hide to avoid re-pasting same text.

**Keyboard-driven**: arrow keys navigate results, Return selects, Escape hides.

**Window modes**: overlay mode (no dock, no nav bar, search-only) vs. normal mode (full app with tabs). Native method channel (`com.deckionary/window`) controls window level.

---

## Tray Icon (macOS)

Optional menu bar icon. Click toggles window, right-click shows context menu (Show/Hide, Quit). Dock visibility also toggleable in settings.

---

## Cross-Device Sync

Offline-first sync via Supabase with Firebase Google Sign-In.

**Synced data**: review cards, review logs, search history, settings.

**Push**: fire-and-forget after each mutation. Unsynced rows (synced=0) retried on next sync cycle.

**Pull**: incremental cursor-based using `updated_at` watermarks per table. New devices pull everything.

**Conflict resolution**: last-write-wins by `updated_at` for cards and settings. Append-only + UUID dedup for logs and history.

**Soft deletes**: `deleted_at` column instead of hard delete. Tombstones sync across devices. Garbage collected after 30 days.

**Auto-sync**: debounced pull on window focus / app resume. Manual sync button in settings.

> Rationale: [design-decisions.md](design-decisions.md#offline-first-sync) covers why offline-first, last-write-wins, cursor-based pull, and soft deletes were chosen.

---

## Authentication

Google Sign-In via Firebase -> Supabase token exchange.

1. Google OAuth -> ID token
2. Supabase `signInWithIdToken` validates and creates session
3. Supabase RLS enforces user-scoped data access

Sync is optional — app fully functional without sign-in.

---

## App Updates

Version check against GitHub Releases API on startup. Shows alert dialog with release notes if newer version available. Skip-version button persists preference in settings.

---

## Settings

| Section | Options |
|---------|---------|
| Account | Google Sign-In/Out, manual sync |
| Audio | Dialect (US/GB), pronunciation display, auto-pronounce |
| Review | New cards/day, max reviews/day, card order, auto-play mode |
| Appearance | Theme (light/dark/system) |
| macOS | Hotkey binding, tray icon, dock visibility, launch on startup |

Settings auto-push to Supabase on change. No explicit save button.

---

## Platform Support

| Feature | macOS | iOS | Android |
|---------|-------|-----|---------|
| Dictionary search | Yes | Yes | Yes |
| FSRS review | Yes | Yes | Yes |
| Audio playback | Yes | Yes | Yes |
| Bulk audio download | Yes | Yes | Yes |
| Cross-device sync | Yes | Yes | Yes |
| Global hotkey overlay | Yes | - | - |
| Tray icon | Yes | - | - |
| Dock hide/show | Yes | - | - |
| Clipboard auto-search | Yes | - | - |
| Cmd+, for settings | Yes | - | - |
