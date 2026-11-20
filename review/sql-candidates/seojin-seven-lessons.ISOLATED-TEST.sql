-- Synthetic accounts and placeholders only. Run in a fresh isolated PostgreSQL database.
\set ON_ERROR_STOP on
\ir ../../app/tests/isolated-postgres-bootstrap.sql
\ir ../../app/sql/student-weekday-policy-v1.REVIEW-ONLY.sql
\ir ../../app/sql/approved-chapter-queue-v1.REVIEW-ONLY.sql
\ir ../../app/sql/student-auto-release-existing-schedule.REVIEW-ONLY.sql

BEGIN;
\set seowoo_student '10000000-0000-4000-8000-000000000071'
\set seowoo_parent 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
\set seojin_student '10000000-0000-4000-8000-000000000072'
\set seojin_parent 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'
\set weekday_effective_from '2026-11-23'
INSERT INTO public.cq_v4_pdf_enrollments VALUES
 (:'seowoo_parent',:'seowoo_student'), (:'seojin_parent',:'seojin_student');
\ir ../../app/sql/student-weekday-policy-initial-config.REVIEW-ONLY.sql

CREATE TEMP TABLE lesson_plan (
 ordinal integer PRIMARY KEY, filename text NOT NULL, lesson_date date UNIQUE NOT NULL, chapter_id uuid UNIQUE NOT NULL
);
INSERT INTO lesson_plan VALUES
 (1,'29-1.pdf','2026-11-24','70000000-0000-4000-8000-000000000077'),
 (2,'29-2.pdf','2026-11-25','70000000-0000-4000-8000-000000000076'),
 (3,'29-3.pdf','2026-11-27','70000000-0000-4000-8000-000000000075'),
 (4,'29-4.pdf','2026-12-01','70000000-0000-4000-8000-000000000074'),
 (5,'29-5.pdf','2026-12-02','70000000-0000-4000-8000-000000000073'),
 (6,'29-6.pdf','2026-12-04','70000000-0000-4000-8000-000000000072'),
 (7,'29-7.pdf','2026-12-08','70000000-0000-4000-8000-000000000071');

SELECT set_config('request.jwt.claim.sub', :'seojin_student', true);
INSERT INTO public.cq_v4_pdf_chapters(chapter_id,parent_user_id,pdf_ready,title)
SELECT chapter_id, :'seojin_parent', false, filename FROM lesson_plan;

DO $$
DECLARE
  student uuid := auth.uid();
  parent uuid := 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';
  first_day timestamptz := TIMESTAMPTZ '2026-11-24 00:00:00+09';
  lesson record;
  day date;
  seoul_midnight timestamptz;
  actual uuid;
