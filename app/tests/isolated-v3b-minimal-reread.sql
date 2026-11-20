-- Disposable PostgreSQL 16 only. Exercise the exact live-V3B-compatible RPC overlay.
\set ON_ERROR_STOP on
BEGIN;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
CREATE TABLE public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text,questions jsonb);
\ir ../../review/sql-candidates/cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql
ALTER TABLE public.cq_v4_student_submissions ADD COLUMN feedback text, ADD COLUMN feedback_released boolean DEFAULT false;
\ir ../../review/sql-candidates/cq_v4_reread_parent_gate_v3b.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/cq_v4_frozen_reread_atomic.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/cq_v4_disable_legacy_reread_trigger.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/cq_v4_submit_v3b_minimal_reread.REVIEW-ONLY.sql
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title) VALUES
('33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Verified'),
('44444444-4444-4444-8444-444444444444','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Legacy');
INSERT INTO public.cq_v4_pdf_enrollments VALUES('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_pdf_assignments VALUES
('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'),
('44444444-4444-4444-8444-444444444444','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,questions,approval_id,approval_hash) VALUES
('33333333-3333-4333-8333-333333333333',now(),'[{"kind":"mc","options":["A","B"]}]','99999999-9999-4999-8999-999999999999','valid-hash'),
('44444444-4444-4444-8444-444444444444',now(),'[{"kind":"mc","options":["A","B"]}]',NULL,NULL);
INSERT INTO public.cq_v4_approval_requests VALUES
('99999999-9999-4999-8999-999999999999','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','33333333-3333-4333-8333-333333333333','[0]','valid-hash','[{"kind":"mc","options":["A","B"]}]');
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at) VALUES
('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333',CURRENT_DATE,now()),
('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','44444444-4444-4444-8444-444444444444',CURRENT_DATE,now());
INSERT INTO storage.objects(bucket_id,name) VALUES
('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/33333333-3333-4333-8333-333333333333.webm'),
('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/44444444-4444-4444-8444-444444444444.webm');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
SELECT public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333','{"readComplete":true,"answers":["1"],"essay":"Verified","speaking":"Verified","hasAudio":true}');
SELECT public.cq_v4_submit_answers('44444444-4444-4444-8444-444444444444','{"readComplete":true,"answers":["0"],"essay":"Legacy","speaking":"Legacy","hasAudio":true}');
SELECT public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333','{"readComplete":true,"answers":["0"],"essay":"Tampered","speaking":"Tampered","hasAudio":true}');
-- Parent cannot write feedback before required reread. Student cannot impersonate parent.
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true);
DO $blocked_feedback$
BEGIN
 BEGIN
  PERFORM public.cq_v4_release_feedback('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333','Feedback',true);
  RAISE EXCEPTION 'Parent feedback allowed before reread';
 EXCEPTION WHEN check_violation THEN NULL;
 END;
END $blocked_feedback$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-cccc-cccccccccccc',true);
DO $cross_student$
BEGIN
 BEGIN
  PERFORM public.cq_v4_complete_reread('33333333-3333-4333-8333-333333333333');
  RAISE EXCEPTION 'Cross-student reread completion accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $cross_student$;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
SELECT public.cq_v4_complete_reread('33333333-3333-4333-8333-333333333333');
DO $student_cannot_feedback$
BEGIN
 BEGIN
  PERFORM public.cq_v4_release_feedback('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333','Unauthorized',true);
  RAISE EXCEPTION 'Student wrote parent feedback';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $student_cannot_feedback$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true);
SELECT public.cq_v4_release_feedback('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333','Approved feedback',true);
RESET ROLE;
DO $assert$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_student_submissions)<>2 THEN RAISE EXCEPTION 'Duplicate or lost submissions';END IF;
 IF (SELECT count(*) FROM public.cq_v4_immutable_grading_snapshots)<>1 THEN RAISE EXCEPTION 'Verified-only snapshot violation';END IF;
 IF (SELECT count(*) FROM public.cq_v4_reread_progress WHERE required)<>1 THEN RAISE EXCEPTION 'Wrong reread decision';END IF;
 IF (SELECT answers->>'essay' FROM public.cq_v4_student_submissions WHERE chapter_uuid='33333333-3333-4333-8333-333333333333')<>'Verified' THEN RAISE EXCEPTION 'Immutable essay overwritten';END IF;
 IF EXISTS(SELECT 1 FROM public.cq_v4_immutable_grading_snapshots WHERE chapter_uuid='44444444-4444-4444-8444-444444444444') THEN RAISE EXCEPTION 'Legacy answer key fabricated';END IF;
 IF (SELECT feedback FROM public.cq_v4_student_submissions WHERE chapter_uuid='33333333-3333-4333-8333-333333333333')<>'Approved feedback' THEN RAISE EXCEPTION 'Parent feedback not released after reread';END IF;
END $assert$;
ROLLBACK;
\echo 'V3B_MINIMAL_REREAD_ASSERTIONS_PASSED'
