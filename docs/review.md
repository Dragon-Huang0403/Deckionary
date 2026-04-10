# Review (FSRS Spaced Repetition)

Deckionary includes an Anki-like spaced repetition system powered by [FSRS](https://pub.dev/packages/fsrs) v2.

## How It Works

- Users select a **word pool** (CEFR levels A1-C1 and/or Oxford 3000/5000)
- Each day, the app presents **due review cards** + **new cards** up to daily limits
- After seeing the front (headword + POS + IPA), tap to reveal the full entry
- Rate each card: Again / Hard / Good / Easy
- FSRS calculates the next review date based on the rating

## Card Model

- **One entry = one card** (headword + POS is the unit)
- "run (noun)" and "run (verb)" are separate cards
- **Front**: headword, POS, IPA with audio buttons (US/GB)
- **Back**: full dictionary entry (reuses `EntryCard` widget)

## Card Lifecycle

1. **Unseen** — no `ReviewCard` row exists; the word is in the dictionary DB only
2. **Learning** — FSRS state 1; short intervals (1m, 10m learning steps)
3. **Review** — FSRS state 2; intervals in days/weeks/months
4. **Relearning** — FSRS state 3; forgot a review card, back to short intervals

Cards are created **lazily** — only when they come up for study, not bulk-inserted.

## Daily Queue

1. **Due cards**: `SELECT * FROM review_cards WHERE due <= now()` (capped at max reviews/day)
2. **New cards**: filtered from dictionary DB, excluding entries with existing review cards (capped at new cards/day minus already learned today)
3. Learning/relearning cards due within 20 minutes are re-queued within the session

## Preset Filters

Filters combine with **OR** (union). Selecting "B1 + Oxford 3000" = all words from either set.

Available filters:
- CEFR levels: A1, A2, B1, B2, C1
- Oxford 3000 (~3,771 entries)
- Oxford 5000 (~5,900 entries)

## Settings

| Setting | Default | Location |
|---------|---------|----------|
| New cards per day | 20 | Settings > Review |
| Max reviews per day | 200 | Settings > Review |
| New card order | Random | Settings > Review |
| Auto-pronounce in review | On | Settings > Review |
| Clear review progress | — | Settings > Review |

Tip: max reviews should be ~7-10x new cards to avoid backlog.

## Architecture

### Database

Two separate databases (can't JOIN across them):

- **DictionaryDatabase** (read-only) — word data with CEFR/Oxford flags
- **UserDatabase** (read-write) — `review_cards`, `review_logs`, `settings`

Cross-database queries done in Dart: fetch candidate IDs from dict DB, subtract existing card IDs from user DB.

### Key Files

```
core/database/
  review_dao.dart          — CRUD for review cards/logs, cross-DB queries
  settings_dao.dart        — review settings (new/day, max/day, filter, order)

features/review/
  domain/
    review_filter.dart     — filter model (CEFR + Oxford), JSON serialization
    review_service.dart    — FSRS bridge (DB <-> FSRS Card conversion)
    review_session.dart    — in-memory queue manager
  providers/
    review_providers.dart  — Riverpod providers (filter, summary, session)
  presentation/
    review_home_screen.dart    — daily summary, filter chips, start button
    review_session_screen.dart — flashcard UI with flip + rating
    widgets/
      filter_selector.dart     — dialog for CEFR/Oxford selection
      rating_bar.dart          — Again/Hard/Good/Easy buttons
```

### FSRS v2 Package API

```dart
Scheduler(desiredRetention: 0.9, learningSteps: [1m, 10m], relearningSteps: [10m])
scheduler.reviewCard(card, rating) → ({Card card, ReviewLog reviewLog})
```

Card states: `learning(1)`, `review(2)`, `relearning(3)` — no `new(0)` state.

## Local-Only

All data stored in local SQLite via Drift. No network calls required. Supabase sync is a future follow-up.
