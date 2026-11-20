-- REVIEW CANDIDATE ONLY. Do not run against production without approval.
-- Align student schedule's is_released with the approved new-work gate and immutable historical submissions.
-- Apply only after reviewed approved-weekday-release-gate and submission overlay; no production execution.
-- Preserve existing return columns, order, enrollment checks and lesson records.
CREATE OR REPLACE FUNCTION public.cq_v4_my_lesson_schedule()
RETURNS TABLE(chapter_uuid uuid, chapter_title text, lesson_date date, is_released boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
 SELECT s.chapter_id, c.title, s.lesson_date,
        (public.cq_v4_can_start_approved_lesson(s.chapter_id, (select auth.uid()))
         OR EXISTS (SELECT 1 FROM public.cq_v4_student_submissions done
                    WHERE done.child_user_id=(select auth.uid())
                      AND done.chapter_uuid=s.chapter_id))
 FROM public.cq_v4_lesson_schedule s
 JOIN public.cq_v4_pdf_chapters c
   ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id
 JOIN public.cq_v4_pdf_enrollments e
   ON e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id
 JOIN public.cq_v4_activities a
   ON a.chapter_uuid=s.chapter_id AND a.published_at IS NOT NULL
 WHERE s.student_user_id=(select auth.uid()) AND c.pdf_ready IS TRUE
 ORDER BY s.lesson_date, s.chapter_id;
$function$;

REVOKE ALL ON FUNCTION public.cq_v4_my_lesson_schedule() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_my_lesson_schedule() TO authenticated;
