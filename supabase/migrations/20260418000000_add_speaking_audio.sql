-- Add audio storage key to speaking_results (per-row pointer to bucket object)
ALTER TABLE speaking_results ADD COLUMN audio_storage_key TEXT;

-- Private bucket for user recordings. Object key layout: <user_id>/<attempt_id>.wav
INSERT INTO storage.buckets (id, name, public)
VALUES ('speaking-audio', 'speaking-audio', false)
ON CONFLICT (id) DO NOTHING;

-- Owner-prefix RLS: users may only operate on objects under their own <user_id>/ prefix
CREATE POLICY "speaking_audio_owner_read" ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'speaking-audio'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "speaking_audio_owner_insert" ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'speaking-audio'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "speaking_audio_owner_update" ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'speaking-audio'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "speaking_audio_owner_delete" ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'speaking-audio'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
