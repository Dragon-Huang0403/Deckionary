-- vocabulary_lists: user-created word collections (e.g., "My Words")
CREATE TABLE vocabulary_lists (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  UNIQUE(user_id, name)
);

CREATE INDEX idx_vocabulary_lists_user ON vocabulary_lists(user_id, updated_at DESC);

ALTER TABLE vocabulary_lists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_data" ON vocabulary_lists
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- vocabulary_list_entries: words belonging to a list
CREATE TABLE vocabulary_list_entries (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  list_id UUID NOT NULL REFERENCES vocabulary_lists(id),
  entry_id INTEGER NOT NULL,
  headword TEXT NOT NULL,
  pos TEXT DEFAULT '',
  added_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_vocabulary_list_entries_user ON vocabulary_list_entries(user_id, updated_at DESC);
CREATE INDEX idx_vocabulary_list_entries_list ON vocabulary_list_entries(list_id, deleted_at);

ALTER TABLE vocabulary_list_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_data" ON vocabulary_list_entries
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
