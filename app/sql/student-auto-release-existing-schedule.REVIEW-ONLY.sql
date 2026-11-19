-- REVIEW ONLY. Apply after weekday policy and approved queue. Install all four
-- RPCs atomically so every schedule/submission write uses the same student lock.
BEGIN;

-- A parent's explicit "hide" must survive repeated calls by the student.
ALTER TABLE public.cq_v4_lesson_schedule
  ADD COLUMN IF NOT EXISTS auto_release_paused boolean NOT NULL DEFAULT true;
-- Existing rows may contain a historical hide. New rows can use automation.
ALTER TABLE public.cq_v4_lesson_schedule ALTER COLUMN auto_release_paused SET DEFAULT false;

-- One transaction lock per student avoids day/chapter lock ordering cycles.
CREATE OR REPLACE FUNCTION public.cq_v4_lock_student_lesson_writes(p_student uuid)
RETURNS void LANGUAGE sql VOLATILE SET search_path TO ''
AS $$
  SELECT pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_student::text, 731640)
  );
$$;
REVOKE ALL ON FUNCTION public.cq_v4_lock_student_lesson_writes(uuid)
  FROM PUBLIC, anon, authenticated;

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
  v_released uuid;
  v_parent uuid;
BEGIN
  IF v_student IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION 'Student login and timestamp required' USING ERRCODE = '42501';
  END IF;

  PERFORM public.cq_v4_lock_student_lesson_writes(v_student);

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
    RETURNING s.chapter_id INTO v_released;
    RETURN v_released;
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
  RETURNING chapter_id INTO v_released;
  RETURN v_released;
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

