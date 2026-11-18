-- CI ISOLATED ONLY. Exercise policies as authenticated, not postgres superuser.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.cq_v4_pdf_chapters VALUES('dddddddd-dddd-4ddd-dddd-dddddddddddd','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',true,'Chapter 1');
INSERT INTO public.cq_v4_pdf_enrollments VALUES('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'),('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','cccccccc-cccc-4ccc-cccc-cccccccccccc');
INSERT INTO public.cq_v4_pdf_assignments VALUES('dddddddd-dddd-4ddd-dddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb');
INSERT INTO public.cq_v4_activities VALUES('dddddddd-dddd-4ddd-dddd-dddddddddddd',now(),'[{"kind":"mc","options":["a","b"]}]');
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at) VALUES('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','dddddddd-dddd-4ddd-dddd-dddddddddddd',(now() AT TIME ZONE 'Asia/Seoul')::date,now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',true);
DO $$
DECLARE c uuid:='dddddddd-dddd-4ddd-dddd-dddddddddddd'; a uuid:='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'; b uuid:='cccccccc-cccc-4ccc-cccc-cccccccccccc';
BEGIN
 IF NOT public.cq_v4_can_start_lesson(c,a) THEN RAISE EXCEPTION 'Student A cannot start'; END IF;
 IF public.cq_v4_can_start_lesson(c,b) THEN RAISE EXCEPTION 'Student A can impersonate B'; END IF;
END $$;
INSERT INTO storage.objects(bucket_id,name) VALUES('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/dddddddd-dddd-4ddd-dddd-dddddddddddd.webm');
DO $$
BEGIN
 BEGIN
  INSERT INTO storage.objects(bucket_id,name) VALUES('cq-v4-speaking','cccccccc-cccc-4ccc-cccc-cccccccccccc/dddddddd-dddd-4ddd-dddd-dddddddddddd.webm');
  RAISE EXCEPTION 'Cross-student recording insert was allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
  INSERT INTO storage.objects(bucket_id,name) VALUES('cq-v4-speaking','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/not-a-uuid.webm');
  RAISE EXCEPTION 'Malformed recording path was allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
  UPDATE storage.objects SET name='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb/eeeeeeee-eeee-4eee-eeee-eeeeeeeeeeee.webm' WHERE bucket_id='cq-v4-speaking';
  IF FOUND THEN RAISE EXCEPTION 'Unauthorized recording UPDATE was allowed'; END IF;
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $$;
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-cccc-cccccccccccc',true);
DO $$
BEGIN
 IF public.cq_v4_can_read_lesson('dddddddd-dddd-4ddd-dddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN RAISE EXCEPTION 'Student B accessed A'; END IF;
END $$;
ROLLBACK;
\echo 'AUTHENTICATED_RLS_ASSERTIONS_PASSED'
