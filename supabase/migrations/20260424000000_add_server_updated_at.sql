-- Add server-authoritative timestamp column for pull watermarks on all synced
-- tables. The existing `updated_at` is client-generated and sent verbatim in
-- upserts, which creates a race: a delayed push can land on the server with an
-- `updated_at` older than another device's pull cursor, permanently skipping
-- the record. `server_updated_at` is set by a trigger at write time, so it's
-- strictly monotonic per arrival order and safe to use as a cursor.
--
-- `updated_at` is kept for last-write-wins conflict resolution (user intent),
-- `server_updated_at` is used only by the pull watermark.

-- ── Trigger function (shared by all synced tables) ──────────────────────────

CREATE OR REPLACE FUNCTION set_server_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.server_updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── review_cards ────────────────────────────────────────────────────────────

ALTER TABLE review_cards
  ADD COLUMN server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
UPDATE review_cards SET server_updated_at = updated_at;

CREATE TRIGGER trg_review_cards_server_updated_at
  BEFORE INSERT OR UPDATE ON review_cards
  FOR EACH ROW EXECUTE FUNCTION set_server_updated_at();

DROP INDEX IF EXISTS idx_review_cards_user;
CREATE INDEX idx_review_cards_sync
  ON review_cards(user_id, server_updated_at DESC);

-- ── review_logs ─────────────────────────────────────────────────────────────

ALTER TABLE review_logs
  ADD COLUMN server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
UPDATE review_logs SET server_updated_at = updated_at;

CREATE TRIGGER trg_review_logs_server_updated_at
  BEFORE INSERT OR UPDATE ON review_logs
  FOR EACH ROW EXECUTE FUNCTION set_server_updated_at();

DROP INDEX IF EXISTS idx_review_logs_user;
CREATE INDEX idx_review_logs_sync
  ON review_logs(user_id, server_updated_at DESC);

-- ── search_history ──────────────────────────────────────────────────────────

ALTER TABLE search_history
  ADD COLUMN server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
UPDATE search_history SET server_updated_at = updated_at;

CREATE TRIGGER trg_search_history_server_updated_at
  BEFORE INSERT OR UPDATE ON search_history
  FOR EACH ROW EXECUTE FUNCTION set_server_updated_at();

DROP INDEX IF EXISTS idx_search_history_user;
CREATE INDEX idx_search_history_sync
  ON search_history(user_id, server_updated_at DESC);

-- ── vocabulary_lists ────────────────────────────────────────────────────────

ALTER TABLE vocabulary_lists
  ADD COLUMN server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
UPDATE vocabulary_lists SET server_updated_at = updated_at;

CREATE TRIGGER trg_vocabulary_lists_server_updated_at
  BEFORE INSERT OR UPDATE ON vocabulary_lists
  FOR EACH ROW EXECUTE FUNCTION set_server_updated_at();

DROP INDEX IF EXISTS idx_vocabulary_lists_user;
CREATE INDEX idx_vocabulary_lists_sync
  ON vocabulary_lists(user_id, server_updated_at DESC);

-- ── vocabulary_list_entries ─────────────────────────────────────────────────

ALTER TABLE vocabulary_list_entries
  ADD COLUMN server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
UPDATE vocabulary_list_entries SET server_updated_at = updated_at;

CREATE TRIGGER trg_vocabulary_list_entries_server_updated_at
  BEFORE INSERT OR UPDATE ON vocabulary_list_entries
  FOR EACH ROW EXECUTE FUNCTION set_server_updated_at();

DROP INDEX IF EXISTS idx_vocabulary_list_entries_user;
CREATE INDEX idx_vocabulary_list_entries_sync
  ON vocabulary_list_entries(user_id, server_updated_at DESC);

-- ── speaking_results ────────────────────────────────────────────────────────

ALTER TABLE speaking_results
  ADD COLUMN server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
UPDATE speaking_results SET server_updated_at = updated_at;

CREATE TRIGGER trg_speaking_results_server_updated_at
  BEFORE INSERT OR UPDATE ON speaking_results
  FOR EACH ROW EXECUTE FUNCTION set_server_updated_at();

DROP INDEX IF EXISTS idx_speaking_results_sync;
CREATE INDEX idx_speaking_results_sync
  ON speaking_results(user_id, server_updated_at DESC);
