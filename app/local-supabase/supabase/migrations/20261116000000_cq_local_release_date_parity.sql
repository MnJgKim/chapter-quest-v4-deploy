-- Isolated local test stack only: mirror production lesson-date authorization.
ALTER TABLE public.cq_v4_lesson_schedule
  ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'Asia/Seoul';

CREATE OR REPLACE FUNCTION public.cq_v4_is_released(p_chapter uuid, p_student uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT EXISTS(
  SELECT 1 FROM public.cq_v4_lesson_schedule s
  JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id AND c.pdf_ready IS TRUE
  JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=s.chapter_id AND a.student_user_id=s.student_user_id
  JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id
  JOIN public.cq_v4_activities act ON act.chapter_uuid=s.chapter_id AND act.published_at IS NOT NULL
  WHERE s.chapter_id=p_chapter AND s.student_user_id=p_student
    AND s.released_at IS NOT NULL
    AND (now() AT TIME ZONE COALESCE(NULLIF(s.timezone,''),'Asia/Seoul'))::date >= s.lesson_date
 );
$function$;
REVOKE ALL ON FUNCTION public.cq_v4_is_released(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_is_released(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_my_released_chapters()
RETURNS TABLE(chapter_uuid uuid,chapter_title text,questions jsonb,lesson_date date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT c.chapter_id,c.title,act.questions,s.lesson_date
 FROM public.cq_v4_lesson_schedule s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=s.chapter_id AND a.student_user_id=s.student_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id
 JOIN public.cq_v4_activities act ON act.chapter_uuid=s.chapter_id AND act.published_at IS NOT NULL
 WHERE s.student_user_id=(select auth.uid()) AND public.cq_v4_is_released(s.chapter_id,(select auth.uid()))
 ORDER BY s.lesson_date,s.chapter_id;
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_chapter_activities(p_chapter_uuid uuid)
RETURNS TABLE(vocabulary jsonb,writing_prompt text,speaking_prompt text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT act.vocabulary,act.writing_prompt,act.speaking_prompt
 FROM public.cq_v4_activities act
 WHERE act.chapter_uuid=p_chapter_uuid
 AND public.cq_v4_is_released(p_chapter_uuid,(select auth.uid()));
$function$;
