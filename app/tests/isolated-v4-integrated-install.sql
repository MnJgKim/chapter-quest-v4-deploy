\set ON_ERROR_STOP on
-- Run only in the disposable CI database after the scheduler regression.
DO $$ BEGIN
 IF current_database() <> 'cq_v4_isolated' THEN RAISE EXCEPTION 'Wrong test database'; END IF;
END $$;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS vocabulary jsonb;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS writing_prompt text;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS speaking_prompt text;
CREATE TABLE IF NOT EXISTS public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text,questions jsonb);
CREATE TABLE IF NOT EXISTS public.cq_v4_reread_progress(chapter_uuid uuid NOT NULL,child_user_id uuid NOT NULL,required boolean NOT NULL,completed_at timestamptz,PRIMARY KEY(chapter_uuid,child_user_id));
\ir ../../review/sql-candidates/cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/v4-integrated-optional-answers.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/v4-parent-frozen-result.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/v4-parent-material-preview.REVIEW-ONLY.sql
DO $$ BEGIN
 IF has_function_privilege('anon','public.cq_v4_parent_frozen_result(uuid,uuid)','EXECUTE') OR has_function_privilege('anon','public.cq_v4_parent_material_preview(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Anonymous access'; END IF;
 IF NOT has_function_privilege('authenticated','public.cq_v4_parent_material_preview(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Parent RPC unavailable'; END IF;
 IF has_function_privilege('authenticated','public.cq_v4_record_frozen_reread_internal(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed'; END IF;
END $$;

-- Synthetic fixtures only; never use real student IDs.
BEGIN;
DO $test$
DECLARE p uuid:='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
 s uuid; c uuid; a uuid; n integer; q jsonb; k jsonb; ans jsonb; got jsonb;
BEGIN
 SELECT jsonb_agg(jsonb_build_object('kind','mc','text','Test','options',jsonb_build_array('A','B','C'))) INTO q FROM generate_series(1,7);
 q:=q||'[{"kind":"short","text":"Explain"}]'::jsonb;
 k:='[0,0,0,0,0,0,0,"Sample"]';
 FOREACH n IN ARRAY ARRAY[5,4,0] LOOP
  s:=md5('integration-student-'||n)::uuid;c:=md5('integration-chapter-'||n)::uuid;a:=md5('integration-approval-'||n)::uuid;
  SELECT jsonb_agg(CASE WHEN i<=n THEN '0' ELSE '' END ORDER BY i) INTO ans FROM generate_series(1,8) i;
  INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title) VALUES(c,p,true,'Integration test');
  INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id) VALUES(p,s);
  INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES(c,s);
  INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,chapter_uuid,answer_key,content_hash,questions) VALUES(a,p,c,k,'test-hash',q);
  INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,approval_id,approval_hash,questions) VALUES(c,now(),a,'test-hash',q);
  INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at) VALUES(p,s,c,(now() AT TIME ZONE 'Asia/Seoul')::date+1,now());
  PERFORM set_config('request.jwt.claim.sub',p::text,true);
  IF public.cq_v4_parent_material_preview(c)->'answer_key' IS DISTINCT FROM k THEN RAISE EXCEPTION 'Parent future preview failed'; END IF;
  PERFORM set_config('request.jwt.claim.sub',s::text,true);
  IF public.cq_v4_parent_material_preview(c) IS NOT NULL OR public.cq_v4_parent_frozen_result(c,s) IS NOT NULL THEN RAISE EXCEPTION 'Student answer leak'; END IF;
  IF public.cq_v4_is_released(c,s) THEN RAISE EXCEPTION 'Future release leaked'; END IF;
  PERFORM set_config('request.jwt.claim.sub','ffffffff-ffff-4fff-8fff-ffffffffffff',true);
  IF public.cq_v4_parent_material_preview(c) IS NOT NULL THEN RAISE EXCEPTION 'Other parent preview leak'; END IF;
  UPDATE public.cq_v4_lesson_schedule SET lesson_date=(now() AT TIME ZONE 'Asia/Seoul')::date WHERE chapter_id=c AND student_user_id=s;
  INSERT INTO storage.objects(bucket_id,name) VALUES('cq-v4-speaking',s::text||'/'||c::text||'.webm');
  PERFORM set_config('request.jwt.claim.sub',s::text,true);
  PERFORM public.cq_v4_submit_answers(c,jsonb_build_object('readComplete',true,'answers',ans,'essay','Test','speaking','Test','hasAudio',true));
  IF (SELECT required FROM public.cq_v4_reread_progress WHERE chapter_uuid=c AND child_user_id=s) IS DISTINCT FROM (n<5) THEN RAISE EXCEPTION 'Incorrect reread for %/7',n; END IF;
  PERFORM set_config('request.jwt.claim.sub',p::text,true);
  got:=public.cq_v4_parent_frozen_result(c,s);
  IF got->'submitted_answers' IS DISTINCT FROM ans OR got->'answer_key' IS DISTINCT FROM k THEN RAISE EXCEPTION 'Frozen result mismatch'; END IF;
  UPDATE public.cq_v4_activities SET approval_hash='changed' WHERE chapter_uuid=c;
  IF public.cq_v4_parent_frozen_result(c,s) IS DISTINCT FROM got THEN RAISE EXCEPTION 'Frozen result changed after republish'; END IF;
  PERFORM set_config('request.jwt.claim.sub','ffffffff-ffff-4fff-8fff-ffffffffffff',true);
  IF public.cq_v4_parent_frozen_result(c,s) IS NOT NULL THEN RAISE EXCEPTION 'Other parent frozen result leak'; END IF;
 END LOOP;
END $test$;
CREATE TEMP TABLE integration_saved AS SELECT to_jsonb(s) AS row FROM public.cq_v4_immutable_grading_snapshots s;
COMMIT;

\ir ../../review/sql-candidates/v4-integrated-optional-answers.rollback.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/v4-integrated-optional-answers.REVIEW-ONLY.sql
\echo V4_INTEGRATED_INSTALL_ROLLBACK_ASSERTIONS_PASSED

DO $$ BEGIN
 IF EXISTS (SELECT row FROM integration_saved EXCEPT SELECT to_jsonb(s) FROM public.cq_v4_immutable_grading_snapshots s) THEN RAISE EXCEPTION 'Rollback changed frozen history'; END IF;
END $$;
\echo V4_DETAILED_INTEGRATION_ASSERTIONS_PASSED
