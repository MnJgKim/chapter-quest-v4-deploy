\set ON_ERROR_STOP on
-- Disposable PostgreSQL 16 only. No production connectivity.
BEGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
GRANT authenticated TO CURRENT_USER;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS 'SELECT nullif(current_setting(''test.uid'',true),'''')::uuid';
CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE AS 'SELECT auth.uid() = ''00000000-0000-0000-0000-000000000001''::uuid';
CREATE TABLE public.cq_v4_approval_requests(
 id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,questions jsonb,answer_key jsonb,
 vocabulary jsonb,writing_prompt text,speaking_prompt text,content_hash text);
CREATE TABLE public.cq_v4_pdf_chapters(
 chapter_id uuid PRIMARY KEY,parent_user_id uuid,pdf_ready boolean,pdf_verified_at timestamptz,storage_path text);
CREATE TABLE public.cq_v4_pdf_enrollments(parent_user_id uuid,student_user_id uuid);
CREATE TABLE public.cq_v4_activities(
 chapter_uuid uuid PRIMARY KEY,questions jsonb,vocabulary jsonb,writing_prompt text,
 speaking_prompt text,published_at timestamptz,approval_id uuid,approval_hash text);
CREATE TABLE public.cq_v4_pdf_assignments(chapter_id uuid,student_user_id uuid,UNIQUE(chapter_id,student_user_id));
CREATE TABLE public.cq_v4_student_submissions(chapter_uuid uuid,child_user_id uuid);
INSERT INTO public.cq_v4_pdf_chapters VALUES
 ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000001',true,now(),'private/lesson.pdf');
INSERT INTO public.cq_v4_pdf_enrollments VALUES
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011');
INSERT INTO public.cq_v4_approval_requests VALUES
 ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000101',
 '[{"kind":"mc","options":["A","B"]}]','[1]','[]','Write','Speak','hash-a'),
 ('00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000101',
 '[{"kind":"mc","options":["A","B"]}]','[3]','[]','Write','Speak','hash-b');
\ir ../sql/development-reread-publish-validation-not-for-production.sql
\ir ../sql/development-publish-approved-reread-guard.REVIEW-ONLY.sql
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000001',false);
DO $test$
DECLARE v uuid; n integer;
BEGIN
 v:=public.cq_v4_publish_approved('00000000-0000-0000-0000-000000000201',ARRAY['00000000-0000-0000-0000-000000000011']::uuid[]);
 IF v <> '00000000-0000-0000-0000-000000000101'::uuid THEN RAISE EXCEPTION 'Wrong chapter'; END IF;
 SELECT count(*) INTO n FROM public.cq_v4_pdf_assignments;
 IF n<>1 THEN RAISE EXCEPTION 'Assignment missing'; END IF;
 -- Idempotent re-publish with same immutable payload.
 PERFORM public.cq_v4_publish_approved('00000000-0000-0000-0000-000000000201',ARRAY['00000000-0000-0000-0000-000000000011']::uuid[]);
 SELECT count(*) INTO n FROM public.cq_v4_pdf_assignments;
 IF n<>1 THEN RAISE EXCEPTION 'Duplicate assignment'; END IF;
 BEGIN
  PERFORM public.cq_v4_publish_approved('00000000-0000-0000-0000-000000000202',ARRAY['00000000-0000-0000-0000-000000000011']::uuid[]);
  RAISE EXCEPTION 'Invalid answer key accepted';
 EXCEPTION WHEN sqlstate '22023' THEN NULL; END;
 IF (SELECT approval_hash FROM public.cq_v4_activities WHERE chapter_uuid=v) <> 'hash-a'
 THEN RAISE EXCEPTION 'Failed publication changed content'; END IF;
 UPDATE public.cq_v4_approval_requests SET writing_prompt='Tampered' WHERE id='00000000-0000-0000-0000-000000000201';
 BEGIN
  PERFORM public.cq_v4_publish_approved('00000000-0000-0000-0000-000000000201',ARRAY['00000000-0000-0000-0000-000000000011']::uuid[]);
  RAISE EXCEPTION 'Tampered approved content accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 IF (SELECT writing_prompt FROM public.cq_v4_activities WHERE chapter_uuid=v) <> 'Write'
 THEN RAISE EXCEPTION 'Immutable publication changed'; END IF;
END $test$;
SELECT set_config('test.uid','00000000-0000-0000-0000-000000000011',false);
DO $test$
BEGIN
 BEGIN
  PERFORM public.cq_v4_publish_approved('00000000-0000-0000-0000-000000000201',ARRAY['00000000-0000-0000-0000-000000000011']::uuid[]);
  RAISE EXCEPTION 'Student was allowed to publish';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $test$;
DO $test$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_activities)<>1 THEN RAISE EXCEPTION 'Unauthorized change'; END IF;
END $test$;
ROLLBACK;
SELECT 'PUBLISH_RPC_ISOLATED_ASSERTIONS_PASSED' AS result;
