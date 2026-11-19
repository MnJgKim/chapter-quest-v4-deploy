-- Fresh local PostgreSQL only. All lesson data below is synthetic.
\set ON_ERROR_STOP on
\ir ../../app/tests/isolated-postgres-bootstrap.sql
ALTER TABLE public.cq_v4_pdf_chapters ADD COLUMN pdf_verified_at timestamptz, ADD COLUMN storage_path text;
ALTER TABLE public.cq_v4_activities ADD COLUMN vocabulary jsonb, ADD COLUMN writing_prompt text,
 ADD COLUMN speaking_prompt text, ADD COLUMN approval_id uuid, ADD COLUMN approval_hash text;
CREATE TABLE public.cq_v4_approval_requests (
 id uuid PRIMARY KEY, parent_user_id uuid NOT NULL, chapter_uuid uuid NOT NULL,
 book_local_id text NOT NULL, source_text text, content_hash text, questions jsonb,
 answer_key jsonb, vocabulary jsonb, writing_prompt text, speaking_prompt text
);
\ir ../../app/sql/student-weekday-policy-v1.REVIEW-ONLY.sql
\ir ../../app/sql/approved-chapter-queue-v1.REVIEW-ONLY.sql
\ir ../../app/sql/student-auto-release-existing-schedule.REVIEW-ONLY.sql
\ir ../../app/sql/recurring-approved-publication.REVIEW-ONLY.sql
\ir ../../app/server-review/release-auth-candidate.sql

\set parent 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
\set a '10000000-0000-4000-8000-000000000081'
\set b '10000000-0000-4000-8000-000000000082'
\set c '10000000-0000-4000-8000-000000000083'
\set first '20000000-0000-4000-8000-000000000083'
\set second '20000000-0000-4000-8000-000000000082'
\set third '20000000-0000-4000-8000-000000000081'
INSERT INTO public.cq_v4_pdf_enrollments VALUES (:'parent',:'a'),(:'parent',:'b'),(:'parent',:'c');
\set seowoo_student :a
\set seowoo_parent :parent
\set seojin_student :b
\set seojin_parent :parent
\set siwoo_student :c
\set siwoo_parent :parent
\ir ../../app/sql/recurring-weekday-config.REVIEW-ONLY.sql
BEGIN;
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title,pdf_verified_at,storage_path)
SELECT id,:'parent',true,title,'2026-11-20',title
FROM (VALUES (:'first'::uuid,'First'),(:'second'::uuid,'Second'),(:'third'::uuid,'Next book')) f(id,title);
INSERT INTO public.cq_v4_approval_requests
SELECT chapter_id,parent_user_id,chapter_id,CASE WHEN title='Next book' THEN 'book2' ELSE 'book1' END,
       'Separate source','hash-'||title,'[{"kind":"short","text":"Synthetic question"}]',
       '["Synthetic answer"]','[{"word":"test","meaning":"fixture"}]','Write','Speak'
FROM public.cq_v4_pdf_chapters;
SELECT set_config('request.jwt.claim.sub', :'parent', true);
SET LOCAL ROLE authenticated;
SELECT public.cq_v4_parent_enqueue_approved(:'first',ARRAY[:'a',:'b',:'c']::uuid[],1);
SELECT public.cq_v4_parent_enqueue_approved(:'first',ARRAY[:'a',:'b']::uuid[],1);
DO $$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_parent_recurring_status() WHERE state='ready' AND NOT published) <> 3
 THEN RAISE EXCEPTION 'Parent cannot see approval readiness'; END IF;
 BEGIN
  PERFORM public.cq_v4_parent_enqueue_approved('20000000-0000-4000-8000-000000000082',
    ARRAY['10000000-0000-4000-8000-000000000081']::uuid[],3);
  RAISE EXCEPTION 'Skipped chapter was accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 BEGIN
  PERFORM public.cq_v4_parent_enqueue_approved('20000000-0000-4000-8000-000000000081',
    ARRAY['10000000-0000-4000-8000-000000000081']::uuid[],1);
  RAISE EXCEPTION 'Started another book before the current book end was marked';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
END $$;
SELECT public.cq_v4_parent_enqueue_approved(:'second',ARRAY[:'a',:'b']::uuid[],2,'First book',true);
SELECT public.cq_v4_parent_enqueue_approved(:'third',ARRAY[:'a',:'b']::uuid[],1,'Next book');
DO $$
BEGIN
 IF public.cq_v4_parent_withdraw_recurring('10000000-0000-4000-8000-000000000081','20000000-0000-4000-8000-000000000083')
 THEN RAISE EXCEPTION 'Removing a non-tail chapter must not skip the sequence'; END IF;
 IF NOT public.cq_v4_parent_withdraw_recurring('10000000-0000-4000-8000-000000000081','20000000-0000-4000-8000-000000000081')
 THEN RAISE EXCEPTION 'Could not withdraw an unstarted tail'; END IF;
