-- Isolated PostgreSQL only: verify the overlay denies unapproved work but retains history.
\set ON_ERROR_STOP on
BEGIN;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
CREATE TABLE IF NOT EXISTS public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text,questions jsonb);
\ir ../../review/sql-candidates/cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql
CREATE TABLE public.cq_v4_reread_progress(chapter_uuid uuid NOT NULL,child_user_id uuid NOT NULL,required boolean NOT NULL,completed_at timestamptz,PRIMARY KEY(chapter_uuid,child_user_id));
\ir ../../review/sql-candidates/cq_v4_frozen_reread_atomic.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/cq_v4_disable_legacy_reread_trigger.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/cq_v4_submit_with_frozen_snapshot.REVIEW-ONLY.sql
INSERT INTO public.cq_v4_pdf_chapters VALUES
 ('33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Approved'),
 ('44444444-4444-4444-8444-444444444444','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Not approved');
INSERT INTO public.cq_v4_pdf_enrollments VALUES ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_pdf_assignments VALUES
 ('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'),
 ('44444444-4444-4444-8444-444444444444','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities VALUES
 ('33333333-3333-4333-8333-333333333333',now(),'[{"kind":"mc","options":["A","B"]}]'),
 ('44444444-4444-4444-8444-444444444444',now(),'[{"kind":"mc","options":["A","B"]}]');
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date) VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333',(now() AT TIME ZONE 'Asia/Seoul')::date),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','44444444-4444-4444-8444-444444444444',(now() AT TIME ZONE 'Asia/Seoul')::date);
INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal) VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333',1);
INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,weekdays,effective_from)
VALUES ('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',ARRAY[1,2,3,4,5,6,7],DATE '2020-01-01');
INSERT INTO public.cq_v4_approval_requests(id,parent_user_id,chapter_uuid,answer_key,content_hash) VALUES
 ('99999999-9999-4999-8999-999999999999','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','33333333-3333-4333-8333-333333333333','[0]'::jsonb,'frozen-approved'),
 ('99999999-9999-4999-8999-999999999998','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','44444444-4444-4444-8444-444444444444','[0]'::jsonb,'frozen-approved-2');
UPDATE public.cq_v4_activities SET approval_id='99999999-9999-4999-8999-999999999999',approval_hash='frozen-approved' WHERE chapter_uuid='33333333-3333-4333-8333-333333333333';
UPDATE public.cq_v4_activities SET approval_id='99999999-9999-4999-8999-999999999998',approval_hash='frozen-approved-2' WHERE chapter_uuid='44444444-4444-4444-8444-444444444444';
UPDATE public.cq_v4_approval_requests r SET questions=a.questions
FROM public.cq_v4_activities a WHERE a.approval_id=r.id;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
DO $test$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_my_released_chapters())<>1 THEN
   RAISE EXCEPTION 'Unapproved chapter leaked into released list'; END IF;
 IF public.cq_v4_can_read_lesson('44444444-4444-4444-8444-444444444444','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
   RAISE EXCEPTION 'Unapproved chapter leaked through PDF/read predicate'; END IF;
 IF public.cq_v4_can_read_lesson('33333333-3333-4333-8333-333333333333','cccccccc-cccc-4ccc-cccc-cccccccccccc') THEN
   RAISE EXCEPTION 'Cross-student PDF/read predicate bypass'; END IF;
 BEGIN
   PERFORM public.cq_v4_submit_answers('44444444-4444-4444-8444-444444444444',
     '{"readComplete":true,"answers":["0"],"essay":"Test","speaking":"Test","hasAudio":true}'::jsonb);
   RAISE EXCEPTION 'Unapproved chapter submission accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
   INSERT INTO storage.objects(bucket_id,name) VALUES
     ('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/44444444-4444-4444-8444-444444444444.webm');
   RAISE EXCEPTION 'Unapproved chapter recording accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $test$;
INSERT INTO storage.objects(bucket_id,name) VALUES
 ('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/33333333-3333-4333-8333-333333333333.webm');
-- A published legacy chapter with mismatched approval provenance must still
-- accept a valid submission, but must never fabricate a grading snapshot.
RESET ROLE;
UPDATE public.cq_v4_activities SET approval_hash='deliberately-mismatched'
 WHERE chapter_uuid='33333333-3333-4333-8333-333333333333';
SET LOCAL ROLE authenticated;
SELECT chapter_uuid FROM public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333',
 '{"readComplete":true,"answers":["0"],"essay":"Legacy","speaking":"Legacy","hasAudio":true}'::jsonb);