BEGIN
  -- Draft rows alone cannot create an assignment or schedule.
  IF public.cq_v4_ensure_approved_lesson_at(first_day) IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.cq_v4_lesson_schedule WHERE student_user_id=student)
     OR EXISTS (SELECT 1 FROM public.cq_v4_pdf_assignments WHERE student_user_id=student)
  THEN RAISE EXCEPTION 'Draft-only chapter escaped the release gate'; END IF;

  -- Model independent gates without touching real materials.
  INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal,approved_at)
  SELECT parent,student,chapter_id,ordinal,first_day FROM lesson_plan;
  INSERT INTO public.cq_v4_pdf_assignments
  SELECT chapter_id,student FROM lesson_plan;
  IF public.cq_v4_ensure_approved_lesson_at(first_day) IS NOT NULL
  THEN RAISE EXCEPTION 'Chapter without a ready PDF was released'; END IF;

  UPDATE public.cq_v4_pdf_chapters SET pdf_ready=true
  WHERE chapter_id IN (SELECT chapter_id FROM lesson_plan);
  IF public.cq_v4_ensure_approved_lesson_at(first_day) IS NOT NULL
  THEN RAISE EXCEPTION 'Chapter without published activity was released'; END IF;

  INSERT INTO public.cq_v4_activities(chapter_uuid,published_at,questions)
  SELECT chapter_id,first_day,'[]' FROM lesson_plan;
  DELETE FROM public.cq_v4_approved_chapter_queue WHERE student_user_id=student;
  IF public.cq_v4_ensure_approved_lesson_at(first_day) IS NOT NULL
  THEN RAISE EXCEPTION 'Chapter without explicit queue approval was released'; END IF;
  INSERT INTO public.cq_v4_approved_chapter_queue(parent_user_id,student_user_id,chapter_id,ordinal,approved_at)
  SELECT parent,student,chapter_id,ordinal,first_day FROM lesson_plan;
  FOR day IN SELECT '2026-11-23'::date + offset_days FROM generate_series(0,15) offset_days
  LOOP
    SELECT * INTO lesson FROM lesson_plan WHERE lesson_date=day;
    seoul_midnight := day::timestamp AT TIME ZONE 'Asia/Seoul';
    actual := public.cq_v4_ensure_approved_lesson_at(seoul_midnight);
    IF actual IS DISTINCT FROM lesson.chapter_id THEN
      RAISE EXCEPTION 'At Seoul midnight %, expected %, got %', day, lesson.chapter_id, actual;
    END IF;
    IF actual IS NOT NULL THEN
      -- A synthetic completion lets the next approved ordinal advance.
      INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers,submitted_at)
      VALUES (actual,student,'{}',seoul_midnight + interval '8 hours');
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT chapter_id,lesson_date FROM lesson_plan
    EXCEPT
    SELECT chapter_id,lesson_date FROM public.cq_v4_lesson_schedule
    WHERE student_user_id=student AND released_at IS NOT NULL
  ) OR (SELECT count(*) FROM public.cq_v4_lesson_schedule WHERE student_user_id=student) <> 7
  THEN RAISE EXCEPTION 'Released schedules differ from the seven requested dates'; END IF;

  -- For the requested fixed calendar, verify explicit reservations separately.
  -- Use fixture rows only and leave the existing queue intact.
  DELETE FROM public.cq_v4_student_submissions WHERE child_user_id=student;
  DELETE FROM public.cq_v4_lesson_schedule WHERE student_user_id=student;
  INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
  SELECT parent,student,chapter_id,lesson_date FROM lesson_plan;
  IF public.cq_v4_ensure_approved_lesson_at(first_day - interval '1 microsecond') IS NOT NULL
     OR EXISTS (
       SELECT 1 FROM public.cq_v4_lesson_schedule
       WHERE student_user_id=student AND released_at IS NOT NULL
     )
  THEN RAISE EXCEPTION 'Chapter release before 2026-11-24 00:00 Seoul'; END IF;
  FOR lesson IN SELECT * FROM lesson_plan ORDER BY ordinal
  LOOP
    seoul_midnight := lesson.lesson_date::timestamp AT TIME ZONE 'Asia/Seoul';
    actual := public.cq_v4_ensure_approved_lesson_at(seoul_midnight);
    IF actual IS DISTINCT FROM lesson.chapter_id THEN
      RAISE EXCEPTION 'Reservation % did not release chapter %', lesson.lesson_date, lesson.ordinal;
    END IF;
    IF lesson.ordinal=1 AND (SELECT count(*) FROM public.cq_v4_lesson_schedule
      WHERE student_user_id=student AND released_at IS NOT NULL) <> 1
    THEN RAISE EXCEPTION 'More than Chapter 1 released at the first Seoul midnight'; END IF;
  END LOOP;
  IF EXISTS (
    SELECT chapter_id,lesson_date FROM lesson_plan
    EXCEPT
    SELECT chapter_id,lesson_date FROM public.cq_v4_lesson_schedule
    WHERE student_user_id=student AND released_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'An explicit schedule was changed'; END IF;
END $$;
ROLLBACK;
\echo SEOJIN_SEVEN_LESSONS_ASSERTIONS_PASSED
