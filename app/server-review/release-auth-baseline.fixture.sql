-- Isolated PGlite fixture ONLY; never apply to hosted Supabase.
-- Apply after existing public V4 tables/auth.uid() setup, before release-auth-candidate.sql.
CREATE TABLE IF NOT EXISTS public.cq_v4_lesson_schedule (
 parent_user_id uuid NOT NULL,
 student_user_id uuid NOT NULL,
 chapter_id uuid NOT NULL,
 lesson_date date NOT NULL,
 timezone text NOT NULL DEFAULT 'Asia/Seoul',
 created_at timestamptz NOT NULL DEFAULT now(),
 released_at timestamptz,
 CONSTRAINT cq_v4_lesson_schedule_pkey PRIMARY KEY (student_user_id,chapter_id),
 CONSTRAINT cq_v4_lesson_schedule_chapter_id_fkey FOREIGN KEY (chapter_id)
  REFERENCES public.cq_v4_pdf_chapters(chapter_id),
 CONSTRAINT cq_v4_lesson_schedule_timezone CHECK (timezone='Asia/Seoul')
);
CREATE OR REPLACE FUNCTION public.cq_v4_is_released(p_chapter uuid,p_student uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
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
GRANT EXECUTE ON FUNCTION public.cq_v4_is_released(uuid,uuid) TO authenticated;