RESET ROLE;
DO $verify_legacy$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.cq_v4_student_submissions WHERE child_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb' AND chapter_uuid='33333333-3333-4333-8333-333333333333')
 OR EXISTS(SELECT 1 FROM public.cq_v4_immutable_grading_snapshots WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb' AND chapter_uuid='33333333-3333-4333-8333-333333333333')
 OR EXISTS(SELECT 1 FROM public.cq_v4_reread_progress WHERE child_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb' AND chapter_uuid='33333333-3333-4333-8333-333333333333')
 THEN RAISE EXCEPTION 'Legacy submission must persist without fabricated snapshot or reread';END IF;
END $verify_legacy$;
UPDATE public.cq_v4_activities SET approval_hash='frozen-approved'
 WHERE chapter_uuid='33333333-3333-4333-8333-333333333333';
SET LOCAL ROLE authenticated;
SELECT chapter_uuid FROM public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333',
 '{"readComplete":true,"answers":["0"],"essay":"Test","speaking":"Test","hasAudio":true}'::jsonb);
DO $test$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_my_released_chapters())<>1 THEN
   RAISE EXCEPTION 'Historical submitted chapter not readable'; END IF;
 IF NOT public.cq_v4_can_read_lesson('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
   RAISE EXCEPTION 'Historical read denied'; END IF;
END $test$;
-- After submission, new recording writes must be blocked while PDF history stays readable.
DO $post_submit$
BEGIN
 BEGIN
   INSERT INTO storage.objects(bucket_id,name) VALUES
     ('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/33333333-3333-4333-8333-333333333333.ogg');
   RAISE EXCEPTION 'Recording upload allowed after immutable submission';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 IF NOT public.cq_v4_can_read_lesson('33333333-3333-4333-8333-333333333333',
     'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
   RAISE EXCEPTION 'Historical PDF reading denied after submission'; END IF;
END $post_submit$;
-- A different authenticated student cannot see the chapter list or submitted PDF.
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-cccc-cccccccccccc',true);
DO $other_student$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_my_released_chapters()) <> 0 THEN
   RAISE EXCEPTION 'Cross-student chapter listing exposed'; END IF;
 IF public.cq_v4_can_read_lesson('33333333-3333-4333-8333-333333333333',
     'cccccccc-cccc-4ccc-cccc-cccccccccccc') THEN
   RAISE EXCEPTION 'Cross-student historical PDF reading exposed'; END IF;
 BEGIN
   PERFORM public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333',
     '{"readComplete":true,"answers":["0"],"essay":"Other student","speaking":"Other","hasAudio":true}'::jsonb);
   RAISE EXCEPTION 'Cross-student submission accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $other_student$;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
-- A second submission must be idempotent: no additional row or mutation.
SELECT chapter_uuid FROM public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333',
 '{"readComplete":true,"answers":["1"],"essay":"Attempted overwrite","speaking":"Changed","hasAudio":true}'::jsonb);
RESET ROLE;
-- Inspect the stored immutable row as the isolated test owner, not as a student.
DO $idempotency$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_student_submissions
     WHERE chapter_uuid='33333333-3333-4333-8333-333333333333'::uuid
       AND child_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'::uuid) <> 1 THEN
   RAISE EXCEPTION 'Duplicate immutable submission row'; END IF;
 IF (SELECT answers->>'essay' FROM public.cq_v4_student_submissions
     WHERE chapter_uuid='33333333-3333-4333-8333-333333333333'::uuid
       AND child_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'::uuid) <> 'Test' THEN
   RAISE EXCEPTION 'Submitted essay was overwritten'; END IF;
END $idempotency$;
DO $snapshot_checks$
BEGIN
 IF (SELECT required FROM public.cq_v4_reread_progress WHERE chapter_uuid='33333333-3333-4333-8333-333333333333'::uuid AND child_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'::uuid) IS DISTINCT FROM false THEN RAISE EXCEPTION 'Correct one-question submission must not require reread';END IF;
 IF (SELECT count(*) FROM public.cq_v4_immutable_grading_snapshots WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'::uuid AND chapter_uuid='33333333-3333-4333-8333-333333333333'::uuid)<>1 THEN RAISE EXCEPTION 'Atomic submission did not capture snapshot';END IF;
 IF (SELECT count(*) FROM public.cq_v4_immutable_grading_snapshots)<>1 THEN RAISE EXCEPTION 'Unexpected extra snapshot';END IF;
END $snapshot_checks$;
ROLLBACK;
\echo 'ATOMIC_SUBMISSION_SNAPSHOT_ASSERTIONS_PASSED'
