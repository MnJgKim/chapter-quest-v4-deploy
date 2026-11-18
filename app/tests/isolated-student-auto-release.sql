-- PostgreSQL 16 fixture. All mutations are rolled back; UUIDs are synthetic.
\set ON_ERROR_STOP on
BEGIN;

-- Match the released-list and parent-toggle signatures in the hosted snapshot.
ALTER TABLE public.cq_v4_pdf_chapters ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS vocabulary jsonb;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS writing_prompt text;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS speaking_prompt text;
\ir ../server-review/release-schedule-live.fixture.sql

ALTER TABLE public.cq_v4_lesson_schedule ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.cq_v4_lesson_schedule TO authenticated;
CREATE FUNCTION pg_temp.expect_release(student uuid, clock_time timestamptz, expected uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', student::text, true);
  actual := public.cq_v4_ensure_approved_lesson_at(clock_time);
  IF actual IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'Student %, at %: expected %, got %', student, clock_time, expected, actual;
  END IF;
END;
$$;

INSERT INTO public.cq_v4_student_weekday_policy VALUES
 ('10000000-0000-4000-8000-000000000001', ARRAY[1,3,4], '2026-11-23', true),
 ('10000000-0000-4000-8000-000000000002', ARRAY[2,3,5], '2026-11-23', true);
INSERT INTO public.cq_v4_pdf_enrollments VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000001'),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000002'),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000003');

WITH chapters AS (
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title)
SELECT chapter_id, 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', n <> 5, 'Chapter ' || n
FROM unnest(ARRAY[
 'f0000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',
 '20000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000004',
 '20000000-0000-4000-8000-000000000005','20000000-0000-4000-8000-000000000006',
 '20000000-0000-4000-8000-000000000007','20000000-0000-4000-8000-000000000008'
]::uuid[]) WITH ORDINALITY AS fixture(chapter_id,n)
RETURNING chapter_id
)
INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,questions)
SELECT chapter_id,'2026-11-01','[]' FROM chapters;
INSERT INTO public.cq_v4_pdf_assignments VALUES
 ('f0000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001'),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001'),
 ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001'),
 ('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001'),
 ('20000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000002'),
 ('20000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000002'),
 ('20000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000003');

INSERT INTO public.cq_v4_approved_chapter_queue VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000001','f0000000-0000-4000-8000-000000000001',1,'2026-11-01'),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',2,'2026-11-01'),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000005',1,'2026-11-01'),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000006',2,'2026-11-01'),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa','10000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000007',1,'2026-11-01');

\set a '10000000-0000-4000-8000-000000000001'
\set b '10000000-0000-4000-8000-000000000002'
\set c '10000000-0000-4000-8000-000000000003'
\set parent 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
\set first 'f0000000-0000-4000-8000-000000000001'
\set next '20000000-0000-4000-8000-000000000002'
\set makeup '20000000-0000-4000-8000-000000000003'
\set completed '20000000-0000-4000-8000-000000000004'

INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date,released_at) VALUES
 (:'parent',:'a',:'completed','2026-11-19','2026-11-18T15:00Z'),
 (:'parent',:'a',:'makeup','2026-11-24','2026-11-23T15:00Z');
INSERT INTO public.cq_v4_student_submissions VALUES
 (:'completed',:'a','{"saved":"untouched"}','2026-11-19T03:00Z');
SET LOCAL TIME ZONE 'America/Los_Angeles';
CREATE TEMP TABLE saved_history AS
SELECT to_jsonb(s) AS row FROM public.cq_v4_lesson_schedule s WHERE student_user_id = :'a'
UNION ALL
SELECT to_jsonb(sub) FROM public.cq_v4_student_submissions sub WHERE child_user_id = :'a';

-- Monday Seoul midnight, reverse UUID order and idempotence.
SELECT pg_temp.expect_release(:'a','2026-11-22T14:59:59.999999Z',NULL);
SELECT pg_temp.expect_release(:'a','2026-11-22T15:00:00Z',:'first');
SELECT pg_temp.expect_release(:'a','2026-11-22T15:00:01Z',NULL);

-- Once Monday is submitted, Tuesday has an explicit off-pattern makeup.
-- That date remains available through the original released_at/date gate.
INSERT INTO public.cq_v4_student_submissions VALUES
 (:'first',:'a','{"saved":"first"}','2026-11-23T03:00Z');
SELECT pg_temp.expect_release(:'a','2026-11-23T15:00Z',NULL);
SELECT pg_temp.expect_release(:'a','2026-11-24T15:00Z',NULL);
INSERT INTO public.cq_v4_student_submissions VALUES
 (:'makeup',:'a','{"saved":"makeup"}','2026-11-24T03:00Z');

