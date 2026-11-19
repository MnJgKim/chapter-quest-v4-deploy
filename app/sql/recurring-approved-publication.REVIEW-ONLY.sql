-- Apply after student-auto-release-existing-schedule, in a reviewed maintenance window.
BEGIN;
ALTER TABLE public.cq_v4_approved_chapter_queue
  ADD COLUMN IF NOT EXISTS approval_id uuid REFERENCES public.cq_v4_approval_requests(id),
  ADD COLUMN IF NOT EXISTS book_id text,
  ADD COLUMN IF NOT EXISTS book_title text,
  ADD COLUMN IF NOT EXISTS ends_book boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS chapter_number integer CHECK (chapter_number > 0);
CREATE UNIQUE INDEX IF NOT EXISTS cq_v4_queue_book_chapter
  ON public.cq_v4_approved_chapter_queue(student_user_id, book_id, chapter_number);

CREATE OR REPLACE FUNCTION public.cq_v4_recurring_approval_ready(p_approval uuid, p_parent uuid, p_chapter uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO ''
AS $$
 SELECT EXISTS (
   SELECT 1 FROM public.cq_v4_approval_requests r
   JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=r.chapter_uuid AND c.parent_user_id=r.parent_user_id
   WHERE r.id=p_approval AND r.parent_user_id=p_parent AND r.chapter_uuid=p_chapter
     AND c.pdf_ready AND c.pdf_verified_at IS NOT NULL AND NULLIF(btrim(c.storage_path),'') IS NOT NULL
     AND NULLIF(btrim(r.source_text),'') IS NOT NULL AND NULLIF(btrim(r.content_hash),'') IS NOT NULL
     AND NULLIF(btrim(r.writing_prompt),'') IS NOT NULL AND NULLIF(btrim(r.speaking_prompt),'') IS NOT NULL
     AND CASE WHEN jsonb_typeof(r.questions)='array' AND jsonb_typeof(r.answer_key)='array'
                   AND jsonb_typeof(r.vocabulary)='array' THEN
       jsonb_array_length(r.questions) BETWEEN 1 AND 30
       AND jsonb_array_length(r.questions)=jsonb_array_length(r.answer_key)
       AND jsonb_array_length(r.vocabulary)>0
       AND NOT EXISTS (
         SELECT 1 FROM jsonb_array_elements(r.questions) WITH ORDINALITY q(item, pos)
         CROSS JOIN LATERAL (SELECT r.answer_key -> ((q.pos-1)::integer) AS item) k
         WHERE jsonb_typeof(q.item->'text') IS DISTINCT FROM 'string'
           OR CASE WHEN jsonb_typeof(q.item)='object' THEN q.item - ARRAY['kind','text','options'] <> '{}'::jsonb ELSE true END
           OR NULLIF(btrim(q.item->>'text'),'') IS NULL
           OR coalesce(q.item->>'kind','') NOT IN ('mc','inference','critical','short','comprehension')
           OR CASE WHEN q.item->>'kind'='mc' THEN
             CASE WHEN jsonb_typeof(q.item->'options')='array' AND jsonb_typeof(k.item)='number'
                       AND k.item::text ~ '^[0-9]{1,2}$' THEN
                jsonb_array_length(q.item->'options') NOT BETWEEN 2 AND 6
                OR k.item::text::integer >= jsonb_array_length(q.item->'options')
                OR EXISTS (SELECT 1 FROM jsonb_array_elements(q.item->'options') o
                           WHERE jsonb_typeof(o)<>'string' OR btrim(o #>> '{}')='')
             ELSE true END
           ELSE jsonb_typeof(k.item) IS DISTINCT FROM 'string' OR btrim(k.item #>> '{}')='' END
       )
       AND NOT EXISTS (
         SELECT 1 FROM jsonb_array_elements(r.vocabulary) v
         WHERE jsonb_typeof(v->'word') IS DISTINCT FROM 'string'
            OR jsonb_typeof(v->'meaning') IS DISTINCT FROM 'string'
            OR CASE WHEN jsonb_typeof(v)='object' THEN v - ARRAY['word','meaning','example'] <> '{}'::jsonb ELSE true END
            OR coalesce(jsonb_typeof(v->'example'),'null') NOT IN ('null','string')
            OR NULLIF(btrim(v->>'word'),'') IS NULL OR NULLIF(btrim(v->>'meaning'),'') IS NULL
       )
     ELSE false END
     AND NOT EXISTS (
       SELECT 1 FROM public.cq_v4_activities a WHERE a.chapter_uuid=p_chapter
         AND (a.approval_id IS DISTINCT FROM r.id OR a.approval_hash IS DISTINCT FROM r.content_hash)
     )
     AND (EXISTS (SELECT 1 FROM public.cq_v4_activities a WHERE a.chapter_uuid=p_chapter)
          OR NOT EXISTS (SELECT 1 FROM public.cq_v4_student_submissions s WHERE s.chapter_uuid=p_chapter))
 );
$$;
REVOKE ALL ON FUNCTION public.cq_v4_recurring_approval_ready(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_enqueue_approved(
 p_approval uuid, p_students uuid[], p_chapter_number integer, p_book_title text DEFAULT NULL, p_ends_book boolean DEFAULT false
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
 v_parent uuid := auth.uid();
 v_student uuid;
 v_approval public.cq_v4_approval_requests%ROWTYPE;
 v_existing public.cq_v4_approved_chapter_queue%ROWTYPE;
 v_last public.cq_v4_approved_chapter_queue%ROWTYPE;
BEGIN
 IF v_parent IS NULL OR NOT public.cq_is_admin() THEN
   RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501';
 END IF;
 IF p_chapter_number IS NULL OR p_chapter_number NOT BETWEEN 1 AND 1000 OR p_ends_book IS NULL
   OR coalesce(length(p_book_title),0)>200
   OR coalesce(cardinality(p_students),0) NOT BETWEEN 1 AND 30 OR array_position(p_students,NULL) IS NOT NULL
 THEN RAISE EXCEPTION 'Invalid chapter number or student list' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_approval FROM public.cq_v4_approval_requests r WHERE r.id=p_approval AND r.parent_user_id=v_parent;
 IF NOT public.cq_v4_recurring_approval_ready(p_approval,v_parent,v_approval.chapter_uuid) THEN
   RAISE EXCEPTION 'Verified PDF and complete approved activities required' USING ERRCODE='42501';
 END IF;
 FOR v_student IN SELECT DISTINCT x FROM unnest(p_students) x ORDER BY x LOOP
   PERFORM public.cq_v4_lock_student_lesson_writes(v_student);
   IF NOT EXISTS (SELECT 1 FROM public.cq_v4_pdf_enrollments e
                   WHERE e.parent_user_id=v_parent AND e.student_user_id=v_student)
   THEN RAISE EXCEPTION 'Student enrollment missing' USING ERRCODE='42501'; END IF;
   SELECT * INTO v_existing FROM public.cq_v4_approved_chapter_queue q
   WHERE q.student_user_id=v_student AND q.chapter_id=v_approval.chapter_uuid;
   IF FOUND THEN
     IF v_existing.parent_user_id=v_parent AND v_existing.approval_id=p_approval
        AND v_existing.chapter_number=p_chapter_number AND v_existing.ends_book=p_ends_book THEN CONTINUE; END IF;
     RAISE EXCEPTION 'Chapter already queued with different approval or position' USING ERRCODE='23505';
   END IF;
   SELECT * INTO v_last FROM public.cq_v4_approved_chapter_queue q
   WHERE q.student_user_id=v_student AND q.parent_user_id=v_parent
   ORDER BY q.ordinal DESC LIMIT 1;
   IF v_last.book_id=v_approval.book_local_id THEN
     IF v_last.ends_book OR p_chapter_number<>v_last.chapter_number+1 THEN
       RAISE EXCEPTION 'Queue the next chapter in order' USING ERRCODE='22023';
     END IF;
   ELSIF v_last.book_id IS NOT NULL AND NOT v_last.ends_book THEN
     RAISE EXCEPTION 'Mark the previous book final chapter before starting another book' USING ERRCODE='22023';
   ELSIF p_chapter_number<>1 OR EXISTS (
     SELECT 1 FROM public.cq_v4_approved_chapter_queue q
     WHERE q.student_user_id=v_student AND q.book_id=v_approval.book_local_id
   ) THEN RAISE EXCEPTION 'A new book must start at Chapter 1' USING ERRCODE='22023'; END IF;
   INSERT INTO public.cq_v4_approved_chapter_queue
     (parent_user_id,student_user_id,chapter_id,ordinal,approval_id,book_id,book_title,chapter_number,ends_book)
   SELECT v_parent,v_student,v_approval.chapter_uuid,coalesce(max(q.ordinal),0)+1,
          p_approval,v_approval.book_local_id,NULLIF(btrim(p_book_title),''),p_chapter_number,coalesce(p_ends_book,false)
   FROM public.cq_v4_approved_chapter_queue q WHERE q.student_user_id=v_student;
 END LOOP;
 RETURN v_approval.chapter_uuid;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_enqueue_approved(uuid,uuid[],integer,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_enqueue_approved(uuid,uuid[],integer,text,boolean) TO authenticated;

-- No client clock. The timestamp parameter is available only to its owner/isolated tests.
CREATE OR REPLACE FUNCTION public.cq_v4_release_recurring_student_at(v_student uuid, p_now timestamptz)
RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path TO ''
AS $$
DECLARE
 v_day date := (p_now AT TIME ZONE 'Asia/Seoul')::date;
 v_next public.cq_v4_approved_chapter_queue%ROWTYPE;
 v_approval public.cq_v4_approval_requests%ROWTYPE;
BEGIN
 IF v_student IS NULL THEN RAISE EXCEPTION 'Student login required' USING ERRCODE='42501'; END IF;
 PERFORM public.cq_v4_lock_student_lesson_writes(v_student);
 SELECT q.* INTO v_next FROM public.cq_v4_approved_chapter_queue q
 WHERE q.student_user_id=v_student AND NOT EXISTS (
   SELECT 1 FROM public.cq_v4_student_submissions s
   WHERE s.child_user_id=v_student AND s.chapter_uuid=q.chapter_id
 ) ORDER BY q.ordinal LIMIT 1;

 -- Old reserved dates (including a parent hold) stay under the existing release rules.
 IF v_next.approval_id IS NULL OR EXISTS (
   SELECT 1 FROM public.cq_v4_lesson_schedule s WHERE s.student_user_id=v_student AND s.lesson_date=v_day
 ) THEN
   IF (SELECT auth.uid())=v_student THEN RETURN public.cq_v4_ensure_approved_lesson_at(p_now); END IF;
   RETURN NULL;
 END IF;
 IF v_next.approved_at>p_now OR NOT EXISTS (
   SELECT 1 FROM public.cq_v4_student_weekday_policy p
   WHERE p.student_user_id=v_student AND p.enabled AND p.effective_from<=v_day
     AND extract(isodow FROM v_day)::integer=ANY(p.weekdays)
 ) OR NOT EXISTS (
   SELECT 1 FROM public.cq_v4_pdf_enrollments e WHERE e.student_user_id=v_student AND e.parent_user_id=v_next.parent_user_id
 ) OR EXISTS (
   SELECT 1 FROM public.cq_v4_student_submissions s WHERE s.child_user_id=v_student
     AND (s.submitted_at AT TIME ZONE 'Asia/Seoul')::date=v_day
 ) OR EXISTS (
   SELECT 1 FROM public.cq_v4_lesson_schedule s WHERE s.student_user_id=v_student
   AND (s.chapter_id=v_next.chapter_id OR s.lesson_date<v_day AND NOT EXISTS (
     SELECT 1 FROM public.cq_v4_student_submissions done WHERE done.child_user_id=v_student AND done.chapter_uuid=s.chapter_id
   ))
 ) THEN RETURN NULL; END IF;

 -- Serialize publication of the same approved PDF for different students.
 SELECT * INTO v_approval FROM public.cq_v4_approval_requests r WHERE r.id=v_next.approval_id FOR UPDATE;
 PERFORM 1 FROM public.cq_v4_pdf_chapters c WHERE c.chapter_id=v_next.chapter_id FOR UPDATE;
 IF NOT public.cq_v4_recurring_approval_ready(v_next.approval_id,v_next.parent_user_id,v_next.chapter_id)
 THEN RETURN NULL; END IF;
 INSERT INTO public.cq_v4_activities
   (chapter_uuid,questions,vocabulary,writing_prompt,speaking_prompt,published_at,approval_id,approval_hash)
 VALUES(v_next.chapter_id,v_approval.questions,v_approval.vocabulary,v_approval.writing_prompt,
        v_approval.speaking_prompt,p_now,v_approval.id,v_approval.content_hash)
 ON CONFLICT (chapter_uuid) DO NOTHING;
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id)
 VALUES(v_next.chapter_id,v_student) ON CONFLICT DO NOTHING;
 INSERT INTO public.cq_v4_lesson_schedule
    (parent_user_id,student_user_id,chapter_id,lesson_date,timezone,released_at)
 VALUES(v_next.parent_user_id,v_student,v_next.chapter_id,v_day,'Asia/Seoul',p_now);
 RETURN v_next.chapter_id;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_release_recurring_student_at(uuid,timestamptz) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_release_recurring_at(p_now timestamptz)
RETURNS uuid LANGUAGE sql VOLATILE SET search_path TO ''
AS $$ SELECT public.cq_v4_release_recurring_student_at(auth.uid(),p_now); $$;
REVOKE ALL ON FUNCTION public.cq_v4_release_recurring_at(timestamptz) FROM PUBLIC,anon,authenticated;

-- Run as the DB owner from a singleton scheduled job. The student request path
-- remains a retry if the job misses a day boundary or skips a busy student.
CREATE OR REPLACE FUNCTION public.cq_v4_run_recurring_releases()
RETURNS integer LANGUAGE plpgsql VOLATILE SET search_path TO ''
AS $$
DECLARE
 v_now timestamptz := pg_catalog.statement_timestamp();
 v_day date := (v_now AT TIME ZONE 'Asia/Seoul')::date;
 v_student uuid;
 v_count integer := 0;
BEGIN
 FOR v_student IN
   SELECT p.student_user_id FROM public.cq_v4_student_weekday_policy p
   WHERE p.enabled AND p.effective_from<=v_day
     AND extract(isodow FROM v_day)::integer=ANY(p.weekdays)
     AND EXISTS (SELECT 1 FROM public.cq_v4_approved_chapter_queue q
                 WHERE q.student_user_id=p.student_user_id AND q.approval_id IS NOT NULL)
   ORDER BY p.student_user_id
 LOOP
   IF pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended(v_student::text,731640))
   THEN
     IF public.cq_v4_release_recurring_student_at(v_student,v_now) IS NOT NULL THEN v_count:=v_count+1; END IF;
   END IF;
 END LOOP;
 RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_run_recurring_releases() FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.cq_v4_ensure_today_approved_lesson()
RETURNS uuid LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $$ SELECT public.cq_v4_release_recurring_at(pg_catalog.statement_timestamp()); $$;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_withdraw_recurring(p_student uuid, p_chapter uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE v_parent uuid := auth.uid();
BEGIN
 IF v_parent IS NULL OR NOT public.cq_is_admin() OR NOT EXISTS (
   SELECT 1 FROM public.cq_v4_pdf_enrollments e WHERE e.student_user_id=p_student AND e.parent_user_id=v_parent
 ) THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 PERFORM public.cq_v4_lock_student_lesson_writes(p_student);
 DELETE FROM public.cq_v4_approved_chapter_queue q
 WHERE q.student_user_id=p_student AND q.parent_user_id=v_parent AND q.chapter_id=p_chapter
   AND q.approval_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM public.cq_v4_approved_chapter_queue later WHERE later.student_user_id=p_student AND later.ordinal>q.ordinal)
   AND NOT EXISTS (SELECT 1 FROM public.cq_v4_lesson_schedule s WHERE s.student_user_id=p_student AND s.chapter_id=p_chapter)
   AND NOT EXISTS (SELECT 1 FROM public.cq_v4_student_submissions s WHERE s.child_user_id=p_student AND s.chapter_uuid=p_chapter);
 RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_withdraw_recurring(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_withdraw_recurring(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_recurring_status()
RETURNS TABLE(student_id uuid, weekdays integer[], effective_from date, enabled boolean,
              book_id text, chapter_number integer, chapter_title text, pdf_ready boolean,
              published boolean, ready boolean, state text, book_title text, current_title text, next_title text, withdraw_chapter uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 SELECT e.student_user_id,p.weekdays,p.effective_from,coalesce(p.enabled,false),
        q.book_id,q.chapter_number,c.title,coalesce(c.pdf_ready,false),a.published_at IS NOT NULL,
        coalesce(public.cq_v4_recurring_approval_ready(q.approval_id,e.parent_user_id,q.chapter_id),false),
        CASE WHEN q.chapter_id IS NULL THEN 'empty'
             WHEN s.released_at IS NOT NULL AND s.lesson_date<=(now() AT TIME ZONE 'Asia/Seoul')::date THEN 'in_progress'
             WHEN s.auto_release_paused THEN 'paused'
             WHEN s.chapter_id IS NOT NULL THEN 'scheduled'
             WHEN public.cq_v4_recurring_approval_ready(q.approval_id,e.parent_user_id,q.chapter_id) THEN 'ready'
             ELSE 'blocked' END,
        q.book_title,current_lesson.title,
        CASE WHEN s.released_at IS NOT NULL AND s.lesson_date<=(now() AT TIME ZONE 'Asia/Seoul')::date
             THEN following.title ELSE c.title END,
        tail.chapter_id
 FROM public.cq_v4_pdf_enrollments e
 LEFT JOIN public.cq_v4_student_weekday_policy p ON p.student_user_id=e.student_user_id
 LEFT JOIN LATERAL (
   SELECT qq.* FROM public.cq_v4_approved_chapter_queue qq
   WHERE qq.student_user_id=e.student_user_id AND qq.parent_user_id=e.parent_user_id
     AND NOT EXISTS (SELECT 1 FROM public.cq_v4_student_submissions sub
                      WHERE sub.child_user_id=e.student_user_id AND sub.chapter_uuid=qq.chapter_id)
   ORDER BY qq.ordinal LIMIT 1
 ) q ON true
 LEFT JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=q.chapter_id
 LEFT JOIN public.cq_v4_activities a ON a.chapter_uuid=q.chapter_id
 LEFT JOIN public.cq_v4_lesson_schedule s ON s.chapter_id=q.chapter_id AND s.student_user_id=e.student_user_id
 LEFT JOIN LATERAL (
   SELECT cc.title FROM public.cq_v4_lesson_schedule ss
   JOIN public.cq_v4_pdf_chapters cc ON cc.chapter_id=ss.chapter_id
   WHERE ss.student_user_id=e.student_user_id AND ss.parent_user_id=e.parent_user_id
     AND ss.released_at IS NOT NULL AND ss.lesson_date<=(now() AT TIME ZONE 'Asia/Seoul')::date
   ORDER BY ss.lesson_date DESC LIMIT 1
 ) current_lesson ON true
 LEFT JOIN LATERAL (
   SELECT cc.title FROM public.cq_v4_approved_chapter_queue qq
   JOIN public.cq_v4_pdf_chapters cc ON cc.chapter_id=qq.chapter_id
   WHERE qq.student_user_id=e.student_user_id AND qq.parent_user_id=e.parent_user_id AND qq.ordinal>q.ordinal
   ORDER BY qq.ordinal LIMIT 1
 ) following ON true
 LEFT JOIN LATERAL (
   SELECT qq.chapter_id FROM public.cq_v4_approved_chapter_queue qq
   WHERE qq.student_user_id=e.student_user_id AND qq.parent_user_id=e.parent_user_id
     AND qq.approval_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.cq_v4_approved_chapter_queue later WHERE later.student_user_id=e.student_user_id AND later.ordinal>qq.ordinal)
     AND NOT EXISTS (SELECT 1 FROM public.cq_v4_lesson_schedule ss WHERE ss.student_user_id=e.student_user_id AND ss.chapter_id=qq.chapter_id)
 ) tail ON true
 WHERE e.parent_user_id=auth.uid() AND public.cq_is_admin()
 ORDER BY e.student_user_id;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_recurring_status() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_recurring_status() TO authenticated;
COMMIT;
