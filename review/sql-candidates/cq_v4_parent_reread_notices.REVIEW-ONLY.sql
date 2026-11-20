-- REVIEW ONLY. DO NOT RUN IN PRODUCTION WITHOUT APPROVAL AND SCHEMA AUDIT.
-- Parent-triggered, server-verified, idempotent objective reread notices.
CREATE TABLE IF NOT EXISTS public.cq_v4_reread_notices (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 parent_user_id uuid NOT NULL,
 student_user_id uuid NOT NULL,
 chapter_uuid uuid NOT NULL,
 approval_snapshot_id uuid NOT NULL,
 correct_mc integer NOT NULL CHECK(correct_mc>=0),
 total_mc integer NOT NULL CHECK(total_mc>0 AND correct_mc<=total_mc),
 submitted_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 acknowledged_at timestamptz,
 UNIQUE(student_user_id,chapter_uuid)
);
ALTER TABLE public.cq_v4_reread_notices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_reread_notices FROM PUBLIC,anon,authenticated;
-- No direct table access: authenticated parents use the restricted RPC below.
CREATE OR REPLACE FUNCTION public.cq_v4_parent_sync_reread_notice(p_student uuid,p_chapter uuid)
RETURNS TABLE(correct_mc integer,total_mc integer,needs_reread boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_parent uuid:=auth.uid();v_q jsonb;v_key jsonb;v_ans jsonb;v_snapshot uuid;
 v_submitted timestamptz;v_total integer:=0;v_correct integer:=0;v_i integer;v_option integer;v_selected text;
BEGIN
 IF v_parent IS NULL OR NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501';END IF;
 -- Exact parent/chapter/student relationship; no untrusted client score or answer key.
 SELECT a.questions,r.answer_key,s.answers->'answers',a.approval_id,s.submitted_at
 INTO v_q,v_key,v_ans,v_snapshot,v_submitted
 FROM public.cq_v4_student_submissions s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid AND c.parent_user_id=v_parent
 JOIN public.cq_v4_pdf_assignments d ON d.chapter_id=c.chapter_id AND d.student_user_id=s.child_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=v_parent AND e.student_user_id=s.child_user_id
 JOIN public.cq_v4_activities a ON a.chapter_uuid=c.chapter_id AND a.published_at IS NOT NULL
 JOIN public.cq_v4_approval_requests r ON r.id=a.approval_id AND r.chapter_uuid=c.chapter_id AND r.parent_user_id=v_parent
 WHERE s.child_user_id=p_student AND s.chapter_uuid=p_chapter
 AND a.approval_hash IS NOT NULL AND r.content_hash IS NOT NULL AND a.approval_hash=r.content_hash;
 IF NOT FOUND THEN RAISE EXCEPTION 'Submission or approval snapshot unavailable' USING ERRCODE='42501';END IF;
 IF jsonb_typeof(v_q)<>'array' OR jsonb_typeof(v_key)<>'array' OR jsonb_typeof(v_ans)<>'array'
 OR jsonb_array_length(v_q)<>jsonb_array_length(v_key) OR jsonb_array_length(v_q)<>jsonb_array_length(v_ans)
 THEN RAISE EXCEPTION 'Invalid grading snapshot' USING ERRCODE='22023';END IF;
 IF jsonb_array_length(v_q)=0 THEN RETURN QUERY SELECT 0,0,false;RETURN;END IF;
 FOR v_i IN 0..jsonb_array_length(v_q)-1 LOOP
  IF v_q->v_i->>'kind'='mc' THEN
   IF jsonb_typeof(v_q->v_i->'options')<>'array' OR jsonb_array_length(v_q->v_i->'options')<2
    OR jsonb_typeof(v_key->v_i)<>'number' OR (v_key->>v_i)!~'^(0|[1-9][0-9]*)$'
    OR jsonb_typeof(v_ans->v_i) NOT IN ('number','string') OR (v_ans->>v_i)!~'^(0|[1-9][0-9]*)$'
   THEN RAISE EXCEPTION 'Invalid MC answer or key' USING ERRCODE='22023';END IF;
   IF pg_catalog.length(v_key->>v_i)>8 OR pg_catalog.length(v_ans->>v_i)>8 THEN RAISE EXCEPTION 'MC index too large' USING ERRCODE='22023';END IF;
   v_option=(v_key->>v_i)::integer;
   IF v_option>=jsonb_array_length(v_q->v_i->'options') OR (v_ans->>v_i)::numeric>=jsonb_array_length(v_q->v_i->'options')
   THEN RAISE EXCEPTION 'MC index out of bounds' USING ERRCODE='22023';END IF;
   v_total:=v_total+1;
   IF (v_ans->>v_i)::numeric=v_option THEN v_correct:=v_correct+1;END IF;
  END IF;
 END LOOP;
 IF v_total=0 THEN RETURN QUERY SELECT 0,0,false;RETURN;END IF;
 IF v_correct*10<v_total*7 THEN
  INSERT INTO public.cq_v4_reread_notices(parent_user_id,student_user_id,chapter_uuid,approval_snapshot_id,correct_mc,total_mc,submitted_at)
  VALUES(v_parent,p_student,p_chapter,v_snapshot,v_correct,v_total,v_submitted)
  ON CONFLICT(student_user_id,chapter_uuid) DO NOTHING;
 END IF;
 RETURN QUERY SELECT v_correct,v_total,(v_correct*10<v_total*7);
END;
$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_sync_reread_notice(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_sync_reread_notice(uuid,uuid) TO authenticated;

-- Parent inbox: do not expose approval keys or student answer JSON.
CREATE OR REPLACE FUNCTION public.cq_v4_parent_reread_inbox()
RETURNS TABLE(notice_id uuid,student_user_id uuid,chapter_uuid uuid,correct_mc integer,total_mc integer,submitted_at timestamptz,created_at timestamptz,acknowledged_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
 SELECT n.id,n.student_user_id,n.chapter_uuid,n.correct_mc,n.total_mc,n.submitted_at,n.created_at,n.acknowledged_at
 FROM public.cq_v4_reread_notices n
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=n.chapter_uuid AND c.parent_user_id=n.parent_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=n.parent_user_id AND e.student_user_id=n.student_user_id
 WHERE n.parent_user_id=auth.uid() AND public.cq_is_admin()
 ORDER BY n.created_at DESC,n.id;
$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_reread_inbox() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_reread_inbox() TO authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_ack_reread_notice(p_notice uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_parent uuid:=auth.uid();v_found boolean;
BEGIN
 IF v_parent IS NULL OR NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501';END IF;
 UPDATE public.cq_v4_reread_notices n SET acknowledged_at=COALESCE(n.acknowledged_at,now())
 WHERE n.id=p_notice AND n.parent_user_id=v_parent
 AND EXISTS(SELECT 1 FROM public.cq_v4_pdf_chapters c WHERE c.chapter_id=n.chapter_uuid AND c.parent_user_id=v_parent)
 AND EXISTS(SELECT 1 FROM public.cq_v4_pdf_enrollments e WHERE e.parent_user_id=v_parent AND e.student_user_id=n.student_user_id)
 RETURNING true INTO v_found;
 RETURN COALESCE(v_found,false);
END;
$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_ack_reread_notice(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_ack_reread_notice(uuid) TO authenticated;

-- Student receives only a Boolean suggestion after the owning parent releases feedback.
-- No score, answer key, parent inbox ID, or other student's records are exposed.
CREATE OR REPLACE FUNCTION public.cq_v4_my_released_reread_suggestion(p_chapter uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $fn$
 SELECT EXISTS(
  SELECT 1 FROM public.cq_v4_student_submissions s
  JOIN public.cq_v4_reread_notices n ON n.chapter_uuid=s.chapter_uuid AND n.student_user_id=s.child_user_id
  JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid AND c.parent_user_id=n.parent_user_id
  JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
  WHERE s.child_user_id=auth.uid() AND s.chapter_uuid=p_chapter
   AND s.feedback_released IS TRUE
 );
$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_my_released_reread_suggestion(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_my_released_reread_suggestion(uuid) TO authenticated;
