# Release & Versioning

## Version Display

The app shows version, build date, and commit hash at the bottom of the Settings screen:
- Release builds: `v0.1.0 · 2026-04-12 · a3b4c5d`
- Local dev builds: `v0.1.0 · 2026-04-12 14:32 · dev`

Source of truth: `app/lib/core/build_info.dart` (generated — do not edit manually). The commit hash and build date are injected at build time via `--dart-define` in CI. Local dev builds fall back to `DateTime.now()` (date + HH:MM).

## How to Release

```bash
./scripts/bump_version.sh 0.2.0
git push
```

That's it. The script and CI handle the rest:

1. **`bump_version.sh`** updates `app/pubspec.yaml` version, auto-increments build number, regenerates `build_info.dart`, and commits `"release: v0.2.0"`
2. **Push to main** triggers `auto-tag.yml` — detects the pubspec version change, creates git tag `v0.2.0`
3. **Tag creation** triggers `release.yml` — builds Android APK + macOS app, creates a GitHub Release with both artifacts

## Files

| File | Role |
|---|---|
| `app/pubspec.yaml` | Canonical version (`0.2.0+2`) |
| `app/lib/core/build_info.dart` | Generated consts: `appVersion`, `appBuildNumber`, `buildDate`, `buildCommit` |
| `scripts/bump_version.sh` | Bumps version, regenerates build_info, commits |
| `.github/workflows/auto-tag.yml` | Creates git tag when pubspec version changes on main |
| `.github/workflows/release.yml` | Builds artifacts and creates GitHub Release on tag |

## Version Format

`pubspec.yaml` uses `<semver>+<build>`:
- **Semver** (e.g. `0.2.0`) — the user-facing version, used for git tags and display
- **Build number** (e.g. `+2`) — auto-incremented by `bump_version.sh`, used by Android `versionCode` and iOS `CFBundleVersion`

## Build Date

`buildDate` uses `String.fromEnvironment('BUILD_DATE')`. CI injects a UTC date (`YYYY-MM-DD`). Local dev builds default to `DateTime.now()` formatted as `YYYY-MM-DD HH:MM`, so the Settings screen always shows a meaningful timestamp.

## Commit Hash

`buildCommit` uses `String.fromEnvironment('BUILD_COMMIT')` — a compile-time const injected via `--dart-define` in `release.yml`. Defaults to `'dev'` for local builds. CI passes the full SHA (`${{ github.sha }}`); the UI truncates to 7 chars for display.

## CI Notes

- `auto-tag.yml` explicitly calls `gh workflow run release.yml` instead of relying on the tag push event. This is because GitHub's `GITHUB_TOKEN` cannot trigger other workflows via push events (by design, to prevent infinite loops).
- `release.yml` also accepts `workflow_dispatch` for manual triggers from the GitHub Actions UI.
