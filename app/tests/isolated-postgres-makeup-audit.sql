-- ISOLATED CI ONLY: test parent-approved makeup audit and immutable completed lessons.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.cq_v4_pdf_chapters VALUES('dddddddd-dddd-4ddd-dddd-dddddddddddd','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Chapter 1');
INSERT INTO public.cq_v4_pdf_enrollments VALUES('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities VALUES('dddddddd-dddd-4ddd-dddd-dddddddddddd',now(),'[]');
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at)
VALUES('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','dddddddd-dddd-4ddd-dddd-dddddddddddd',(now() AT TIME ZONE 'Asia/Seoul')::date-1,now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true);
SELECT public.cq_v4_parent_schedule_lesson('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','dddddddd-dddd-4ddd-dddd-dddddddddddd',(now() AT TIME ZONE 'Asia/Seoul')::date);
SET LOCAL ROLE postgres;
DO $
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_makeup_approvals)!=1 THEN RAISE EXCEPTION 'Missing makeup audit'; END IF;
 IF (SELECT lesson_date FROM public.cq_v4_lesson_schedule)!=(now() AT TIME ZONE 'Asia/Seoul')::date THEN RAISE EXCEPTION 'Makeup date unchanged'; END IF;
END $$;
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES('dddddddd-dddd-4ddd-dddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','{}');
SET LOCAL ROLE authenticated;
DO $
BEGIN
 BEGIN
  PERFORM public.cq_v4_parent_schedule_lesson('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','dddddddd-dddd-4ddd-dddd-dddddddddddd',(now() AT TIME ZONE 'Asia/Seoul')::date+1);
  RAISE EXCEPTION 'Completed schedule was changed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;

END $$;
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-cccc-cccccccccccc',true);
DO $$
BEGIN
 BEGIN
  PERFORM public.cq_v4_parent_schedule_lesson('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','dddddddd-dddd-4ddd-dddd-dddddddddddd',(now() AT TIME ZONE 'Asia/Seoul')::date+1);
  RAISE EXCEPTION 'Unauthorized parent changed schedule';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $$;
ROLLBACK;
\echo 'MAKEUP_AUDIT_ASSERTIONS_PASSED'
