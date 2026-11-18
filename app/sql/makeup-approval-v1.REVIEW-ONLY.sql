-- REVIEW ONLY — DO NOT APPLY TO PRODUCTION.
-- Depends on existing cq_v4_parent_schedule_lesson and release RPC.
-- Migration must be tested with a transaction and rollback in an isolated clone.
CREATE TABLE IF NOT EXISTS public.cq_v4_makeup_approvals (
  approval_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id uuid NOT NULL,
  student_user_id uuid NOT NULL,
  chapter_id uuid NOT NULL,
  original_lesson_date date NOT NULL,
  approved_lesson_date date NOT NULL,
  approved_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cq_v4_makeup_date_changed CHECK (original_lesson_date <> approved_lesson_date)
);
ALTER TABLE public.cq_v4_makeup_approvals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_makeup_approvals FROM PUBLIC,anon,authenticated;
-- No direct table writes from browsers. Only audited parent RPC writes via definer.
CREATE OR REPLACE FUNCTION public.cq_v4_parent_schedule_lesson(
 p_student_user_id uuid,p_chapter_id uuid,p_lesson_date date
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
 v_parent uuid := auth.uid();
 v_old_date date;
 v_released timestamptz;
 v_now date := (now() AT TIME ZONE 'Asia/Seoul')::date;
BEGIN
 IF v_parent IS NULL OR NOT public.cq_is_admin() THEN
   RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501';
 END IF;
 IF p_lesson_date IS NULL OR p_lesson_date < v_now THEN
   RAISE EXCEPTION 'Schedule date must be today or later' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM public.cq_v4_pdf_enrollments e
  JOIN public.cq_v4_pdf_chapters c ON c.parent_user_id=e.parent_user_id
  JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
  WHERE e.parent_user_id=v_parent AND e.student_user_id=p_student_user_id
    AND c.chapter_id=p_chapter_id AND c.pdf_ready IS TRUE
 ) THEN RAISE EXCEPTION 'Approved PDF and enrolled student required' USING ERRCODE='42501';
 END IF;
 -- Serialize with the submission RPC for this student/chapter pair before checking completion.
 -- Both paths must acquire this same transaction advisory lock before any state reads.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_student_user_id::text || ':' || p_chapter_id::text, 0));
 -- Existing immutable submissions may never be rescheduled by this RPC.
 IF EXISTS (
   SELECT 1 FROM public.cq_v4_student_submissions done
   WHERE done.child_user_id=p_student_user_id AND done.chapter_uuid=p_chapter_id
 ) THEN RAISE EXCEPTION 'Completed lessons cannot be rescheduled' USING ERRCODE='42501';
 END IF;
 SELECT s.lesson_date,s.released_at INTO v_old_date,v_released
 FROM public.cq_v4_lesson_schedule s
 WHERE s.parent_user_id=v_parent AND s.student_user_id=p_student_user_id AND s.chapter_id=p_chapter_id
 FOR UPDATE;
 IF FOUND THEN
   IF v_old_date < v_now AND v_old_date IS DISTINCT FROM p_lesson_date THEN
     INSERT INTO public.cq_v4_makeup_approvals(
       parent_user_id,student_user_id,chapter_id,original_lesson_date,approved_lesson_date
     ) VALUES(v_parent,p_student_user_id,p_chapter_id,v_old_date,p_lesson_date);
   END IF;
   UPDATE public.cq_v4_lesson_schedule s
   SET lesson_date=p_lesson_date
   WHERE s.parent_user_id=v_parent AND s.student_user_id=p_student_user_id AND s.chapter_id=p_chapter_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Schedule update not authorized' USING ERRCODE='42501'; END IF;
 ELSE
   INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
   VALUES(v_parent,p_student_user_id,p_chapter_id,p_lesson_date)
   ON CONFLICT(student_user_id,chapter_id) DO NOTHING;
   -- Concurrent insertion must retry through the locked existing-row path.
   -- An UPSERT UPDATE here could bypass the makeup audit and completion check.
   IF NOT FOUND THEN RAISE EXCEPTION 'Concurrent schedule change: retry with current schedule' USING ERRCODE='40001'; END IF;
 END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_schedule_lesson(uuid,uuid,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_schedule_lesson(uuid,uuid,date) TO authenticated;
-- Important: revoke direct UPDATE on lesson_schedule from authenticated and
-- audit all other SECURITY DEFINER schedule writers before deployment.
-- New date alone is not sufficient: existing released_at and publication
-- status must still be checked by cq_v4_can_start_lesson.
-- No historical student submissions are modified by this migration.
