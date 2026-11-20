\set ON_ERROR_STOP on
BEGIN;
ALTER TABLE public.cq_v4_student_submissions ADD COLUMN IF NOT EXISTS feedback_released boolean NOT NULL DEFAULT false;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
CREATE TABLE IF NOT EXISTS public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text,questions jsonb);
\ir ../../review/sql-candidates/cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/cq_v4_parent_reread_frozen_snapshot.REVIEW-ONLY.sql
CREATE TABLE public.cq_v4_reread_progress(chapter_uuid uuid NOT NULL,child_user_id uuid NOT NULL,required boolean NOT NULL,completed_at timestamptz,PRIMARY KEY(chapter_uuid,child_user_id));
\ir ../../review/sql-candidates/cq_v4_frozen_reread_atomic.REVIEW-ONLY.sql
DO $$
DECLARE p uuid:='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';s uuid:='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';t uuid:='eeeeeeee-eeee-4eee-eeee-eeeeeeeeeeee';
 c uuid:='cccccccc-cccc-4ccc-cccc-cccccccccccc';d uuid:='cccccccc-cccc-4ccc-cccc-cccccccccccd';a uuid:='dddddddd-dddd-4ddd-dddd-dddddddddddd';v integer;
BEGIN
 INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title) VALUES(c,p,'Frozen six'),(d,p,'Frozen seven');
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES(c,s),(d,t);
 INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id) VALUES(p,s),(p,t);
 INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,chapter_uuid,answer_key,content_hash) VALUES
 (a,p,c,'[0,0,0,0,0,0,0,0,0,0]'::jsonb,'hash-1'),
 ('dddddddd-dddd-4ddd-dddd-ddddddddddde',p,d,'[0,0,0,0,0,0,0,0,0,0]'::jsonb,'hash-2');
 INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,approval_id,approval_hash,questions) VALUES
 (c,now(),a,'hash-1',(SELECT jsonb_agg(jsonb_build_object('kind','mc','options',jsonb_build_array('a','b'))) FROM generate_series(1,10))),
 (d,now(),'dddddddd-dddd-4ddd-dddd-ddddddddddde','hash-2',(SELECT jsonb_agg(jsonb_build_object('kind','mc','options',jsonb_build_array('a','b'))) FROM generate_series(1,10)));
 UPDATE public.cq_v4_approval_requests r SET questions=act.questions
 FROM public.cq_v4_activities act WHERE act.approval_id=r.id;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES
 (c,s,'{"answers":["0","0","0","0","0","0","1","1","1","1"]}'::jsonb),
 (d,t,'{"answers":["0","0","0","0","0","0","0","1","1","1"]}'::jsonb);
 PERFORM set_config('request.jwt.claim.sub',s::text,true);
 IF NOT public.cq_v4_capture_grading_snapshot_internal(s,c) THEN RAISE EXCEPTION 'First capture failed';END IF;
 IF NOT public.cq_v4_record_frozen_reread_internal(s,c) THEN RAISE EXCEPTION 'Frozen six reread record failed';END IF;
 IF (SELECT required FROM public.cq_v4_reread_progress WHERE chapter_uuid=c AND child_user_id=s) IS DISTINCT FROM true THEN RAISE EXCEPTION 'Six of ten should require reread';END IF;
 IF public.cq_v4_capture_grading_snapshot_internal(s,c) THEN RAISE EXCEPTION 'Duplicate capture overwrote row';END IF;
 BEGIN PERFORM public.cq_v4_capture_grading_snapshot_internal(t,d);RAISE EXCEPTION 'Other student capture succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',t::text,true);
 IF NOT public.cq_v4_capture_grading_snapshot_internal(t,d) THEN RAISE EXCEPTION 'Second capture failed';END IF;
 IF NOT public.cq_v4_record_frozen_reread_internal(t,d) THEN RAISE EXCEPTION 'Frozen seven reread record failed';END IF;
 IF (SELECT required FROM public.cq_v4_reread_progress WHERE chapter_uuid=d AND child_user_id=t) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Seven of ten should not require reread';END IF;
 UPDATE public.cq_v4_activities SET approval_hash='republished',questions='[]'::jsonb;
 UPDATE public.cq_v4_approval_requests SET answer_key='[]'::jsonb,content_hash='republished';
 -- Legacy submission with no immutable snapshot must fail closed.
 INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,title) VALUES('cccccccc-cccc-4ccc-cccc-ccccccccccce',p,'Legacy');
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id) VALUES('cccccccc-cccc-4ccc-cccc-ccccccccccce',s);
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES('cccccccc-cccc-4ccc-cccc-ccccccccccce',s,'{"answers":["0"]}'::jsonb);
 PERFORM set_config('request.jwt.claim.sub',p::text,true);
 BEGIN
  PERFORM public.cq_v4_parent_sync_reread_notice(s,'cccccccc-cccc-4ccc-cccc-ccccccccccce');
  RAISE EXCEPTION 'Legacy submission graded without frozen snapshot';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF EXISTS(SELECT 1 FROM public.cq_v4_reread_notices WHERE chapter_uuid='cccccccc-cccc-4ccc-cccc-ccccccccccce')
 THEN RAISE EXCEPTION 'Legacy notice created without snapshot';END IF;
 IF (SELECT correct_mc FROM public.cq_v4_parent_sync_reread_notice(s,c))<>6 THEN RAISE EXCEPTION 'Frozen six grade mismatch';END IF;
 IF (SELECT correct_mc FROM public.cq_v4_parent_sync_reread_notice(t,d))<>7 THEN RAISE EXCEPTION 'Frozen seven grade mismatch';END IF;
 IF (SELECT count(*) FROM public.cq_v4_reread_notices)<>1 THEN RAISE EXCEPTION 'Frozen notice threshold mismatch';END IF;
 IF (SELECT correct_mc FROM public.cq_v4_parent_sync_reread_notice(s,c))<>6 OR (SELECT count(*) FROM public.cq_v4_reread_notices)<>1 THEN RAISE EXCEPTION 'Frozen notice duplicate';END IF;
 PERFORM set_config('request.jwt.claim.sub',s::text,true);
 BEGIN PERFORM public.cq_v4_parent_sync_reread_notice(s,c);RAISE EXCEPTION 'Student graded own snapshot';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub','ffffffff-ffff-4fff-ffff-ffffffffffff',true);
 BEGIN PERFORM public.cq_v4_parent_sync_reread_notice(s,c);RAISE EXCEPTION 'Other parent graded snapshot';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.cq_v4_parent_sync_reread_notice(s,c);RAISE EXCEPTION 'Anonymous graded snapshot';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 SELECT count(*) INTO v FROM public.cq_v4_immutable_grading_snapshots WHERE jsonb_array_length(questions)=10 AND jsonb_array_length(answer_key)=10;
 IF v<>2 THEN RAISE EXCEPTION 'Republish modified frozen snapshot';END IF;
 IF (SELECT count(*) FROM public.cq_v4_immutable_grading_snapshots WHERE student_user_id=s AND submitted_answers->5='"0"'::jsonb AND submitted_answers->6='"1"'::jsonb)<>1
 THEN RAISE EXCEPTION '6/10 frozen answers changed';END IF;
 IF (SELECT count(*) FROM public.cq_v4_immutable_grading_snapshots WHERE student_user_id=t AND submitted_answers->6='"0"'::jsonb AND submitted_answers->7='"1"'::jsonb)<>1
 THEN RAISE EXCEPTION '7/10 frozen answers changed';END IF;
 BEGIN UPDATE public.cq_v4_immutable_grading_snapshots SET content_hash='bad';RAISE EXCEPTION 'Mutation allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN DELETE FROM public.cq_v4_immutable_grading_snapshots;RAISE EXCEPTION 'Deletion allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF has_function_privilege('authenticated','public.cq_v4_capture_grading_snapshot_internal(uuid,uuid)','EXECUTE') THEN
 RAISE EXCEPTION 'Capture helper exposed to authenticated';END IF;
 IF has_table_privilege('authenticated','public.cq_v4_immutable_grading_snapshots','SELECT') THEN
 RAISE EXCEPTION 'Snapshot table exposed to authenticated';END IF;
 IF (SELECT count(*) FROM public.cq_v4_immutable_grading_snapshots)<>2 THEN RAISE EXCEPTION 'Snapshot count wrong';END IF;
 RAISE NOTICE 'IMMUTABLE_SNAPSHOT_ISOLATED_ASSERTIONS_PASSED';
END $$;
ROLLBACK;
