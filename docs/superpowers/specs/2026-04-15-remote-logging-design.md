# Remote Logging & Device Identification

## Overview

Full observability system for Deckionary: crash reporting, diagnostic logs, device identification, and in-app log viewer. Uses Talker as the unified logging API, Sentry for crash/error monitoring, and Supabase for queryable diagnostic logs.

## Stack

- **talker_flutter** -- unified logging API + in-app viewer
- **talker_riverpod_logger** -- auto-log Riverpod state changes
- **sentry_flutter** -- crash reporting, error monitoring, breadcrumb trails
- **Supabase `app_logs` table** -- queryable diagnostic logs with 7-day retention
- **Existing `uuid` package** -- device ID generation

## Device ID

UUID v4 generated on first launch, stored in existing `settings` table via `SettingsDao`.

```dart
SettingsDao.getDeviceId() -> String?
SettingsDao.setDeviceId(String id)
```

On startup: check if `device_id` exists. If not, generate with `Uuid().v4()` and persist. Attached to every Sentry event and Supabase log row.

No new dependencies.

## Log Levels & Routing

| Level   | Console | Sentry            | Supabase |
|---------|---------|-------------------|----------|
| error   | yes     | captureException  | yes      |
| warning | yes     | breadcrumb        | yes      |
| info    | yes     | breadcrumb        | yes      |
| debug   | yes     | breadcrumb        | no       |

Tagged logging per module:
```dart
talker.error('[SYNC] Push failed for review_cards', error, stackTrace);
talker.info('[AUDIO] Cache hit for word: $word');
talker.warning('[AUTH] Token refresh retry #$attempt');
```

## Sentry Integration

`SentryFlutter.init()` in `main.dart` with `runZonedGuarded` wrapping.

**Automatic captures:** unhandled Dart exceptions, Flutter framework errors, ANRs (Android), slow/frozen frames.

**Custom context on every event:**
- `device_id` tag (from settings)
- `user_id` tag (from auth, if signed in)
- `app_version` + `platform`

**Environment separation:**
```dart
options.environment = kDebugMode ? 'development' : 'production';
```

Filter dev noise vs real user issues in Sentry dashboard. Same DSN for both.

**DSN configuration:** Goes into `env.json`. When `env.json` absent (local-only mode), Sentry disabled -- mirrors existing sync-disabled pattern.

**How Talker feeds Sentry** (custom `TalkerObserver`):
- `error` -> `Sentry.captureException(error, stackTrace: st)`
- `warning` -> `Sentry.addBreadcrumb(level: warning)`
- `info` -> `Sentry.addBreadcrumb(level: info)`
- `debug` -> `Sentry.addBreadcrumb(level: debug)`

## Supabase Log Table

### Schema

```sql
create table app_logs (
  id bigint generated always as identity primary key,
  device_id text not null,
  user_id uuid references auth.users(id),
  level text not null,
  tag text,
  message text not null,
  error text,
  stack_trace text,
  app_version text,
  platform text,
  created_at timestamptz not null
);

create index idx_app_logs_device on app_logs(device_id, created_at desc);
create index idx_app_logs_level on app_logs(level, created_at desc);
```

### Auto-cleanup (7 days)

```sql
select cron.schedule('clean-old-logs', '0 3 * * *',
  $$DELETE FROM app_logs WHERE created_at < now() - interval '7 days'$$);
```

### RLS

Disabled on `app_logs` or use service role. Logs are write-only from client. Query from Supabase dashboard / SQL editor.

## Batch Flush Pipeline

- In-memory buffer (list of log entries)
- **Flush triggers:** every 30 minutes, on app resume, or when buffer hits 50 entries
- On flush: `supabase.from('app_logs').insert(batch)`
- If flush fails (offline): keep in buffer, retry on next trigger
- If app killed before flush: logs lost (acceptable -- Sentry captures errors independently)

## In-App Log Viewer

**Access:** Long-press app version text in Settings screen -> opens `TalkerScreen`.

**Features** (provided by `talker_flutter`):
- Color-coded by level
- Tap to expand full error + stack trace
- Filter by level, search by text
- Share/copy to clipboard

**Available in release builds** -- hidden behind gesture, not gated by `kDebugMode`.

## Existing Code Migration

Replace all `debugPrint` across 28 files:

| Current pattern                    | Becomes                                   |
|------------------------------------|-------------------------------------------|
| `debugPrint('[AUTH] ...')`         | `talker.info('[AUTH] ...')`               |
| `debugPrint('Error: $e')` in catch | `talker.error('[TAG] message', e, st)`   |
| `debugPrint` with no tag           | Add tag based on module                   |

Key improvements:
- Silent catches now report to Sentry
- `catch (e)` updated to `catch (e, st)` to capture stack traces
- No behavioral changes -- observability only

## File Structure

### New files

```
app/lib/core/logging/
  logging_service.dart        -- Talker init, global instance, provider
  sentry_observer.dart        -- TalkerObserver -> Sentry + buffer
  log_flush_service.dart      -- Batch buffer, 30-min timer, flush to Supabase

supabase/migrations/
  YYYYMMDD_create_app_logs.sql
```

### Modified files

```
app/lib/core/database/settings_dao.dart  -- add getDeviceId / setDeviceId
app/lib/main.dart                        -- init order: deviceId -> Sentry -> Talker -> app
app/lib/features/settings/               -- long-press gesture on version text
28 files across core/ and features/      -- debugPrint -> talker migration
```

### Providers

```dart
final talkerProvider = Provider<Talker>((ref) => ...);
final logFlushServiceProvider = Provider<LogFlushService>((ref) => ...);
final deviceIdProvider = FutureProvider<String>((ref) => ...);
```

## Initialization Order (main.dart)

1. Generate/load device ID from settings
2. `SentryFlutter.init()` with device ID tag + environment
3. Initialize Talker with custom `SentryObserver`
4. Attach `TalkerRiverpodObserver` to `ProviderScope`
5. Wrap app in `runZonedGuarded` for unhandled async errors

## New Dependencies

```yaml
dependencies:
  talker_flutter: ^4.0.0
  talker_riverpod_logger: ^2.0.0
  sentry_flutter: ^8.0.0
```
