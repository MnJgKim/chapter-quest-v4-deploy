-- Separate operational approval required. Supabase pg_cron must be enabled first.
-- Run as the DB owner after the recurring publication transaction is installed.
-- Use the Seoul zone when interpreting the job; the expression itself is UTC.
BEGIN;
DO $$
BEGIN
  IF current_setting('cron.timezone',true) IS DISTINCT FROM 'GMT'
     AND current_setting('cron.timezone',true) IS DISTINCT FROM 'UTC'
  THEN RAISE EXCEPTION 'Verify that pg_cron is configured for UTC before enabling release'; END IF;
END $$;
SELECT cron.schedule('cq-v4-recurring-release-seoul', '0 15 * * *',
  'SELECT public.cq_v4_run_recurring_releases()');
COMMIT;
