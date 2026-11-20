-- REVIEW ONLY. Apply only to disposable PostgreSQL 16 test databases.
-- Install after immutable grading snapshots and reread progress table.
-- Called by the authorized submit RPC AFTER snapshot capture, in the SAME transaction.
-- Do not install the legacy cq_v4_reread_after_submit trigger alongside this RPC path.
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
    OR idx IS NULL OR idx !~ '^(0|[1-9][0-9]*)$' OR key_index IS NULL OR key_index !~ '^(0|[1-9][0-9]*)$'
    OR length(idx)>8 OR length(key_index)>8 THEN
     RAISE EXCEPTION 'Invalid frozen MC answer or key' USING ERRCODE='22023';
   END IF;
   IF idx::numeric>=jsonb_array_length(q->i->'options') OR key_index::numeric>=jsonb_array_length(q->i->'options') THEN
    RAISE EXCEPTION 'Frozen MC index out of bounds' USING ERRCODE='22023';
   END IF;
   total:=total+1;
   IF idx::numeric=key_index::numeric THEN correct:=correct+1;END IF;
  END IF;
 END LOOP;
 IF total=0 THEN RAISE EXCEPTION 'No objectively scorable MC questions' USING ERRCODE='22023';END IF;
 INSERT INTO public.cq_v4_reread_progress(chapter_uuid,child_user_id,required)
 VALUES(p_chapter,p_student,correct*10<total*7);
 RETURN true;
END;$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_record_frozen_reread_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
