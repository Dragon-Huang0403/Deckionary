-- Add soft-delete column to all synced tables
ALTER TABLE search_history ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE review_cards ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE review_logs ADD COLUMN deleted_at TIMESTAMPTZ;

-- search_history needs updated_at for pull filtering (to discover soft-deletes)
ALTER TABLE search_history ADD COLUMN updated_at TIMESTAMPTZ;
UPDATE search_history SET updated_at = searched_at;
ALTER TABLE search_history ALTER COLUMN updated_at SET NOT NULL;
ALTER TABLE search_history ALTER COLUMN updated_at SET DEFAULT now();

-- review_logs needs updated_at for pull filtering
ALTER TABLE review_logs ADD COLUMN updated_at TIMESTAMPTZ;
UPDATE review_logs SET updated_at = reviewed_at;
ALTER TABLE review_logs ALTER COLUMN updated_at SET NOT NULL;
ALTER TABLE review_logs ALTER COLUMN updated_at SET DEFAULT now();
