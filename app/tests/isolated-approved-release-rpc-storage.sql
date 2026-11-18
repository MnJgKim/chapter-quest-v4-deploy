-- Isolated PostgreSQL only: verify the overlay denies unapproved work but retains history.
\set ON_ERROR_STOP on
BEGIN;
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
SELECT chapter_uuid FROM public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333',
 '{"readComplete":true,"answers":["0"],"essay":"Test","speaking":"Test","hasAudio":true}'::jsonb);
DO $test$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_my_released_chapters())<>1 THEN
   RAISE EXCEPTION 'Historical submitted chapter not readable'; END IF;
 IF NOT public.cq_v4_can_read_lesson('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
   RAISE EXCEPTION 'Historical read denied'; END IF;
END $test$;
-- A second submission must be idempotent: no additional row or mutation.
SELECT chapter_uuid FROM public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333',
 '{"readComplete":true,"answers":["1"],"essay":"Attempted overwrite","speaking":"Changed","hasAudio":true}'::jsonb);
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
ROLLBACK;
\echo 'APPROVED_RELEASE_RPC_STORAGE_ASSERTIONS_PASSED'
