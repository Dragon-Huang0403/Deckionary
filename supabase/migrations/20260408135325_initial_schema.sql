-- User profiles (extends auth.users)
CREATE TABLE profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read/write own profile"
    ON profiles FOR ALL USING (auth.uid() = id);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO profiles (id) VALUES (NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- FSRS review cards
CREATE TABLE review_cards (
    id              UUID PRIMARY KEY,
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    entry_id        INTEGER NOT NULL,
    headword        TEXT NOT NULL,
    pos             TEXT NOT NULL DEFAULT '',
    due             TIMESTAMPTZ NOT NULL,
    stability       DOUBLE PRECISION NOT NULL DEFAULT 0,
    difficulty      DOUBLE PRECISION NOT NULL DEFAULT 0,
    elapsed_days    INTEGER NOT NULL DEFAULT 0,
    scheduled_days  INTEGER NOT NULL DEFAULT 0,
    reps            INTEGER NOT NULL DEFAULT 0,
    lapses          INTEGER NOT NULL DEFAULT 0,
    state           INTEGER NOT NULL DEFAULT 0,
    last_review     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_rc_user_due ON review_cards(user_id, due);
ALTER TABLE review_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their cards"
    ON review_cards FOR ALL USING (auth.uid() = user_id);

-- FSRS review logs
CREATE TABLE review_logs (
    id              UUID PRIMARY KEY,
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    card_id         UUID NOT NULL REFERENCES review_cards(id) ON DELETE CASCADE,
    rating          INTEGER NOT NULL,
    state           INTEGER NOT NULL,
    due             TIMESTAMPTZ NOT NULL,
    stability       DOUBLE PRECISION NOT NULL,
    difficulty      DOUBLE PRECISION NOT NULL,
    elapsed_days    INTEGER NOT NULL,
    scheduled_days  INTEGER NOT NULL,
    reviewed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_rl_card ON review_logs(card_id);
CREATE INDEX idx_rl_user_date ON review_logs(user_id, reviewed_at);
ALTER TABLE review_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their logs"
    ON review_logs FOR ALL USING (auth.uid() = user_id);

-- Vocabulary lists
CREATE TABLE vocabulary_lists (
    id              UUID PRIMARY KEY,
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    description     TEXT NOT NULL DEFAULT '',
    is_preset       BOOLEAN NOT NULL DEFAULT false,
    preset_type     TEXT NOT NULL DEFAULT '',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_vl_user ON vocabulary_lists(user_id);
ALTER TABLE vocabulary_lists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their lists"
    ON vocabulary_lists FOR ALL USING (auth.uid() = user_id);

-- Vocabulary list entries
CREATE TABLE vocabulary_list_entries (
    id              UUID PRIMARY KEY,
    list_id         UUID NOT NULL REFERENCES vocabulary_lists(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    entry_id        INTEGER NOT NULL,
    headword        TEXT NOT NULL,
    added_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(list_id, entry_id)
);
CREATE INDEX idx_vle_list ON vocabulary_list_entries(list_id);
ALTER TABLE vocabulary_list_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their list entries"
    ON vocabulary_list_entries FOR ALL USING (auth.uid() = user_id);

-- User settings (JSON blob)
CREATE TABLE user_settings (
    user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    settings_json   JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their settings"
    ON user_settings FOR ALL USING (auth.uid() = user_id);

-- Create audio storage bucket
INSERT INTO storage.buckets (id, name, public) VALUES ('audio', 'audio', true);
