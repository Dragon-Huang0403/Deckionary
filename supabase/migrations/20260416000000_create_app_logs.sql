-- Diagnostic log table for remote observability.
-- Logs are write-only from clients, queried from Supabase dashboard.
-- Auto-cleaned after 7 days via pg_cron.

CREATE TABLE app_logs (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  device_id  TEXT        NOT NULL,
  user_id    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  level      TEXT        NOT NULL,
  tag        TEXT,
  message    TEXT        NOT NULL,
  error      TEXT,
  stack_trace TEXT,
  app_version TEXT,
  platform   TEXT,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_app_logs_device ON app_logs(device_id, created_at DESC);
CREATE INDEX idx_app_logs_level  ON app_logs(level, created_at DESC);

-- Allow any client to insert logs (including unauthenticated).
-- No SELECT/UPDATE/DELETE from client — query from dashboard only.
ALTER TABLE app_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_insert" ON app_logs FOR INSERT WITH CHECK (true);

-- Auto-delete logs older than 7 days (runs daily at 03:00 UTC).
DO $$ BEGIN
  PERFORM cron.schedule(
    'clean-old-app-logs',
    '0 3 * * *',
    $$DELETE FROM app_logs WHERE created_at < now() - interval '7 days'$$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron not available, skipping auto-cleanup schedule';
END $$;
