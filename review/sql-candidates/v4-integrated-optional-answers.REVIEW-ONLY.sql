-- REVIEW ONLY: integrated optional answers after snapshot and scheduler prerequisites.
BEGIN;
CREATE OR REPLACE FUNCTION public.cq_v4_record_frozen_reread_internal(p_student uuid,p_chapter uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE q jsonb;k jsonb;a jsonb;total integer:=0;correct integer:=0;i integer;idx text;key_index text;
BEGIN
 IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_student THEN
  RAISE EXCEPTION 'Student identity mismatch' USING ERRCODE='42501';
 END IF;
 SELECT snap.questions,snap.answer_key,snap.submitted_answers INTO q,k,a
 FROM public.cq_v4_immutable_grading_snapshots snap
 JOIN public.cq_v4_student_submissions sub ON sub.child_user_id=snap.student_user_id
  AND sub.chapter_uuid=snap.chapter_uuid AND sub.submitted_at=snap.submitted_at
 WHERE snap.student_user_id=p_student AND snap.chapter_uuid=p_chapter FOR SHARE OF snap,sub;
 IF NOT FOUND OR jsonb_typeof(q) IS DISTINCT FROM 'array' OR jsonb_typeof(k) IS DISTINCT FROM 'array'
 OR jsonb_typeof(a) IS DISTINCT FROM 'array' OR jsonb_array_length(q)=0
 OR jsonb_array_length(q)<>jsonb_array_length(k) OR jsonb_array_length(q)<>jsonb_array_length(a) THEN
  RAISE EXCEPTION 'Frozen grading snapshot unavailable or invalid' USING ERRCODE='22023';
 END IF;
 FOR i IN 0..jsonb_array_length(q)-1 LOOP
  IF q->i->>'kind'='mc' THEN
   idx:=a->>i;key_index:=k->>i;
   IF jsonb_typeof(q->i->'options') IS DISTINCT FROM 'array' OR jsonb_array_length(q->i->'options')<2
    OR jsonb_typeof(k->i) IS DISTINCT FROM 'number'
    OR jsonb_typeof(a->i) NOT IN ('string','number')
    OR idx IS NULL OR (idx<>'' AND idx !~ '^(0|[1-9][0-9]*)$') OR key_index IS NULL OR key_index !~ '^(0|[1-9][0-9]*)$'
    OR length(idx)>8 OR length(key_index)>8 THEN
     RAISE EXCEPTION 'Invalid frozen MC answer or key' USING ERRCODE='22023';
   END IF;
   IF key_index::numeric>=jsonb_array_length(q->i->'options') THEN RAISE EXCEPTION 'Invalid key' USING ERRCODE='22023'; END IF;
   total:=total+1;
   IF idx='' THEN CONTINUE; END IF;
   IF idx::numeric>=jsonb_array_length(q->i->'options') THEN
    RAISE EXCEPTION 'Frozen MC index out of bounds' USING ERRCODE='22023';
   END IF;
   IF idx::numeric=key_index::numeric THEN correct:=correct+1;END IF;
  END IF;
 END LOOP;
 IF total=0 THEN RAISE EXCEPTION 'No objectively scorable MC questions' USING ERRCODE='22023';END IF;
 INSERT INTO public.cq_v4_reread_progress(chapter_uuid,child_user_id,required)
 VALUES(p_chapter,p_student,correct*10<total*7);
 RETURN true;
END;$fn$;
CREATE OR REPLACE FUNCTION public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_questions jsonb; v_question jsonb; v_answer jsonb; v_index integer; v_value text; v_number numeric; v_snapshot_ready boolean := false; v_inserted integer := 0;
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
   IF v_value IS NULL OR pg_catalog.length(v_value)>8000 THEN
     RAISE EXCEPTION 'Empty or oversized answer' USING ERRCODE='22023';
   END IF;
   IF jsonb_typeof(v_answer)='string' AND v_value='' THEN CONTINUE; END IF;
   IF v_question->>'kind'='mc' THEN
     IF jsonb_typeof(v_question->'options') IS DISTINCT FROM 'array' OR v_value !~ '^(0|[1-9][0-9]?)$' THEN
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
 -- Only matched approved answer keys are eligible for automatic grading.
 SELECT EXISTS (
  SELECT 1 FROM public.cq_v4_activities act
  JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=act.chapter_uuid
  JOIN public.cq_v4_approval_requests req
    ON req.id=act.approval_id AND req.chapter_uuid=act.chapter_uuid
   AND req.parent_user_id=c.parent_user_id
   AND req.content_hash=act.approval_hash AND req.questions=act.questions
  WHERE act.chapter_uuid=p_chapter_uuid AND act.published_at IS NOT NULL
    AND act.approval_hash IS NOT NULL AND jsonb_typeof(req.answer_key)='array'
    AND jsonb_array_length(req.answer_key)=jsonb_array_length(act.questions)
 ) INTO v_snapshot_ready;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
 VALUES(p_chapter_uuid,v_uid,p_answers)
 ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS v_inserted = ROW_COUNT;
 IF v_inserted=1 AND v_snapshot_ready THEN
   IF NOT public.cq_v4_capture_grading_snapshot_internal(v_uid,p_chapter_uuid) THEN
     RAISE EXCEPTION 'Immutable grading snapshot capture failed' USING ERRCODE='22023';
   END IF;
   IF NOT public.cq_v4_record_frozen_reread_internal(v_uid,p_chapter_uuid) THEN
     RAISE EXCEPTION 'Frozen reread decision failed' USING ERRCODE='22023';
   END IF;
 END IF;
 -- Existing submission is immutable. The caller can fetch the authoritative record.
 RETURN QUERY SELECT s.chapter_uuid,s.submitted_at FROM public.cq_v4_student_submissions s
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=v_uid;
END; $function$;
REVOKE ALL ON FUNCTION public.cq_v4_record_frozen_reread_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.cq_v4_submit_answers(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_submit_answers(uuid,jsonb) TO authenticated;
COMMIT;
