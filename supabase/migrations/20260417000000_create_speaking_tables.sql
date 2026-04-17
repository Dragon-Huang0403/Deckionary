-- speaking_results: user speech analysis results from GPT-4o
CREATE TABLE speaking_results (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  topic TEXT NOT NULL,
  is_custom_topic BOOLEAN NOT NULL DEFAULT false,
  transcript TEXT NOT NULL,
  corrections_json JSONB NOT NULL,
  natural_version TEXT NOT NULL,
  overall_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_speaking_results_sync ON speaking_results(user_id, updated_at DESC);

ALTER TABLE speaking_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_data" ON speaking_results
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- speaking_audio_cache: server-side TTS audio cache (accessed by edge functions via service role)
CREATE TABLE speaking_audio_cache (
  text_hash TEXT PRIMARY KEY,
  audio_data BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS enabled with no user-facing policies = service-role-only access
ALTER TABLE speaking_audio_cache ENABLE ROW LEVEL SECURITY;
