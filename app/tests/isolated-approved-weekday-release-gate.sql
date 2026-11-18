-- ISOLATED POSTGRES ONLY. Uses server clock and rolls back all fixtures.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.cq_v4_pdf_chapters VALUES
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Chapter 1'),
 ('22222222-2222-4222-8222-222222222222','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Chapter 2');
INSERT INTO public.cq_v4_pdf_enrollments VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_pdf_assignments VALUES
 ('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities VALUES
 ('11111111-1111-4111-8111-111111111111',now(),'[]'),
 ('22222222-2222-4222-8222-222222222222',now(),'[]');
INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal) VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111',1),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222',2);
INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,weekdays,effective_from)
VALUES ('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',ARRAY[1,2,3,4,5,6,7],DATE '2020-01-01');
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111',(now() AT TIME ZONE 'Asia/Seoul')::date),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222',(now() AT TIME ZONE 'Asia/Seoul')::date);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
DO $$
BEGIN
 IF NOT public.cq_v4_can_start_approved_lesson('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
  RAISE EXCEPTION 'Approved first chapter denied';
 END IF;
 IF public.cq_v4_can_start_approved_lesson('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
  RAISE EXCEPTION 'Second chapter opened before first completion';
 END IF;
 IF public.cq_v4_can_start_approved_lesson('11111111-1111-4111-8111-111111111111','cccccccc-cccc-4ccc-cccc-cccccccccccc') THEN
  RAISE EXCEPTION 'Cross-student access';
 END IF;
END $$;
SET LOCAL ROLE postgres;
UPDATE public.cq_v4_student_weekday_policy
SET weekdays=ARRAY[EXTRACT(ISODOW FROM (now() AT TIME ZONE 'Asia/Seoul')::date + 1)::integer]
WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
SET LOCAL ROLE authenticated;
DO $
BEGIN
 IF public.cq_v4_can_start_approved_lesson('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
  RAISE EXCEPTION 'Non-weekday opened without approved makeup';
 END IF;
END $;
SET LOCAL ROLE postgres;
INSERT INTO public.cq_v4_makeup_approvals(parent_user_id,student_user_id,chapter_id,original_lesson_date,approved_lesson_date)
VALUES ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111',
 (now() AT TIME ZONE 'Asia/Seoul')::date - 1,(now() AT TIME ZONE 'Asia/Seoul')::date);
SET LOCAL ROLE authenticated;
DO $
BEGIN
 IF NOT public.cq_v4_can_start_approved_lesson('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
  RAISE EXCEPTION 'Audited makeup not honored';
 END IF;
END $;
SET LOCAL ROLE postgres;
DELETE FROM public.cq_v4_makeup_approvals WHERE chapter_id='11111111-1111-4111-8111-111111111111';
UPDATE public.cq_v4_student_weekday_policy SET weekdays=ARRAY[1,2,3,4,5,6,7]
WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
VALUES ('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','{}');
SET LOCAL ROLE authenticated;
DO $
BEGIN
 IF public.cq_v4_can_start_approved_lesson('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
  RAISE EXCEPTION 'Submitted chapter still open for new work';
 END IF;
 IF public.cq_v4_can_start_approved_lesson('22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
  RAISE EXCEPTION 'Second chapter opened on same Seoul learning day';
 END IF;
END $;
SET LOCAL ROLE postgres;
UPDATE public.cq_v4_student_weekday_policy SET enabled=false WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
SET LOCAL ROLE authenticated;
DO $$
BEGIN
 IF public.cq_v4_can_start_approved_lesson('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN
  RAISE EXCEPTION 'Disabled weekday policy opened chapter';
 END IF;
END $$;
ROLLBACK;
\echo 'APPROVED_WEEKDAY_RELEASE_GATE_ASSERTIONS_PASSED'
