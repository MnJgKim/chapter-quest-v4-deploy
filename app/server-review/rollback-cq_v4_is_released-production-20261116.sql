-- CAPTURED FROM LIVE PRODUCTION BEFORE AUTHORIZED PATCH ON 2026-11-16.
-- ROLLBACK ONLY. This is the original function body and original grants.
-- owner: postgres; anon EXECUTE: false; authenticated EXECUTE: true; service_role EXECUTE: true
CREATE OR REPLACE FUNCTION public.cq_v4_is_released(p_chapter uuid, p_student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT EXISTS (
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
GRANT EXECUTE ON FUNCTION public.cq_v4_is_released(uuid,uuid) TO authenticated,service_role;
