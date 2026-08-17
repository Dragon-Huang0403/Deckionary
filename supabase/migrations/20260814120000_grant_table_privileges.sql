-- Grant table privileges explicitly instead of relying on implicit default privileges.
--
-- Every table here was created without a GRANT, which worked because Supabase sets
-- ALTER DEFAULT PRIVILEGES for anon/authenticated/service_role in the public schema.
-- Newer local Supabase stacks no longer apply those defaults to migration-created
-- tables, so `supabase start` + `flutter test` failed with:
--
--   PostgrestException(message: permission denied for table user_settings, code: 42501)
--
-- These grants are a no-op on Supabase Cloud, where the same privileges already exist,
-- and they make the schema reproducible on any CLI version.
--
-- Security is unchanged: RLS is enabled on all of these tables and every policy still
-- gates rows by auth.uid(). Table privileges only decide who may attempt a query;
-- RLS decides which rows they see. service_role bypasses RLS by design and is used
-- only by the integration tests and trusted server-side code.

GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_logs TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.review_cards TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.review_logs TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.search_history TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.speaking_audio_cache TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.speaking_results TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_settings TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.vocabulary_list_entries TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.vocabulary_lists TO authenticated, service_role;
