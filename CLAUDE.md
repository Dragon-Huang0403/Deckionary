# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Deckionary** — a Flutter dictionary app powered by OALD10 (Oxford Advanced Learner's Dictionary) with FSRS spaced repetition, macOS global hotkey quick search, and cross-device sync via Firebase + Supabase. Targets macOS, iOS, Android.

## Commands

The root `Makefile` wraps the common tasks (`make` lists them): `make setup`, `make run`,
`make build-macos`, `make install`, `make test-offline`, `make lint`, `make gen`. Each one
prefixes Flutter with `fvm` when available. macOS builds go through
`scripts/build_macos.sh`, which builds unsigned and ad-hoc signs, so no Apple Developer
certificate is needed.

The underlying commands run from `app/`, prefixed with `fvm` so they use the pinned SDK:

```bash
cd app
fvm flutter pub get
fvm flutter pub get --enforce-lockfile           # exactly what CI runs
fvm flutter run --dart-define-from-file=env.json # Run app (sync-enabled)
fvm flutter run                                  # Run app (local-only, no sync)
fvm flutter analyze --fatal-warnings             # Lint (CI enforces this)
fvm dart format .                                # Format all Dart files
fvm dart run build_runner build --delete-conflicting-outputs  # Regenerate Drift code
fvm flutter build apk --release --dart-define-from-file=env.json
fvm flutter build macos --release --dart-define-from-file=env.json
```

### Flutter version pinning

`app/.fvmrc` is the single source of truth for the Flutter version. `fvm install` reads it
locally; every workflow reads the same file via `subosito/flutter-action`'s
`flutter-version-file: app/.fvmrc`. Never add `channel: stable` back to a workflow — an
unpinned channel is what silently broke CI whenever Flutter shipped a new minor.

All workflows run `flutter pub get --enforce-lockfile`, so `pubspec.lock` must match the
pinned SDK. To upgrade Flutter: edit `.fvmrc`, `fvm install`, `fvm flutter pub get`,
`fvm flutter analyze --fatal-warnings`, then commit `.fvmrc` and `pubspec.lock` together.

Python tools (from repo root):
```bash
python build_db.py                  # Build oald10.db from macOS dictionary bundle
```

Supabase Edge Functions (from repo root):
```bash
supabase start                                    # Start local Supabase (applies migrations)
cp supabase/.env.example supabase/.env.local      # Create env file (first time only)
# Edit supabase/.env.local to add your OPENAI_API_KEY
supabase functions serve --env-file supabase/.env.local  # Serve edge functions locally
```

Pre-commit hook auto-formats and lints. Install with: `git config core.hooksPath .githooks`

### Testing

Integration tests run against a local Supabase instance (requires Docker + [Supabase CLI](https://supabase.com/docs/guides/cli)):

```bash
supabase start                          # Start local Supabase (applies migrations)
cd app && flutter test                  # Run all tests
supabase stop                           # Stop when done
```

- Tests use the default local Supabase demo keys (no secrets needed)
- Override with env vars: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- After schema changes, run `supabase db reset` to reapply all migrations

## Architecture

### Two-part project
- **`app/`** — Flutter application (Dart)
- **`db/`, root .py files** — Python tooling for DB building, web API

### Flutter app structure (`app/lib/`)

**State management**: Riverpod (FutureProvider, NotifierProvider, AsyncNotifierProvider)

**Two separate SQLite databases** (cannot JOIN across them):
- **DictionaryDatabase** (`dictionary_tables.dart`) — read-only, bundled from `assets/oald10.db`, opened via raw SQL. 76K entries with FTS5 search index.
- **UserDatabase** (`app_database.dart`) — read-write, Drift ORM with migrations (schema v5). Stores review cards, logs, search history, audio cache, settings, sync state.

**Feature modules** (`features/`):
- `dictionary/` — multi-tier search (exact > variant > suffix strip > prefix > fuzzy), entry display
- `review/` — FSRS spaced repetition scheduler, session queue, filter by CEFR/Oxford level
- `settings/` — app config UI
- `account/` — Google Sign-In, user info

**Core services** (`core/`):
- `database/` — Drift schema, DAOs (ReviewDao, SearchHistoryDao, SettingsDao), database providers
- `audio/` — pronunciation playback from R2 CDN with SQLite caching, background download via `background_downloader`
- `sync/` — offline-first Supabase sync (debounced pull on resume, fire-and-forget push)
- `auth/` — Google Sign-In via Firebase, token exchange with Supabase
- `update/` — GitHub Releases version check

**macOS-specific** (`app.dart`): global hotkey (Cmd+Shift+D), window management (always-on-top, display-aware positioning), optional tray icon, clipboard auto-search. Uses MethodChannel `com.deckionary/window` for native window level control.

### Key patterns
- **Offline-first sync**: local `synced` column (0/1) tracks push state; last-write-wins by `updated_at`
- **Lazy card creation**: FSRS review cards created on first encounter, not bulk-imported
- **Cross-DB queries**: dictionary lookups + user data joined in Dart, not SQL
- **Drift code generation**: `app_database.g.dart` is generated; run build_runner after schema changes
- **File size limit**: Keep Dart files under 500 lines. Split via widget extraction, Dart extensions, or domain-specific modules.

### Environment & secrets
- `app/env.json` (gitignored) — `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `R2_BASE_URL`
- `app/lib/firebase_options.dart` (gitignored) — generated by `flutterfire configure`
- `app/assets/oald10.db` (gitignored, ~93MB) — must be placed before building

### Documentation
See [`docs/README.md`](docs/README.md) for full index. Key docs:
- `docs/features.md` — feature catalog (what the app does)
- `docs/design-decisions.md` — architectural decisions and rationale
- `docs/review.md` — FSRS deep-dive (card model, scheduling, queue logic)
- `docs/database.md` — dictionary schema and build pipeline
- `docs/r2-export.md` — Cloudflare R2 export and upload
- `docs/release.md` — versioning and CI release workflow

When adding features or making architectural changes, update `docs/features.md` and `docs/design-decisions.md` accordingly.
