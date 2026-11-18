-- ISOLATED POSTGRES ONLY. No real students. Roll back every fixture.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.cq_v4_pdf_chapters VALUES
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Chapter 1');
INSERT INTO public.cq_v4_pdf_enrollments VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_pdf_assignments VALUES
 ('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities VALUES
 ('11111111-1111-4111-8111-111111111111',now(),'[]');
INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal) VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111',1);
INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,weekdays,effective_from)
VALUES ('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',ARRAY[1,3,4],DATE '2026-11-23');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
DO $$
BEGIN
 IF public.cq_v4_weekday_approved_candidate('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',DATE '2026-11-23') IS DISTINCT FROM '11111111-1111-4111-8111-111111111111'::uuid THEN
  RAISE EXCEPTION 'Monday approved candidate missing';
 END IF;
 IF public.cq_v4_weekday_approved_candidate('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',DATE '2026-11-24') IS NOT NULL THEN
  RAISE EXCEPTION 'Tuesday improperly opened';
 END IF;
 IF public.cq_v4_weekday_approved_candidate('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',DATE '2026-11-22') IS NOT NULL THEN
  RAISE EXCEPTION 'Opened before effective date';
 END IF;
 IF public.cq_v4_weekday_approved_candidate('cccccccc-cccc-4ccc-cccc-cccccccccccc',DATE '2026-11-23') IS NOT NULL THEN
  RAISE EXCEPTION 'Cross-student candidate leaked';
 END IF;
END $$;
SET LOCAL ROLE postgres;
UPDATE public.cq_v4_student_weekday_policy SET enabled=false WHERE student_user_id='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';
SET LOCAL ROLE authenticated;
DO $$
BEGIN
 IF public.cq_v4_weekday_approved_candidate('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',DATE '2026-11-23') IS NOT NULL THEN
  RAISE EXCEPTION 'Disabled policy still opened';
 END IF;
END $$;
ROLLBACK;
\echo 'WEEKDAY_APPROVED_CANDIDATE_ASSERTIONS_PASSED'
