-- REVIEW ONLY. A restrictive server-clock gate, NOT yet wired into production.
-- Requires existing lesson schedule, approved queue, weekday policy and makeup audit.
-- Never accepts client-supplied dates; never creates assignments or schedules.
CREATE OR REPLACE FUNCTION public.cq_v4_can_start_approved_lesson(
 p_chapter uuid, p_student uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 WITH clock AS (
   SELECT (now() AT TIME ZONE 'Asia/Seoul')::date AS today
 )
 SELECT p_student=(SELECT auth.uid())
   AND public.cq_v4_can_start_lesson(p_chapter,p_student)
   AND EXISTS (
     SELECT 1
     FROM public.cq_v4_lesson_schedule s
     JOIN public.cq_v4_approved_chapter_queue q
       ON q.student_user_id=s.student_user_id AND q.chapter_id=s.chapter_id
       AND q.parent_user_id=s.parent_user_id
     CROSS JOIN clock
     WHERE s.student_user_id=p_student AND s.chapter_id=p_chapter
       AND s.lesson_date=clock.today
       AND public.cq_v4_next_approved_chapter(p_student)=p_chapter
       AND (
         EXISTS (
           SELECT 1 FROM public.cq_v4_student_weekday_policy pol
           WHERE pol.student_user_id=p_student AND pol.enabled IS TRUE
             AND pol.effective_from<=clock.today
             AND EXTRACT(ISODOW FROM clock.today)::integer=ANY(pol.weekdays)
         )
         OR EXISTS (
           SELECT 1 FROM public.cq_v4_makeup_approvals m
           WHERE m.parent_user_id=s.parent_user_id
             AND m.student_user_id=s.student_user_id
             AND m.chapter_id=s.chapter_id
             AND m.approved_lesson_date=clock.today
             AND m.original_lesson_date<clock.today
         )
       )
   );
$$;
REVOKE ALL ON FUNCTION public.cq_v4_can_start_approved_lesson(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_can_start_approved_lesson(uuid,uuid) TO authenticated;
-- INTEGRATION BLOCKERS:
-- 1. Existing submit/storage/PDF RPCs still use cq_v4_can_start_lesson.
-- 2. Existing schedule rows must be reviewed before enforcing the queue.
-- 3. A parent-authorized atomic coordinator must populate lesson_date.
-- 4. Concurrent submissions and reschedules must be tested with real PostgreSQL.
