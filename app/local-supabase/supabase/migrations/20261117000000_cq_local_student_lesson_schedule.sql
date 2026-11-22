-- Local CI parity only. Source: review/rollback-snapshots/20261116-cq_v4_my_lesson_schedule.sql
-- Do not apply this migration to hosted or production Supabase.
-- Retain the hosted function's existing return shape and enrollment/publication gates.
CREATE OR REPLACE FUNCTION public.cq_v4_my_lesson_schedule()
RETURNS TABLE(chapter_uuid uuid, chapter_title text, lesson_date date, is_released boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
 SELECT s.chapter_id,c.title,s.lesson_date,s.released_at IS NOT NULL
 FROM public.cq_v4_lesson_schedule s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id
 JOIN public.cq_v4_activities a ON a.chapter_uuid=s.chapter_id AND a.published_at IS NOT NULL
 WHERE s.student_user_id=(SELECT auth.uid()) AND c.pdf_ready IS TRUE
 ORDER BY s.lesson_date,s.chapter_id;
$function$;

REVOKE ALL ON FUNCTION public.cq_v4_my_lesson_schedule() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_my_lesson_schedule() TO authenticated;
