\set ON_ERROR_STOP on
CREATE SCHEMA auth;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('cq.test_uid',true),'')::uuid $$;
CREATE FUNCTION public.cq_is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT auth.uid()='11111111-1111-1111-1111-111111111111'::uuid $$;
CREATE TABLE public.cq_v4_pdf_chapters(chapter_id uuid PRIMARY KEY,parent_user_id uuid NOT NULL);
CREATE TABLE public.cq_v4_pdf_assignments(chapter_id uuid,student_user_id uuid);
CREATE TABLE public.cq_v4_pdf_enrollments(parent_user_id uuid,student_user_id uuid);
CREATE TABLE public.cq_v4_approval_requests(id uuid PRIMARY KEY,chapter_uuid uuid,content_hash text,questions jsonb,answer_key jsonb,parent_user_id uuid);
CREATE TABLE public.cq_v4_activities(chapter_uuid uuid PRIMARY KEY,approval_id uuid,approval_hash text,questions jsonb,published_at timestamptz);
CREATE TABLE public.cq_v4_student_submissions(chapter_uuid uuid,child_user_id uuid,answers jsonb,submitted_at timestamptz DEFAULT now(),feedback text DEFAULT '',feedback_released boolean DEFAULT false,PRIMARY KEY(chapter_uuid,child_user_id));
INSERT INTO public.cq_v4_pdf_chapters VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111');
INSERT INTO public.cq_v4_pdf_assignments VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222');
INSERT INTO public.cq_v4_pdf_enrollments VALUES ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
INSERT INTO public.cq_v4_approval_requests VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','valid', (SELECT jsonb_agg(jsonb_build_object('kind','mc','options',jsonb_build_array('A','B'))) FROM generate_series(1,10)), '[1,1,1,1,1,1,1,1,1,1]'::jsonb,'11111111-1111-1111-1111-111111111111');
INSERT INTO public.cq_v4_activities SELECT chapter_uuid,id,content_hash,questions,now() FROM public.cq_v4_approval_requests;
\ir ../sql/development-reread-publish-validation-not-for-production.sql
SELECT set_config('cq.test_uid','11111111-1111-1111-1111-111111111111',false);
DO $reread_validation$
BEGIN
 IF public.cq_v4_assert_reread_publishable('cccccccc-cccc-cccc-cccc-cccccccccccc') IS DISTINCT FROM true THEN RAISE EXCEPTION 'valid approved key rejected'; END IF;
 PERFORM set_config('cq.test_uid','22222222-2222-2222-2222-222222222222',true);
 BEGIN
  PERFORM public.cq_v4_assert_reread_publishable('cccccccc-cccc-cccc-cccc-cccccccccccc');
  RAISE EXCEPTION 'student unexpectedly validated parent approval';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 PERFORM set_config('cq.test_uid','11111111-1111-1111-1111-111111111111',true);
 UPDATE public.cq_v4_approval_requests SET answer_key='[1]'::jsonb WHERE id='cccccccc-cccc-cccc-cccc-cccccccccccc';
 BEGIN
  PERFORM public.cq_v4_assert_reread_publishable('cccccccc-cccc-cccc-cccc-cccccccccccc');
  RAISE EXCEPTION 'missing answer key not rejected';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 UPDATE public.cq_v4_approval_requests SET answer_key='[9,1,1,1,1,1,1,1,1,1]'::jsonb WHERE id='cccccccc-cccc-cccc-cccc-cccccccccccc';
 BEGIN
  PERFORM public.cq_v4_assert_reread_publishable('cccccccc-cccc-cccc-cccc-cccccccccccc');
  RAISE EXCEPTION 'out-of-range answer key not rejected';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 UPDATE public.cq_v4_approval_requests SET answer_key='[1,1,1,1,1,1,1,1,1,1]'::jsonb WHERE id='cccccccc-cccc-cccc-cccc-cccccccccccc';
 RAISE NOTICE 'REREAD_PUBLISH_POSTGRES_ASSERTIONS_PASSED';
END $reread_validation$;
\ir ../sql/development-reread-progress-not-for-production.sql
SELECT set_config('cq.test_uid','22222222-2222-2222-2222-222222222222',false);
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','{"answers":["1","1","1","1","1","1","0","0","0","0"]}'::jsonb);
DO $$ BEGIN
 IF (SELECT required FROM public.cq_v4_reread_progress) IS DISTINCT FROM true THEN RAISE EXCEPTION '60 percent must require reread'; END IF;
 IF (SELECT count(*) FROM public.cq_v4_my_reread_status('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'))<>1 THEN RAISE EXCEPTION 'student status missing'; END IF;
 PERFORM set_config('cq.test_uid','33333333-3333-3333-3333-333333333333',true);
 IF EXISTS (SELECT 1 FROM public.cq_v4_my_reread_status('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')) THEN RAISE EXCEPTION 'cross student status leak'; END IF;
 BEGIN PERFORM public.cq_v4_complete_reread('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'); RAISE EXCEPTION 'cross student completion accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('cq.test_uid','22222222-2222-2222-2222-222222222222',true);
 PERFORM public.cq_v4_complete_reread('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
 IF NOT (SELECT completed_at IS NOT NULL FROM public.cq_v4_reread_progress) THEN RAISE EXCEPTION 'completion not persisted'; END IF;
 DELETE FROM public.cq_v4_reread_progress; DELETE FROM public.cq_v4_student_submissions;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','{"answers":["1","1","1","1","1","1","1","0","0","0"]}'::jsonb);
 IF (SELECT required FROM public.cq_v4_reread_progress) IS DISTINCT FROM false THEN RAISE EXCEPTION '70 percent must not require reread'; END IF;
 DELETE FROM public.cq_v4_reread_progress; DELETE FROM public.cq_v4_student_submissions;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','{"answers":["1","1","1","1","1","1","1","1","0","0"]}'::jsonb);
 IF (SELECT required FROM public.cq_v4_reread_progress) IS DISTINCT FROM false THEN RAISE EXCEPTION '80 percent must not require reread'; END IF;
 BEGIN
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','{"answers":["1"]}'::jsonb);
 RAISE EXCEPTION 'duplicate submission accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 DELETE FROM public.cq_v4_reread_progress; DELETE FROM public.cq_v4_student_submissions;
 UPDATE public.cq_v4_approval_requests SET answer_key='[1]'::jsonb WHERE id='cccccccc-cccc-cccc-cccc-cccccccccccc';
 BEGIN
  INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','{"answers":["1","1","1","1","1","1","0","0","0","0"]}'::jsonb);
  RAISE EXCEPTION 'invalid key unexpectedly accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 IF EXISTS (SELECT 1 FROM public.cq_v4_student_submissions) OR EXISTS (SELECT 1 FROM public.cq_v4_reread_progress) THEN RAISE EXCEPTION 'failed score left partial submission'; END IF;
 UPDATE public.cq_v4_approval_requests SET answer_key='[1,1,1,1,1,1,1,1,1,1]'::jsonb WHERE id='cccccccc-cccc-cccc-cccc-cccccccccccc';
 RAISE NOTICE 'REREAD_STUDENT_POSTGRES_ASSERTIONS_PASSED';
END $$;