-- Hosted RPC definitions, with a common lock before schedule/submission state reads.
CREATE OR REPLACE FUNCTION public.cq_v4_parent_schedule_lesson(p_student_user_id uuid, p_chapter_id uuid, p_lesson_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_parent uuid:=auth.uid();
begin
 if v_parent is null or not public.cq_is_admin() then raise exception 'Parent authorization required' using errcode='42501';end if;
 if p_lesson_date is null then raise exception 'Lesson date required' using errcode='22023';end if;
 if not exists (
  select 1 from public.cq_v4_pdf_enrollments e
  join public.cq_v4_pdf_chapters c on c.parent_user_id=e.parent_user_id
  join public.cq_v4_activities act on act.chapter_uuid=c.chapter_id and act.published_at is not null
  where e.parent_user_id=v_parent and e.student_user_id=p_student_user_id
    and c.chapter_id=p_chapter_id and c.pdf_ready=true
 ) then raise exception 'Approved PDF and enrolled student required' using errcode='42501';end if;
   PERFORM public.cq_v4_lock_student_lesson_writes(p_student_user_id);
 IF EXISTS (
   SELECT 1 FROM public.cq_v4_lesson_schedule s
   WHERE s.student_user_id=p_student_user_id AND s.lesson_date=p_lesson_date
     AND s.chapter_id<>p_chapter_id
 ) THEN RAISE EXCEPTION 'Only one chapter may be scheduled per student per day' USING ERRCODE='23505'; END IF;
 IF EXISTS (
   SELECT 1 FROM public.cq_v4_student_submissions sub
   WHERE sub.child_user_id=p_student_user_id AND sub.chapter_uuid=p_chapter_id
 ) AND NOT EXISTS (
   SELECT 1 FROM public.cq_v4_lesson_schedule s
   WHERE s.student_user_id=p_student_user_id AND s.chapter_id=p_chapter_id
     AND s.parent_user_id=v_parent AND s.lesson_date=p_lesson_date
 ) THEN RAISE EXCEPTION 'Completed lessons cannot be rescheduled' USING ERRCODE='42501'; END IF;
 insert into public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
 values(v_parent,p_student_user_id,p_chapter_id,p_lesson_date)
 on conflict(student_user_id,chapter_id) do update
 set lesson_date=excluded.lesson_date
 where public.cq_v4_lesson_schedule.parent_user_id=v_parent;
 if not found then raise exception 'Schedule update not authorized' using errcode='42501';end if;
end $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_set_lesson_release(p_student_user_id uuid, p_chapter_id uuid, p_release boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_parent uuid:=auth.uid();
begin
 if v_parent is null or not public.cq_is_admin() then raise exception 'Parent authorization required' using errcode='42501';end if;
  PERFORM public.cq_v4_lock_student_lesson_writes(p_student_user_id);
 if not exists(select 1 from public.cq_v4_lesson_schedule s where s.parent_user_id=v_parent and s.student_user_id=p_student_user_id and s.chapter_id=p_chapter_id) then
  raise exception 'Owned scheduled lesson required' using errcode='42501';
 end if;
 if p_release and not exists (
  select 1 from public.cq_v4_pdf_chapters c
  join public.cq_v4_activities a on a.chapter_uuid=c.chapter_id and a.published_at is not null
  where c.chapter_id=p_chapter_id and c.parent_user_id=v_parent and c.pdf_ready=true
 ) then raise exception 'Published and verified lesson required' using errcode='42501';end if;
 update public.cq_v4_lesson_schedule
 set released_at=case when p_release then coalesce(released_at,now()) else null end
 where parent_user_id=v_parent and student_user_id=p_student_user_id and chapter_id=p_chapter_id;
end $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_questions jsonb; v_question jsonb; v_answer jsonb; v_index integer; v_value text; v_number numeric;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='28000'; END IF;
  PERFORM public.cq_v4_lock_student_lesson_writes(v_uid);
 IF NOT public.cq_v4_is_released(p_chapter_uuid,v_uid) THEN RAISE EXCEPTION 'Lesson not released by parent' USING ERRCODE='42501'; END IF;
 IF p_answers IS NULL OR jsonb_typeof(p_answers)<>'object' OR pg_catalog.octet_length(p_answers::text)>65536 THEN
   RAISE EXCEPTION 'Invalid answers' USING ERRCODE='22023'; END IF;
 -- Enforce the exact client payload contract; never trust hasAudio alone.
 IF p_answers->>'readComplete' IS DISTINCT FROM 'true'
    OR jsonb_typeof(p_answers->'answers') IS DISTINCT FROM 'array'
    OR jsonb_array_length(p_answers->'answers')=0
    OR pg_catalog.length(pg_catalog.btrim(COALESCE(p_answers->>'essay','')))=0
    OR pg_catalog.length(pg_catalog.btrim(COALESCE(p_answers->>'speaking','')))=0
    OR p_answers->>'hasAudio' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'Incomplete submission' USING ERRCODE='22023';
 END IF;
 -- Authorize the assigned, published chapter before any privileged storage lookup.
 IF NOT EXISTS (
  SELECT 1 FROM public.cq_v4_pdf_chapters c
  JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
  JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
  JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
  WHERE c.chapter_id=p_chapter_uuid AND a.student_user_id=v_uid AND c.pdf_ready IS TRUE
 ) THEN RAISE EXCEPTION 'Assignment unavailable' USING ERRCODE='42501'; END IF;
 -- Validate every answer against the authorized published question set.
 SELECT act.questions INTO v_questions FROM public.cq_v4_activities act WHERE act.chapter_uuid=p_chapter_uuid;
 IF jsonb_typeof(v_questions) IS DISTINCT FROM 'array'
    OR jsonb_array_length(v_questions)<>jsonb_array_length(p_answers->'answers') THEN
   RAISE EXCEPTION 'Answer count mismatch' USING ERRCODE='22023';
 END IF;
 FOR v_index IN 0..jsonb_array_length(v_questions)-1 LOOP
   v_question:=v_questions->v_index;v_answer:=p_answers->'answers'->v_index;
   IF jsonb_typeof(v_answer) NOT IN ('string','number') OR v_answer IS NULL THEN
     RAISE EXCEPTION 'Invalid answer value' USING ERRCODE='22023';
   END IF;
   v_value:=v_answer #>> '{}';
   IF v_value IS NULL OR pg_catalog.length(pg_catalog.btrim(v_value))=0 OR pg_catalog.length(v_value)>8000 THEN
     RAISE EXCEPTION 'Empty or oversized answer' USING ERRCODE='22023';
   END IF;
   IF v_question->>'kind'='mc' THEN
     IF jsonb_typeof(v_question->'options') IS DISTINCT FROM 'array' OR v_value !~ '^[0-9]{1,2}$' THEN
       RAISE EXCEPTION 'Invalid multiple-choice answer' USING ERRCODE='22023';
     END IF;
     v_number:=v_value::numeric;
     IF v_number<0 OR v_number>=jsonb_array_length(v_question->'options') THEN
       RAISE EXCEPTION 'Multiple-choice answer out of range' USING ERRCODE='22023';
     END IF;
   ELSIF jsonb_typeof(v_answer) IS DISTINCT FROM 'string' THEN
     RAISE EXCEPTION 'Written answer must be text' USING ERRCODE='22023';
   END IF;
 END LOOP;
 -- Only an authorized student may probe the recording for this chapter.
 IF NOT EXISTS (
    SELECT 1 FROM storage.objects o
    WHERE o.bucket_id='cq-v4-speaking'
      AND o.name IN (
        v_uid::text || '/' || p_chapter_uuid::text || '.webm',
        v_uid::text || '/' || p_chapter_uuid::text || '.mp4',
        v_uid::text || '/' || p_chapter_uuid::text || '.ogg'
      )
 ) THEN
    RAISE EXCEPTION 'Speaking recording not uploaded' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
 VALUES(p_chapter_uuid,v_uid,p_answers)
 ON CONFLICT DO NOTHING;
 -- Existing submission is immutable. The caller can fetch the authoritative record.
 RETURN QUERY SELECT s.chapter_uuid,s.submitted_at FROM public.cq_v4_student_submissions s
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=v_uid;
END; $function$;

REVOKE ALL ON FUNCTION public.cq_v4_parent_schedule_lesson(uuid,uuid,date),
  public.cq_v4_parent_set_lesson_release(uuid,uuid,boolean),
  public.cq_v4_submit_answers(uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_schedule_lesson(uuid,uuid,date),
  public.cq_v4_parent_set_lesson_release(uuid,uuid,boolean),
  public.cq_v4_submit_answers(uuid,jsonb) TO authenticated;

COMMIT;
