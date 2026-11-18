-- Isolated PostgreSQL 16 only. All fixture writes rolled back.
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
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
DO $$
BEGIN
 IF public.cq_v4_ensure_today_approved_lesson() IS DISTINCT FROM '11111111-1111-4111-8111-111111111111'::uuid THEN
  RAISE EXCEPTION 'First daily schedule not created';
 END IF;
 IF public.cq_v4_ensure_today_approved_lesson() IS NOT NULL THEN
  RAISE EXCEPTION 'Duplicate daily schedule created';
 END IF;
END $$;
SET LOCAL ROLE postgres;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_lesson_schedule WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb')<>1 THEN
  RAISE EXCEPTION 'Unexpected schedule count';
 END IF;
END $$;
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
VALUES ('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','{}');
SET LOCAL ROLE authenticated;
DO $$
BEGIN
 IF public.cq_v4_ensure_today_approved_lesson() IS NOT NULL THEN
  RAISE EXCEPTION 'Same-day second chapter was scheduled after completion';
 END IF;
END $$;
-- Existing parent schedule must not be overwritten even after chapter 1 completion.
SET LOCAL ROLE postgres;
DELETE FROM public.cq_v4_lesson_schedule
 WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
VALUES ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',
 '22222222-2222-4222-8222-222222222222',(now() AT TIME ZONE 'Asia/Seoul')::date + 3);
SET LOCAL ROLE authenticated;
DO $
BEGIN
 IF public.cq_v4_ensure_today_approved_lesson() IS NOT NULL THEN
  RAISE EXCEPTION 'Existing parent schedule overwritten';
 END IF;
END $;
SET LOCAL ROLE postgres;
DO $
BEGIN
 IF (SELECT lesson_date FROM public.cq_v4_lesson_schedule
     WHERE chapter_id='22222222-2222-4222-8222-222222222222')
    IS DISTINCT FROM (now() AT TIME ZONE 'Asia/Seoul')::date+3 THEN
  RAISE EXCEPTION 'Parent schedule changed';
 END IF;
END $;
ROLLBACK;
\echo 'ATOMIC_WEEKDAY_SCHEDULER_ASSERTIONS_PASSED'
