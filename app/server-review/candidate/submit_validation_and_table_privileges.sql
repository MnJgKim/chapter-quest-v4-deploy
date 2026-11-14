CREATE OR REPLACE FUNCTION public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_questions jsonb; v_question jsonb; v_answer jsonb; v_index integer; v_value text; v_number numeric;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='28000'; END IF;
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

-- Remove table-level privileges which bypass or do not belong to normal RLS CRUD.
-- Do not remove SELECT/INSERT/UPDATE needed by existing snapshot backup.
REVOKE TRUNCATE, TRIGGER, REFERENCES ON public.cq_v4_pdf_chapters, public.cq_v4_pdf_enrollments,
 public.cq_v4_pdf_assignments, public.cq_v4_snapshots FROM anon, authenticated;
