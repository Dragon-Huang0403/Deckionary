-- Add per-word pronunciation feedback (audio analyses only).
-- Nullable: rows created before this migration + all text-mode rows stay NULL.
ALTER TABLE speaking_results
  ADD COLUMN pronunciation_issues_json jsonb;