END $$;
SELECT public.cq_v4_parent_enqueue_approved(:'third',ARRAY[:'a']::uuid[],1,'Next book');
RESET ROLE;
UPDATE public.cq_v4_approved_chapter_queue SET approved_at='2026-11-20';

CREATE FUNCTION pg_temp.expect_release(student uuid, instant timestamptz, expected uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual uuid;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',student::text,true);
 actual:=public.cq_v4_release_recurring_at(instant);
 IF actual IS DISTINCT FROM expected THEN
   RAISE EXCEPTION 'At %, expected %, actual %',instant,expected,actual;
 END IF;
END;
$$;
SELECT pg_temp.expect_release(:'a','2026-11-22 23:59:59.999999+09',NULL);
SELECT pg_temp.expect_release(:'a','2026-11-23 00:00+09',:'first');
SELECT pg_temp.expect_release(:'a','2026-11-23 00:01+09',NULL);
SELECT pg_temp.expect_release(:'b','2026-11-23 23:59:59.999999+09',NULL);
SELECT pg_temp.expect_release(:'b','2026-11-24 00:00+09',:'first');
SELECT pg_temp.expect_release(:'c','2026-11-24 00:00+09',NULL);

INSERT INTO public.cq_v4_student_submissions VALUES
 (:'first',:'a','{"saved":true}','2026-11-23 08:00+09'),
 (:'first',:'b','{"saved":true}','2026-11-24 08:00+09');
SELECT pg_temp.expect_release(:'a','2026-11-24 00:00+09',NULL);
UPDATE public.cq_v4_pdf_chapters SET pdf_ready=false WHERE chapter_id=:'second';
SELECT pg_temp.expect_release(:'a','2026-11-25 00:00+09',NULL);
SELECT set_config('request.jwt.claim.sub', :'parent', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_parent_recurring_status() WHERE state='blocked')<>2
 THEN RAISE EXCEPTION 'Missing PDF not shown as blocked'; END IF;
END $$;
RESET ROLE;
UPDATE public.cq_v4_pdf_chapters SET pdf_ready=true WHERE chapter_id=:'second';
UPDATE public.cq_v4_approval_requests SET questions='[null]' WHERE id=:'second';
SELECT pg_temp.expect_release(:'a','2026-11-25 00:00+09',NULL);
UPDATE public.cq_v4_approval_requests SET questions='[{"kind":"short","text":"Synthetic question"}]' WHERE id=:'second';

SELECT pg_temp.expect_release(:'a','2026-11-25 00:00+09',:'second');
SELECT pg_temp.expect_release(:'b','2026-11-25 00:00+09',:'second');
INSERT INTO public.cq_v4_student_submissions VALUES
 (:'second',:'a','{"saved":true}','2026-11-25 08:00+09'),
 (:'second',:'b','{"saved":true}','2026-11-25 08:00+09');
SELECT pg_temp.expect_release(:'a','2026-11-26 00:00+09',:'third');
SELECT pg_temp.expect_release(:'b','2026-11-26 00:00+09',NULL);
SELECT pg_temp.expect_release(:'b','2026-11-28 00:00+09',NULL);
SELECT pg_temp.expect_release(:'b','2026-12-04 00:00+09',:'third');

SET LOCAL ROLE authenticated;
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM public.cq_v4_parent_recurring_status()) OR
    has_function_privilege('public.cq_v4_release_recurring_at(timestamptz)','EXECUTE')
 THEN RAISE EXCEPTION 'Student could inspect parent queue or set clock'; END IF;
 BEGIN
  PERFORM public.cq_v4_parent_enqueue_approved('20000000-0000-4000-8000-000000000083',
    ARRAY['10000000-0000-4000-8000-000000000082']::uuid[],1);
  RAISE EXCEPTION 'Student could enqueue';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $$;
RESET ROLE;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.cq_v4_pdf_assignments)<>6 OR
    (SELECT count(*) FROM public.cq_v4_lesson_schedule)<>6 OR
    (SELECT count(*) FROM public.cq_v4_student_submissions WHERE answers='{"saved":true}')<>4
 THEN RAISE EXCEPTION 'Unexpected assignment, schedule, or submission mutations'; END IF;
END $$;
ROLLBACK;
\echo RECURRING_PUBLICATION_ASSERTIONS_PASSED
