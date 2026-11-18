-- ISOLATED CI ONLY. Never execute against a Supabase project.
\set ON_ERROR_STOP on
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA storage;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE public.cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid NOT NULL,pdf_ready boolean NOT NULL DEFAULT false,title text NOT NULL);
CREATE TABLE public.cq_v4_pdf_assignments(chapter_id uuid NOT NULL,student_user_id uuid NOT NULL,PRIMARY KEY(chapter_id,student_user_id));
CREATE TABLE public.cq_v4_pdf_enrollments(parent_user_id uuid NOT NULL,student_user_id uuid NOT NULL,PRIMARY KEY(parent_user_id,student_user_id));
CREATE TABLE public.cq_v4_activities(chapter_uuid uuid PRIMARY KEY,published_at timestamptz,questions jsonb);
CREATE TABLE public.cq_v4_lesson_schedule(parent_user_id uuid NOT NULL,student_user_id uuid NOT NULL,chapter_id uuid NOT NULL,lesson_date date NOT NULL,timezone text DEFAULT 'Asia/Seoul',released_at timestamptz,PRIMARY KEY(student_user_id,chapter_id));
CREATE TABLE public.cq_v4_student_submissions(chapter_uuid uuid NOT NULL,child_user_id uuid NOT NULL,answers jsonb NOT NULL,submitted_at timestamptz NOT NULL DEFAULT now(),PRIMARY KEY(chapter_uuid,child_user_id));
CREATE TABLE storage.objects(id uuid DEFAULT gen_random_uuid(),bucket_id text NOT NULL,name text NOT NULL,PRIMARY KEY(bucket_id,name));
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE POLICY isolated_speaking_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='cq-v4-speaking');
CREATE FUNCTION public.cq_v4_is_released(p_chapter uuid,p_student uuid) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT EXISTS(SELECT 1 FROM public.cq_v4_lesson_schedule WHERE chapter_id=p_chapter AND student_user_id=p_student AND released_at IS NOT NULL) $$;
CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT auth.uid()='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'::uuid $$;
GRANT USAGE ON SCHEMA public,storage,auth TO authenticated;
GRANT SELECT,INSERT,UPDATE ON storage.objects TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cq_v4_is_released(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cq_is_admin() TO authenticated;
