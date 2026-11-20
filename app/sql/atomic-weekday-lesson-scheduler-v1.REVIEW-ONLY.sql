-- REVIEW ONLY. Isolated PostgreSQL evaluation only; do not deploy or call on real students.
-- Student-initiated, server-clock schedule creation. No assignment or publication writes.
-- Dependencies: approved queue, weekday policy, existing lesson schedule, submissions.
CREATE OR REPLACE FUNCTION public.cq_v4_ensure_today_approved_lesson()
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
 v_student uuid := auth.uid();
 v_today date := (now() AT TIME ZONE 'Asia/Seoul')::date;
 v_chapter uuid;
 v_parent uuid;
BEGIN
 IF v_student IS NULL THEN
   RAISE EXCEPTION 'Login required' USING ERRCODE='28000';
 END IF;
 -- One transaction-wide student/day mutex, independent of chapter ID.
 PERFORM pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended('cq_v4_day:' || v_student::text || ':' || v_today::text,0)
 );
 -- Never create a second chapter slot on the same Seoul date.
 IF EXISTS (
   SELECT 1 FROM public.cq_v4_lesson_schedule s
   WHERE s.student_user_id=v_student AND s.lesson_date=v_today
 ) OR EXISTS (
   SELECT 1 FROM public.cq_v4_student_submissions done
   WHERE done.child_user_id=v_student
     AND (done.submitted_at AT TIME ZONE 'Asia/Seoul')::date=v_today
 ) THEN
   RETURN NULL;
 END IF;
 -- The planning helper is not itself a permission gate: trusted server date only.
 v_chapter := public.cq_v4_weekday_approved_candidate(v_student,v_today);
 IF v_chapter IS NULL THEN RETURN NULL; END IF;
 SELECT q.parent_user_id INTO v_parent
 FROM public.cq_v4_approved_chapter_queue q
 WHERE q.student_user_id=v_student AND q.chapter_id=v_chapter;
 IF v_parent IS NULL THEN RETURN NULL; END IF;
 -- Never overwrite an existing parent schedule or audited makeup decision.
 IF EXISTS (
   SELECT 1 FROM public.cq_v4_lesson_schedule s
   WHERE s.student_user_id=v_student AND s.chapter_id=v_chapter
 ) THEN RETURN NULL; END IF;
 -- Coordinate with parent schedule changes and student submission for chapter.
 PERFORM pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended(v_student::text || ':' || v_chapter::text,0)
 );
 -- Recheck after taking the same chapter lock as parent scheduling and submit.
 -- Do not use a stale candidate if a parent changed the chapter schedule.
 IF EXISTS (
   SELECT 1 FROM public.cq_v4_lesson_schedule s
   WHERE s.student_user_id=v_student
     AND (s.chapter_id=v_chapter OR s.lesson_date=v_today)
 ) OR EXISTS (
   SELECT 1 FROM public.cq_v4_student_submissions done
   WHERE done.child_user_id=v_student
     AND (done.chapter_uuid=v_chapter
          OR (done.submitted_at AT TIME ZONE 'Asia/Seoul')::date=v_today)
 ) THEN RETURN NULL; END IF;
 IF public.cq_v4_weekday_approved_candidate(v_student,v_today) IS DISTINCT FROM v_chapter THEN
   RETURN NULL;
 END IF;
 INSERT INTO public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
 VALUES(v_parent,v_student,v_chapter,v_today)
 ON CONFLICT(student_user_id,chapter_id) DO NOTHING;
 IF NOT FOUND THEN RETURN NULL; END IF;
 RETURN v_chapter;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_ensure_today_approved_lesson() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_ensure_today_approved_lesson() TO authenticated;
-- RELEASE BLOCKERS: must validate concurrency with actual PostgreSQL; existing
-- can_start, storage and PDF RPCs still use legacy predicate. Verify table RLS,
-- grants, owner and old schedule compatibility before any integration.
