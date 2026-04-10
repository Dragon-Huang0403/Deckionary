CREATE TABLE search_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  query TEXT NOT NULL,
  entry_id INTEGER,
  headword TEXT,
  searched_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_search_history_user ON search_history(user_id, searched_at DESC);

ALTER TABLE search_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_data" ON search_history
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
