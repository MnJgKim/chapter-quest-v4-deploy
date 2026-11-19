-- Isolated PostgreSQL fixtures only; never run on production.
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid $$;
CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT current_setting('test.admin',true)='yes' $$;
CREATE TABLE public.cq_v4_pdf_enrollments(parent_user_id uuid,student_user_id uuid);
CREATE TABLE public.cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid,title text,storage_path text,pdf_ready boolean,pdf_verified_at timestamptz,created_at timestamptz);
CREATE TABLE public.cq_v4_pdf_assignments(chapter_id uuid,student_user_id uuid,assigned_at timestamptz);
CREATE TABLE public.cq_v4_activities(chapter_uuid uuid,questions jsonb,vocabulary jsonb,writing_prompt text,speaking_prompt text,published_at timestamptz,approval_id uuid,approval_hash text);
CREATE TABLE public.cq_v4_lesson_schedule(parent_user_id uuid,student_user_id uuid,chapter_id uuid,lesson_date date,timezone text DEFAULT 'Asia/Seoul',created_at timestamptz,released_at timestamptz,UNIQUE(student_user_id,chapter_id));
CREATE TABLE public.cq_v4_student_submissions(chapter_uuid uuid,child_user_id uuid,answers jsonb,submitted_at timestamptz DEFAULT now(),UNIQUE(chapter_uuid,child_user_id));
CREATE SCHEMA storage;
CREATE TABLE storage.objects(bucket_id text,name text);
CREATE FUNCTION public.cq_v4_is_released(p_chapter uuid,p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM public.cq_v4_lesson_schedule s
 WHERE s.chapter_id=p_chapter AND s.student_user_id=p_student AND s.released_at IS NOT NULL
 AND s.lesson_date <= (now() AT TIME ZONE 'Asia/Seoul')::date);
$$;
