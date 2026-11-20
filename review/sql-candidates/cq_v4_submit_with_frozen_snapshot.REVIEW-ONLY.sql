-- REVIEW ONLY / isolated PostgreSQL only. Never apply to production without approval.
-- Install AFTER approved-weekday-release-gate-v1, the original v3 RPC/storage file,
-- and review/sql-candidates/cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql.
-- NOT DEPLOYABLE: capture requires an approved immutable answer key at submit time.
-- Preserve the original immutable submission/idempotency behavior and historical reads.
CREATE OR REPLACE FUNCTION public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_questions jsonb; v_question jsonb; v_answer jsonb; v_index integer; v_value text; v_number numeric;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='28000'; END IF;
 -- Serialize with parent rescheduling for the same student/chapter pair.
 -- Lock must precede idempotency and lesson-day checks to avoid a submit/reschedule race.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text || ':' || p_chapter_uuid::text, 0));
 -- Existing immutable submissions are idempotent and remain readable after lesson day.
 IF EXISTS (SELECT 1 FROM public.cq_v4_student_submissions existing
            WHERE existing.chapter_uuid=p_chapter_uuid AND existing.child_user_id=v_uid) THEN
   RETURN QUERY SELECT existing.chapter_uuid,existing.submitted_at
   FROM public.cq_v4_student_submissions existing
   WHERE existing.chapter_uuid=p_chapter_uuid AND existing.child_user_id=v_uid;
   RETURN;
 END IF;
 IF NOT public.cq_v4_can_start_approved_lesson(p_chapter_uuid,v_uid) THEN
   RAISE EXCEPTION 'New work is only permitted on the scheduled Seoul lesson day' USING ERRCODE='42501';
 END IF;
 -- New-work release is authorized by cq_v4_can_start_lesson; do not require manual released_at.
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
 -- Atomic frozen snapshot capture. A failure rolls back the submission INSERT above.
 -- Pre-existing submissions exit through the earlier immutable idempotency branch.
 IF NOT public.cq_v4_capture_grading_snapshot_internal(v_uid,p_chapter_uuid) THEN
   RAISE EXCEPTION 'Submission snapshot already exists' USING ERRCODE='23505';
 END IF;
 -- Existing submission is immutable. The caller can fetch the authoritative record.
 RETURN QUERY SELECT s.chapter_uuid,s.submitted_at FROM public.cq_v4_student_submissions s
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=v_uid;
END; $function$
;
-- This list RPC keeps already submitted historical chapters readable.
CREATE OR REPLACE FUNCTION public.cq_v4_my_released_chapters()
 RETURNS TABLE(chapter_uuid uuid, chapter_title text, questions jsonb, lesson_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT c.chapter_id,c.title,act.questions,s.lesson_date
 FROM public.cq_v4_lesson_schedule s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=s.chapter_id AND a.student_user_id=s.student_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id
 JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
 WHERE s.student_user_id=(SELECT auth.uid()) AND c.pdf_ready IS TRUE
   AND (public.cq_v4_can_start_approved_lesson(s.chapter_id,(SELECT auth.uid()))
        OR EXISTS (SELECT 1 FROM public.cq_v4_student_submissions done
                   WHERE done.chapter_uuid=s.chapter_id AND done.child_user_id=(SELECT auth.uid())))
 ORDER BY s.lesson_date,s.chapter_id;
$function$
;

-- New-work PDF/read permission must use the same approved gate as submissions.
-- Preserve historical reads for this student's already-submitted, still-assigned chapter.
CREATE OR REPLACE FUNCTION public.cq_v4_can_read_lesson(p_chapter uuid,p_student uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $read$
 SELECT p_student=(SELECT auth.uid())
   AND (
     public.cq_v4_can_start_approved_lesson(p_chapter,p_student)
     OR EXISTS (
       SELECT 1 FROM public.cq_v4_student_submissions done
       JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=done.chapter_uuid AND c.pdf_ready IS TRUE
       JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id AND a.student_user_id=done.child_user_id
       JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=done.child_user_id
       JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
       WHERE done.chapter_uuid=p_chapter AND done.child_user_id=p_student
     )
   );
$read$;
REVOKE ALL ON FUNCTION public.cq_v4_can_read_lesson(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_can_read_lesson(uuid,uuid) TO authenticated;

-- Preserve the existing permissive policies and restrictive ownership checks;
-- tighten only the restrictive policies already created by v3.
ALTER POLICY cq_v4_speaking_same_day_insert_v2 ON storage.objects
WITH CHECK (
 bucket_id <> 'cq-v4-speaking' OR (
   name ~ ('^' || (SELECT auth.uid())::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](webm|mp4|ogg)$')
   AND public.cq_v4_can_start_approved_lesson(
     CASE WHEN split_part(name,'/',2) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](webm|mp4|ogg)$'
       THEN split_part(split_part(name,'/',2),'.',1)::uuid ELSE NULL::uuid END,
     (SELECT auth.uid()))
 ));
ALTER POLICY cq_v4_speaking_same_day_update_v2 ON storage.objects
USING (
 bucket_id <> 'cq-v4-speaking' OR public.cq_v4_can_start_approved_lesson(
   CASE WHEN split_part(name,'/',2) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](webm|mp4|ogg)$'
     THEN split_part(split_part(name,'/',2),'.',1)::uuid ELSE NULL::uuid END,
   (SELECT auth.uid())))
WITH CHECK (
 bucket_id <> 'cq-v4-speaking' OR (
   name ~ ('^' || (SELECT auth.uid())::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](webm|mp4|ogg)$')
   AND public.cq_v4_can_start_approved_lesson(
     CASE WHEN split_part(name,'/',2) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](webm|mp4|ogg)$'
       THEN split_part(split_part(name,'/',2),'.',1)::uuid ELSE NULL::uuid END,
     (SELECT auth.uid()))
 ));
-- PDF signer and browser integration remain separate blockers.
