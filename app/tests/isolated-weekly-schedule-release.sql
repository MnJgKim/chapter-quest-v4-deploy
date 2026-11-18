-- Isolated PostgreSQL 16 ONLY. Validate real SECURITY DEFINER schedule RPC with authenticated JWT.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.cq_v4_pdf_chapters VALUES
 ('33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Approved'),
 ('44444444-4444-4444-8444-444444444444','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Unapproved');
INSERT INTO public.cq_v4_pdf_enrollments VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities VALUES
 ('33333333-3333-4333-8333-333333333333',now(),'[{"kind":"mc","options":["A","B"]}]'),
 ('44444444-4444-4444-8444-444444444444',now(),'[{"kind":"mc","options":["A","B"]}]');
INSERT INTO public.cq_v4_pdf_assignments VALUES
 ('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'),
 ('44444444-4444-4444-8444-444444444444','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date) VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333',(now() AT TIME ZONE 'Asia/Seoul')::date),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','44444444-4444-4444-8444-444444444444',(now() AT TIME ZONE 'Asia/Seoul')::date);
INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal)
VALUES ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333',1);
INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,weekdays,effective_from)
VALUES ('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',ARRAY[1,2,3,4,5,6,7],DATE '2020-01-01');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
DO $schedule$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_my_lesson_schedule())<>2 THEN
   RAISE EXCEPTION 'Authorized schedule rows missing'; END IF;
 IF (SELECT count(*) FROM public.cq_v4_my_lesson_schedule()
     WHERE chapter_uuid='33333333-3333-4333-8333-333333333333' AND is_released IS TRUE)<>1 THEN
   RAISE EXCEPTION 'Approved chapter was not released without manual released_at'; END IF;
 IF (SELECT count(*) FROM public.cq_v4_my_lesson_schedule()
     WHERE chapter_uuid='44444444-4444-4444-8444-444444444444' AND is_released IS TRUE)<>0 THEN
   RAISE EXCEPTION 'Unapproved chapter leaked as released'; END IF;
END $schedule$;
INSERT INTO storage.objects(bucket_id,name) VALUES
 ('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/33333333-3333-4333-8333-333333333333.webm');
SELECT chapter_uuid FROM public.cq_v4_submit_answers('33333333-3333-4333-8333-333333333333',
 '{"readComplete":true,"answers":["0"],"essay":"Done","speaking":"Done","hasAudio":true}'::jsonb);
DO $history$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_my_lesson_schedule()
     WHERE chapter_uuid='33333333-3333-4333-8333-333333333333' AND is_released IS TRUE)<>1 THEN
   RAISE EXCEPTION 'Submitted chapter lost historical release'; END IF;
END $history$;
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-cccc-cccccccccccc',true);
DO $isolation$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_my_lesson_schedule())<>0 THEN
   RAISE EXCEPTION 'Cross-student schedule leak'; END IF;
END $isolation$;
ROLLBACK;
\echo 'WEEKLY_SCHEDULE_RELEASE_ASSERTIONS_PASSED'
