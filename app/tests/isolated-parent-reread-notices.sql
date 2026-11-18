\set ON_ERROR_STOP on
BEGIN;
-- Isolated PostgreSQL bootstrap, synthetic UUIDs only; all fixture writes roll back.
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
CREATE TABLE IF NOT EXISTS public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text);
\ir ../../review/sql-candidates/cq_v4_parent_reread_notices.REVIEW-ONLY.sql
DO $$
DECLARE
 p uuid:='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
 s uuid:='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
 c uuid:='cccccccc-cccc-4ccc-cccc-cccccccccccc';
 a uuid:='dddddddd-dddd-4ddd-dddd-dddddddddddd';
 n integer; v record;
BEGIN
 -- Neither anonymous nor a different parent/student can trigger notice creation.
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.cq_v4_parent_sync_reread_notice(s,c);
 RAISE EXCEPTION 'Anonymous unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',s::text,true);
 BEGIN PERFORM public.cq_v4_parent_sync_reread_notice(s,c);
 RAISE EXCEPTION 'Student unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','eeeeeeee-eeee-4eee-eeee-eeeeeeeeeeee',true);
 BEGIN PERFORM public.cq_v4_parent_sync_reread_notice(s,c);
 RAISE EXCEPTION 'Other parent unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',p::text,true);
 INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title) VALUES(c,p,'Synthetic chapter');
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES(c,s);
 INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id) VALUES(p,s);
 INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,approval_id,approval_hash,questions)
 VALUES(c,now(),a,'hash-1',(SELECT jsonb_agg(jsonb_build_object('kind','mc','options',jsonb_build_array('a','b'))) FROM generate_series(1,10)));
 INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,chapter_uuid,answer_key,content_hash)
 VALUES(a,p,c,'[0,0,0,0,0,0,0,0,0,0]'::jsonb,'hash-1');
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
 VALUES(c,s,'{"answers":["0","0","0","0","0","0","1","1","1","1"]}'::jsonb);
 SELECT * INTO v FROM public.cq_v4_parent_sync_reread_notice(s,c);
 IF v.correct_mc<>6 OR v.total_mc<>10 OR NOT v.needs_reread THEN RAISE EXCEPTION '6/10 grading wrong';END IF;
 SELECT * INTO v FROM public.cq_v4_parent_sync_reread_notice(s,c);
 SELECT count(*) INTO n FROM public.cq_v4_reread_notices;
 IF n<>1 THEN RAISE EXCEPTION 'Idempotent notice count %',n;END IF;
 -- A 70% submission must never generate an additional notice.
 UPDATE public.cq_v4_student_submissions SET answers='{"answers":["0","0","0","0","0","0","0","1","1","1"]}'::jsonb WHERE chapter_uuid=c;
 SELECT * INTO v FROM public.cq_v4_parent_sync_reread_notice(s,c);
 IF v.correct_mc<>7 OR v.needs_reread THEN RAISE EXCEPTION '7/10 boundary wrong';END IF;
 SELECT count(*) INTO n FROM public.cq_v4_reread_notices;
 IF n<>1 THEN RAISE EXCEPTION 'Existing notice unexpectedly changed';END IF;
 -- A changed approval hash must fail closed without new writes.
 UPDATE public.cq_v4_activities SET approval_hash='tampered' WHERE chapter_uuid=c;
 BEGIN PERFORM public.cq_v4_parent_sync_reread_notice(s,c);
 RAISE EXCEPTION 'Mismatched approval hash unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE public.cq_v4_activities SET approval_hash='hash-1' WHERE chapter_uuid=c;
 -- Invalid key fails closed.
 UPDATE public.cq_v4_approval_requests SET answer_key='[9,0,0,0,0,0,0,0,0,0]'::jsonb WHERE id=a;
 BEGIN PERFORM public.cq_v4_parent_sync_reread_notice(s,c);
 RAISE EXCEPTION 'Invalid answer key unexpectedly succeeded';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 UPDATE public.cq_v4_approval_requests SET answer_key='[0,0,0,0,0,0,0,0,0,0]'::jsonb WHERE id=a;
 -- Zero questions: no invented score.
 UPDATE public.cq_v4_activities SET questions='[]'::jsonb WHERE chapter_uuid=c;
 UPDATE public.cq_v4_approval_requests SET answer_key='[]'::jsonb WHERE id=a;
 UPDATE public.cq_v4_student_submissions SET answers='{"answers":[]}'::jsonb WHERE chapter_uuid=c;
 SELECT * INTO v FROM public.cq_v4_parent_sync_reread_notice(s,c);
 IF v.correct_mc<>0 OR v.total_mc<>0 OR v.needs_reread THEN RAISE EXCEPTION 'Zero-question grading wrong';END IF;
 SELECT count(*) INTO n FROM public.cq_v4_reread_notices;
 IF n<>1 THEN RAISE EXCEPTION 'Unexpected notice count after invalid cases';END IF;
END;
$$;
SELECT 'PARENT_REREAD_GRADE_AUTH_IDEMPOTENCY_PASSED' AS result;
ROLLBACK;