-- Existing approved date must keep its date and gain only the release flag.
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
VALUES (:'parent',:'a',:'next','2026-11-25');
SELECT pg_temp.expect_release(:'a','2026-11-24T14:59:59Z',NULL);
SELECT pg_temp.expect_release(:'a','2026-11-24T15:00Z',:'next');
SELECT set_config('request.jwt.claim.sub', :'parent', true);
SET LOCAL ROLE authenticated;
SELECT public.cq_v4_parent_set_lesson_release(:'a',:'next',false);
RESET ROLE;
SELECT pg_temp.expect_release(:'a','2026-11-24T15:01Z',NULL);

-- No ready PDF at the head of the second student's queue, and no default
-- policy for the third student even though a safe assigned chapter exists.
SELECT pg_temp.expect_release(:'b','2026-11-23T15:00Z',NULL);
SELECT pg_temp.expect_release(:'b','2026-11-24T15:00Z',NULL);
SELECT pg_temp.expect_release(:'b','2026-11-26T15:00Z',NULL);
SELECT pg_temp.expect_release(:'c','2026-11-25T15:00Z',NULL);

DO $$
BEGIN
  IF EXISTS (
    SELECT row FROM saved_history
    EXCEPT
    (SELECT to_jsonb(s) FROM public.cq_v4_lesson_schedule s
      UNION ALL SELECT to_jsonb(sub) FROM public.cq_v4_student_submissions sub)
  ) THEN RAISE EXCEPTION 'Original schedule, makeup or submission changed'; END IF;
  IF EXISTS (SELECT 1 FROM public.cq_v4_lesson_schedule
    WHERE student_user_id IN ('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003'))
  THEN RAISE EXCEPTION 'Unexpected schedule without PDF or policy'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cq_v4_lesson_schedule
    WHERE chapter_id='20000000-0000-4000-8000-000000000002' AND lesson_date='2026-11-25'
      AND released_at IS NULL AND auto_release_paused)
  THEN RAISE EXCEPTION 'Parent hide was overridden'; END IF;
END $$;

-- The actual student list, not just the scheduler return value, uses the gate.
SELECT set_config('request.jwt.claim.sub', :'a', true);
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.cq_v4_my_released_chapters()
    WHERE chapter_uuid='20000000-0000-4000-8000-000000000002')
  THEN RAISE EXCEPTION 'Hidden lesson leaked through actual student list'; END IF;
  IF EXISTS (SELECT 1 FROM public.cq_v4_lesson_schedule)
  THEN RAISE EXCEPTION 'Direct table select bypassed RLS'; END IF;
  IF has_function_privilege('public.cq_v4_ensure_approved_lesson_at(timestamptz)', 'EXECUTE')
    OR has_table_privilege('public.cq_v4_student_weekday_policy', 'UPDATE')
    OR has_table_privilege('public.cq_v4_approved_chapter_queue', 'INSERT')
  THEN RAISE EXCEPTION 'Authenticated client can change clock, policy or approval order'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub', :'b', true);
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.cq_v4_my_released_chapters())
  THEN RAISE EXCEPTION 'Cross-student release leak'; END IF;
END $$;
RESET ROLE;
-- A duplicate legacy day blocks automation, even if only one row is ready.
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
VALUES (:'parent',:'a',:'next','2026-11-26')
ON CONFLICT (student_user_id,chapter_id) DO UPDATE SET lesson_date=EXCLUDED.lesson_date;
INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
VALUES (:'parent',:'a','20000000-0000-4000-8000-000000000008','2026-11-26');
SELECT pg_temp.expect_release(:'a','2026-11-25T15:00Z',NULL);

-- In the synthetic second-student fixture only, make the PDF ready to test
-- that Thursday stays closed and Friday opens. Real students are untouched.
UPDATE public.cq_v4_pdf_chapters SET pdf_ready=true
WHERE chapter_id='20000000-0000-4000-8000-000000000005';
SELECT pg_temp.expect_release(:'b','2026-11-25T15:00Z',NULL);
SELECT pg_temp.expect_release(:'b','2026-11-26T15:00Z','20000000-0000-4000-8000-000000000005');
SET LOCAL ROLE anon;
DO $$
BEGIN
  IF has_function_privilege('public.cq_v4_ensure_today_approved_lesson()', 'EXECUTE')
  THEN RAISE EXCEPTION 'Anonymous scheduler access'; END IF;
END $$;
ROLLBACK;
\echo STUDENT_WEEKDAY_RELEASE_ASSERTIONS_PASSED
