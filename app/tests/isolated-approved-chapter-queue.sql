-- Isolated PostgreSQL only; all fixture changes rolled back.
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
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
DO $$
BEGIN
 IF public.cq_v4_next_approved_chapter('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') IS DISTINCT FROM '11111111-1111-4111-8111-111111111111'::uuid THEN
  RAISE EXCEPTION 'Wrong first approved chapter';
 END IF;
 IF public.cq_v4_next_approved_chapter('cccccccc-cccc-4ccc-cccc-cccccccccccc') IS NOT NULL THEN
  RAISE EXCEPTION 'Cross-student queue leaked';
 END IF;
END $$;
SET LOCAL ROLE postgres;
UPDATE public.cq_v4_pdf_chapters SET pdf_ready=false WHERE chapter_id='11111111-1111-4111-8111-111111111111';
SET LOCAL ROLE authenticated;
DO $audit$
BEGIN
 IF public.cq_v4_next_approved_chapter('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') IS NOT NULL THEN
  RAISE EXCEPTION 'Skipped earlier unready approved chapter';
 END IF;
END $audit$;
SET LOCAL ROLE postgres;
UPDATE public.cq_v4_pdf_chapters SET pdf_ready=true WHERE chapter_id='11111111-1111-4111-8111-111111111111';
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
VALUES ('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','{}');
SET LOCAL ROLE authenticated;
DO $$
BEGIN
 IF public.cq_v4_next_approved_chapter('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') IS DISTINCT FROM '22222222-2222-4222-8222-222222222222'::uuid THEN
  RAISE EXCEPTION 'Did not advance to next approved chapter';
 END IF;
END $$;
ROLLBACK;
\echo 'APPROVED_QUEUE_ASSERTIONS_PASSED'
