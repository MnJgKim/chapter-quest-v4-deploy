-- CI isolated PostgreSQL only. Fail fast on any regression.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE p uuid:='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'; a uuid:='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb'; b uuid:='cccccccc-cccc-4ccc-cccc-cccccccccccc'; c uuid:='dddddddd-dddd-4ddd-dddd-dddddddddddd';
BEGIN
 INSERT INTO public.cq_v4_pdf_chapters VALUES(c,p,true,'Chapter 1');
 INSERT INTO public.cq_v4_pdf_enrollments VALUES(p,a),(p,b);
 INSERT INTO public.cq_v4_pdf_assignments VALUES(c,a);
 INSERT INTO public.cq_v4_activities VALUES(c,now(),'[{"kind":"mc","options":["a","b"]}]');
 INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at) VALUES(p,a,c,(now() AT TIME ZONE 'Asia/Seoul')::date,now());
END $$;
SELECT set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',false);
DO $$
DECLARE c uuid:='dddddddd-dddd-4ddd-dddd-dddddddddddd';a uuid:='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';b uuid:='cccccccc-cccc-4ccc-cccc-cccccccccccc';
BEGIN
 IF NOT public.cq_v4_can_start_lesson(c,a) THEN RAISE EXCEPTION 'Student today should start'; END IF;
 IF NOT public.cq_v4_can_read_lesson(c,a) THEN RAISE EXCEPTION 'Student today should read'; END IF;
 IF public.cq_v4_can_start_lesson(c,b) OR public.cq_v4_can_read_lesson(c,b) THEN RAISE EXCEPTION 'Cross-student access'; END IF;
END $$;
UPDATE public.cq_v4_lesson_schedule SET lesson_date=(now() AT TIME ZONE 'Asia/Seoul')::date+1;
DO $$
BEGIN IF public.cq_v4_can_start_lesson('dddddddd-dddd-4ddd-dddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN RAISE EXCEPTION 'Future access'; END IF; END $$;
UPDATE public.cq_v4_lesson_schedule SET lesson_date=(now() AT TIME ZONE 'Asia/Seoul')::date-1;
DO $$
BEGIN IF public.cq_v4_can_read_lesson('dddddddd-dddd-4ddd-dddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN RAISE EXCEPTION 'Past incomplete read'; END IF; END $$;
INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers) VALUES('dddddddd-dddd-4ddd-dddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb','{}');
DO $$
BEGIN
 IF public.cq_v4_can_start_lesson('dddddddd-dddd-4ddd-dddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN RAISE EXCEPTION 'Completed cannot restart'; END IF;
 IF NOT public.cq_v4_can_read_lesson('dddddddd-dddd-4ddd-dddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb') THEN RAISE EXCEPTION 'Completed history must read'; END IF;
END $$;
DO $$
BEGIN
 IF NOT has_function_privilege('authenticated','public.cq_v4_can_start_lesson(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Authenticated missing execute'; END IF;
 IF has_function_privilege('anon','public.cq_v4_can_start_lesson(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Anon execute exposed'; END IF;
 IF has_function_privilege('anon','public.cq_v4_can_read_lesson(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Anon read exposed'; END IF;
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid='public.cq_v4_can_start_lesson(uuid,uuid)'::regprocedure) THEN RAISE EXCEPTION 'Missing definer'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='public.cq_v4_is_released(uuid,uuid)'::regprocedure) THEN RAISE EXCEPTION 'Legacy release lost'; END IF;
END $$;
ROLLBACK;
\echo 'ISOLATED_SECURITY_ASSERTIONS_PASSED'
