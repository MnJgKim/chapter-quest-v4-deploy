-- DEVELOPMENT REVIEW ONLY — DO NOT RUN AGAINST PRODUCTION.
-- SQL staged for an isolated clone after owner approval and security review.
-- The existing cq_v4_is_released is deliberately NOT replaced: it is used by
-- historical submission / feedback / recording READ authorization.
--
-- Same-day *new work* permission; parent can reschedule via existing parent RPC,
-- but explicit auditable makeup approval is still a separate release blocker.
CREATE OR REPLACE FUNCTION public.cq_v4_can_start_lesson(p_chapter uuid, p_student uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 SELECT p_student = (SELECT auth.uid())
   AND NOT EXISTS (
     SELECT 1 FROM public.cq_v4_student_submissions done
     WHERE done.chapter_uuid=p_chapter AND done.child_user_id=p_student
   )
   AND EXISTS (
     SELECT 1 FROM public.cq_v4_lesson_schedule s
     JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id AND c.pdf_ready IS TRUE
     JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=s.chapter_id AND a.student_user_id=s.student_user_id
     JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id
     JOIN public.cq_v4_activities act ON act.chapter_uuid=s.chapter_id AND act.published_at IS NOT NULL
     WHERE s.chapter_id=p_chapter AND s.student_user_id=p_student
       AND s.released_at IS NOT NULL
       AND s.lesson_date=(now() AT TIME ZONE 'Asia/Seoul')::date
   );
$$;
REVOKE ALL ON FUNCTION public.cq_v4_can_start_lesson(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_can_start_lesson(uuid,uuid) TO authenticated;

-- Historical read is an explicit SECURITY DEFINER predicate because the
-- submission table intentionally has RLS enabled and NO client SELECT policy.
-- This function returns only a boolean, never another student's submission.
CREATE OR REPLACE FUNCTION public.cq_v4_can_read_lesson(p_chapter uuid,p_student uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $
 SELECT p_student=(SELECT auth.uid())
   AND (
     public.cq_v4_can_start_lesson(p_chapter,p_student)
     OR EXISTS (
       SELECT 1 FROM public.cq_v4_student_submissions done
       JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=done.chapter_uuid AND c.pdf_ready IS TRUE
       JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id AND a.student_user_id=done.child_user_id
       JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=done.child_user_id
       JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
       WHERE done.chapter_uuid=p_chapter AND done.child_user_id=p_student
     )
   );
$;
REVOKE ALL ON FUNCTION public.cq_v4_can_read_lesson(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_can_read_lesson(uuid,uuid) TO authenticated;

-- Recommended RPC refactor in the same atomic migration:
-- In cq_v4_submit_answers, keep existing validation and idempotency semantics.
-- Before processing a NEW submission, check:
--   IF EXISTS (SELECT 1 FROM public.cq_v4_student_submissions
--              WHERE chapter_uuid=p_chapter_uuid AND child_user_id=auth.uid())
--   THEN return its existing immutable record (without modifying it).
--   ELSE IF NOT public.cq_v4_can_start_lesson(p_chapter_uuid,auth.uid())
--        THEN raise exception 'Lesson day is not open' using errcode='42501';
--   END IF;
-- The old REVIEW-ONLY before-INSERT trigger should NOT be deployed as-is;
-- it can reject ON CONFLICT DO NOTHING and is not a full start gate.

-- SPEAKING INSERT: preserve existing name/ownership checks and ADD the
-- same-day predicate. Do not change the SELECT policy (history remains readable).
-- Existing policy body must be copied verbatim from the target environment
-- before applying the extra AND public.cq_v4_can_start_lesson(...).
-- Do not blindly DROP existing policies.

-- SECURITY REVIEW REQUIRED:
-- (1) published question retrieval must expose questions only for can_start,
--     or for the same student's already-submitted immutable record if needed;
-- (2) PDF-link Edge Function must enforce can_start for new work, and a
--     separate authorized historical-read predicate for completed submissions;
-- (3) client-only controls cannot enforce the above;
-- (4) past lesson rescheduling requires explicit parent-approved makeup audit;
-- (5) server clock boundary, RLS, definer grants, storage insert/upsert,
--     cross-student and replay tests must pass before any production change.
