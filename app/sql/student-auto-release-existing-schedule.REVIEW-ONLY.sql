-- REVIEW-ONLY CANDIDATE. Never run on production without explicit approval.
-- Auto-release one ALREADY scheduled, assigned, approved lesson for authenticated student.
-- No chapter creation, assignment, schedule modification or release of future dates.
CREATE OR REPLACE FUNCTION public.cq_v4_ensure_today_approved_lesson()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_student uuid := (SELECT auth.uid());
  v_today date := (now() AT TIME ZONE 'Asia/Seoul')::date;
  v_count integer;
  v_weekdays integer[];
  v_chapter uuid;
BEGIN
  IF v_student IS NULL THEN
    RAISE EXCEPTION 'Student login required' USING ERRCODE = '42501';
  END IF;

  -- Serialize competing calls for this student/date without locking other students.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_student::text || ':' || v_today::text, 0)
  );

  -- No implicit defaults: the parent-approved policy must already exist.
  SELECT p.weekdays INTO v_weekdays
  FROM public.cq_v4_student_weekday_policy p
  WHERE p.student_user_id = v_student AND p.enabled IS TRUE
    AND p.effective_from <= v_today;
  IF v_weekdays IS NULL OR NOT (
    EXTRACT(ISODOW FROM v_today)::integer = ANY(v_weekdays)
  ) THEN RETURN NULL; END IF;

  -- Refuse ambiguous dates; never pick a chapter arbitrarily.
  SELECT count(DISTINCT s.chapter_id), min(s.chapter_id::text)::uuid
    INTO v_count, v_chapter
  FROM public.cq_v4_lesson_schedule s
  JOIN public.cq_v4_pdf_assignments a
    ON a.chapter_id = s.chapter_id AND a.student_user_id = s.student_user_id
  JOIN public.cq_v4_pdf_enrollments e
    ON e.parent_user_id = s.parent_user_id AND e.student_user_id = s.student_user_id
  JOIN public.cq_v4_pdf_chapters c
    ON c.chapter_id = s.chapter_id AND c.parent_user_id = s.parent_user_id
    AND c.pdf_ready IS TRUE
  JOIN public.cq_v4_activities act
    ON act.chapter_uuid = s.chapter_id AND act.published_at IS NOT NULL
  WHERE s.student_user_id = v_student
    AND s.lesson_date = v_today
    AND s.timezone = 'Asia/Seoul'
    AND NOT EXISTS (
      SELECT 1 FROM public.cq_v4_student_submissions sub
      WHERE sub.child_user_id = v_student AND sub.chapter_uuid = s.chapter_id
    );

  IF v_count = 0 THEN RETURN NULL; END IF;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Ambiguous daily lesson schedule' USING ERRCODE = '22023';
  END IF;

  UPDATE public.cq_v4_lesson_schedule s
  SET released_at = now()
  WHERE s.student_user_id = v_student
    AND s.chapter_id = v_chapter
    AND s.lesson_date = v_today
    AND s.timezone = 'Asia/Seoul'
    AND s.released_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.cq_v4_student_submissions sub
      WHERE sub.child_user_id = v_student AND sub.chapter_uuid = s.chapter_id
    )
    AND EXISTS (
      SELECT 1 FROM public.cq_v4_pdf_assignments a
      JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id = a.student_user_id
      JOIN public.cq_v4_pdf_chapters c
        ON c.chapter_id = a.chapter_id AND c.parent_user_id = e.parent_user_id AND c.pdf_ready IS TRUE
      JOIN public.cq_v4_activities act
        ON act.chapter_uuid = c.chapter_id AND act.published_at IS NOT NULL
      WHERE a.student_user_id = v_student AND a.chapter_id = s.chapter_id
        AND e.parent_user_id = s.parent_user_id
    );

  RETURN v_chapter;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_ensure_today_approved_lesson() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_ensure_today_approved_lesson() TO authenticated;
