-- Emergency stop after recurring SQL was installed. Run as the job/RPC owner.
-- Retains registrations, assignments, schedule rows, approvals and learning records.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
  job_id bigint;
  student uuid;
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    SELECT j.jobid INTO job_id FROM cron.job j
    WHERE j.jobname='cq-v4-recurring-release-seoul' AND j.database=current_database();
    IF FOUND AND NOT cron.unschedule(job_id) THEN
      RAISE EXCEPTION 'Could not unschedule the Seoul recurring release job';
    END IF;
  END IF;

  -- Wait for active release transactions before disabling their policies.
  FOR student IN
    SELECT p.student_user_id FROM public.cq_v4_student_weekday_policy p
    WHERE p.enabled ORDER BY p.student_user_id
  LOOP
    PERFORM public.cq_v4_lock_student_lesson_writes(student);
  END LOOP;
  UPDATE public.cq_v4_student_weekday_policy SET enabled=false WHERE enabled;
END;
$$;

-- Keep existing clients compatible and hard-stop both entry points.
CREATE OR REPLACE FUNCTION public.cq_v4_ensure_today_approved_lesson()
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $$ SELECT NULL::uuid; $$;
CREATE OR REPLACE FUNCTION public.cq_v4_run_recurring_releases()
RETURNS integer LANGUAGE sql VOLATILE SET search_path TO ''
AS $$ SELECT 0; $$;

COMMIT;
