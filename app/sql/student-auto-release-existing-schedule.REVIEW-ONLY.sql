-- REVIEW ONLY. Apply after weekday policy, approved queue and the shared-lock
-- parent schedule/submit RPCs have been reconciled with the hosted definitions.
BEGIN;

-- A parent's explicit "hide" must survive repeated calls by the student.
ALTER TABLE public.cq_v4_lesson_schedule
  ADD COLUMN IF NOT EXISTS auto_release_paused boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.cq_v4_remember_manual_lesson_hide()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $$
BEGIN
  NEW.auto_release_paused := NEW.released_at IS NULL;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_remember_manual_lesson_hide()
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE TRIGGER cq_v4_remember_manual_lesson_hide
  BEFORE UPDATE OF released_at ON public.cq_v4_lesson_schedule
  FOR EACH ROW
  EXECUTE FUNCTION public.cq_v4_remember_manual_lesson_hide();

-- Owner-only implementation with an explicit clock for isolated boundary tests.
CREATE OR REPLACE FUNCTION public.cq_v4_ensure_approved_lesson_at(p_now timestamptz)
RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path TO ''
AS $$
DECLARE
  v_student uuid := (SELECT auth.uid());
  v_today date := (p_now AT TIME ZONE 'Asia/Seoul')::date;
  v_schedule public.cq_v4_lesson_schedule%ROWTYPE;
  v_chapter uuid;
  v_parent uuid;
BEGIN
  IF v_student IS NULL THEN
    RAISE EXCEPTION 'Student login required' USING ERRCODE = '42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('cq_v4_day:' || v_student::text || ':' || v_today::text, 0)
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.cq_v4_student_weekday_policy p
    WHERE p.student_user_id = v_student AND p.enabled
      AND p.effective_from <= v_today
      AND EXTRACT(ISODOW FROM v_today)::integer = ANY(p.weekdays)
  ) OR EXISTS (
    SELECT 1 FROM public.cq_v4_student_submissions done
    WHERE done.child_user_id = v_student
      AND done.submitted_at >= (v_today::timestamp AT TIME ZONE 'Asia/Seoul')
      AND done.submitted_at < ((v_today + 1)::timestamp AT TIME ZONE 'Asia/Seoul')
  ) THEN RETURN NULL; END IF;

  -- A parent-scheduled date takes precedence over the queue even when the
  -- scheduled chapter is submitted, unpublished or unavailable. Ambiguity
  -- blocks automatic release while leaving the legacy released list usable.
  BEGIN
    SELECT s.* INTO STRICT v_schedule
    FROM public.cq_v4_lesson_schedule s
    WHERE s.student_user_id = v_student AND s.lesson_date = v_today;
  EXCEPTION
    WHEN no_data_found THEN NULL;
    WHEN too_many_rows THEN RETURN NULL;
  END;

  IF v_schedule.chapter_id IS NOT NULL THEN
    v_chapter := v_schedule.chapter_id;
    v_parent := v_schedule.parent_user_id;
  ELSE
    v_chapter := public.cq_v4_next_approved_chapter(v_student);
    IF v_chapter IS NULL THEN RETURN NULL; END IF;

    SELECT q.parent_user_id INTO v_parent
    FROM public.cq_v4_approved_chapter_queue q
    WHERE q.student_user_id = v_student AND q.chapter_id = v_chapter;
  END IF;

  -- Same lock as rescheduling and submission, acquired after the day lock.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_student::text || ':' || v_chapter::text, 0)
  );

  IF NOT EXISTS (
    SELECT 1
    FROM public.cq_v4_pdf_assignments a
    JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id = a.student_user_id
    JOIN public.cq_v4_pdf_chapters c
      ON c.chapter_id = a.chapter_id AND c.parent_user_id = e.parent_user_id AND c.pdf_ready
    JOIN public.cq_v4_activities act
      ON act.chapter_uuid = c.chapter_id AND act.published_at <= p_now
    WHERE a.student_user_id = v_student AND a.chapter_id = v_chapter
      AND e.parent_user_id = v_parent
  ) OR EXISTS (
    SELECT 1 FROM public.cq_v4_student_submissions done
    WHERE done.child_user_id = v_student AND done.chapter_uuid = v_chapter
  ) THEN RETURN NULL; END IF;

  IF v_schedule.chapter_id IS NOT NULL THEN
    UPDATE public.cq_v4_lesson_schedule s
    SET released_at = p_now
    WHERE s.student_user_id = v_student AND s.chapter_id = v_chapter
      AND s.parent_user_id = v_parent AND s.lesson_date = v_today
      AND s.timezone = 'Asia/Seoul'
      AND s.released_at IS NULL AND NOT s.auto_release_paused
    RETURNING s.chapter_id INTO v_chapter;
    RETURN v_chapter;
  END IF;

  IF public.cq_v4_next_approved_chapter(v_student) IS DISTINCT FROM v_chapter
    OR NOT EXISTS (
      SELECT 1 FROM public.cq_v4_approved_chapter_queue q
      WHERE q.student_user_id = v_student AND q.chapter_id = v_chapter
        AND q.parent_user_id = v_parent AND q.approved_at <= p_now
    ) OR EXISTS (
      SELECT 1 FROM public.cq_v4_lesson_schedule s
      WHERE s.student_user_id = v_student
        AND (s.chapter_id = v_chapter OR s.lesson_date = v_today OR
          (s.lesson_date < v_today AND NOT EXISTS (
            SELECT 1 FROM public.cq_v4_student_submissions done
            WHERE done.child_user_id = v_student AND done.chapter_uuid = s.chapter_id
          )))
    ) THEN RETURN NULL; END IF;

  INSERT INTO public.cq_v4_lesson_schedule
    (parent_user_id, student_user_id, chapter_id, lesson_date, timezone, released_at)
  VALUES (v_parent, v_student, v_chapter, v_today, 'Asia/Seoul', p_now)
  ON CONFLICT (student_user_id, chapter_id) DO NOTHING
  RETURNING chapter_id INTO v_chapter;
  RETURN v_chapter;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_ensure_approved_lesson_at(timestamptz)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_ensure_today_approved_lesson()
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $$
  SELECT public.cq_v4_ensure_approved_lesson_at(pg_catalog.statement_timestamp());
$$;
REVOKE ALL ON FUNCTION public.cq_v4_ensure_today_approved_lesson() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_ensure_today_approved_lesson() TO authenticated;

COMMIT;
