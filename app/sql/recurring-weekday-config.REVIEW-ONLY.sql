-- Isolated test or explicitly approved rollout only.
-- psql variables are full, independently verified account IDs and owning parent IDs.
\set ON_ERROR_STOP on
BEGIN;
WITH requested(student_id,parent_id,days,start_day,enabled) AS (
 VALUES
  (:'seowoo_student'::uuid,:'seowoo_parent'::uuid,ARRAY[1,3,4],DATE '2026-11-23',true),
  (:'seojin_student'::uuid,:'seojin_parent'::uuid,ARRAY[2,3,5],DATE '2026-11-24',true),
  (:'siwoo_student'::uuid,:'siwoo_parent'::uuid,ARRAY[1,2,3,4,5],DATE 'infinity',false)
), validated AS (
 SELECT count(DISTINCT r.student_id)=3 AND bool_and(EXISTS (
   SELECT 1 FROM public.cq_v4_pdf_enrollments e
   WHERE e.student_user_id=r.student_id AND e.parent_user_id=r.parent_id
 )) AS valid FROM requested r
)
INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,weekdays,effective_from,enabled)
SELECT CASE WHEN validated.valid THEN r.student_id END,r.days,r.start_day,r.enabled
FROM requested r CROSS JOIN validated
ON CONFLICT (student_user_id) DO UPDATE
SET weekdays=excluded.weekdays,effective_from=excluded.effective_from,enabled=excluded.enabled
RETURNING student_user_id,weekdays,effective_from,enabled;
COMMIT;
