-- REVIEW ONLY. Do not run against production before isolated PostgreSQL tests and explicit approval.
-- Inbox is derived from immutable submitted answers and approved/published answer keys.
-- Acknowledgements are separate; no UPDATE to student submissions is permitted.
BEGIN;
CREATE TABLE IF NOT EXISTS public.cq_v4_reread_ack (
 parent_user_id uuid NOT NULL,
 student_user_id uuid NOT NULL,
 chapter_uuid uuid NOT NULL,
 acknowledged_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (parent_user_id,student_user_id,chapter_uuid)
);
ALTER TABLE public.cq_v4_reread_ack ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_reread_ack FROM PUBLIC,anon,authenticated;

-- Return NULL when key/answer structure cannot be trusted. Count only valid MC questions.
CREATE OR REPLACE FUNCTION public.cq_v4_objective_reread_score(p_chapter uuid,p_student uuid)
RETURNS TABLE(correct_mc integer,total_mc integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE v_questions jsonb;v_key jsonb;v_answers jsonb;v_q jsonb;v_k jsonb;v_a text;v_total integer:=0;v_correct integer:=0;v_i integer;
BEGIN
 IF (SELECT auth.uid()) IS NULL THEN RETURN; END IF;
 SELECT r.questions,r.answer_key,s.answers->'answers'
 INTO v_questions,v_key,v_answers
 FROM public.cq_v4_student_submissions s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
 JOIN public.cq_v4_pdf_assignments ass ON ass.chapter_id=s.chapter_uuid AND ass.student_user_id=s.child_user_id
 JOIN public.cq_v4_activities a ON a.chapter_uuid=s.chapter_uuid AND a.published_at IS NOT NULL
 JOIN public.cq_v4_approval_requests r ON r.id=a.approval_id AND r.chapter_uuid=a.chapter_uuid AND r.content_hash=a.approval_hash
 WHERE s.chapter_uuid=p_chapter AND s.child_user_id=p_student
 AND (c.parent_user_id=(SELECT auth.uid()) OR s.child_user_id=(SELECT auth.uid()))
 LIMIT 1;
 IF jsonb_typeof(v_questions) IS DISTINCT FROM 'array'
 OR jsonb_typeof(v_key) IS DISTINCT FROM 'array'
 OR jsonb_typeof(v_answers) IS DISTINCT FROM 'array' THEN RETURN; END IF;
 IF jsonb_array_length(v_questions)=0
 OR jsonb_array_length(v_questions)<>jsonb_array_length(v_key)
 OR jsonb_array_length(v_questions)<>jsonb_array_length(v_answers) THEN RETURN; END IF;
 FOR v_i IN 0..jsonb_array_length(v_questions)-1 LOOP
  v_q:=v_questions->v_i;
  IF v_q->>'kind' IS DISTINCT FROM 'mc' THEN CONTINUE; END IF;
  v_k:=v_key->v_i;v_a:=v_answers->>v_i;
  IF jsonb_typeof(v_q->'options') IS DISTINCT FROM 'array' THEN RETURN; END IF;
  IF jsonb_array_length(v_q->'options')<2 THEN RETURN; END IF;
  IF jsonb_typeof(v_k) IS DISTINCT FROM 'number'
   OR v_k::text !~ '^(0|[1-9][0-9]*)$'
   OR v_a IS NULL OR v_a !~ '^(0|[1-9][0-9]*)$' THEN RETURN; END IF;
  IF v_k::text::numeric>=jsonb_array_length(v_q->'options')
   OR v_a::numeric>=jsonb_array_length(v_q->'options') THEN RETURN; END IF;
  v_total:=v_total+1;
  IF v_a::numeric=v_k::text::numeric THEN v_correct:=v_correct+1; END IF;
 END LOOP;
 IF v_total=0 THEN RETURN; END IF;
 correct_mc:=v_correct;total_mc:=v_total;RETURN NEXT;
END;$$;
REVOKE ALL ON FUNCTION public.cq_v4_objective_reread_score(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_reread_inbox()
RETURNS TABLE(notice_id uuid,student_user_id uuid,chapter_uuid uuid,correct_mc integer,total_mc integer,submitted_at timestamptz,acknowledged_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 SELECT md5(s.child_user_id::text||':'||s.chapter_uuid::text)::uuid AS notice_id,s.child_user_id,s.chapter_uuid,g.correct_mc,g.total_mc,s.submitted_at,ack.acknowledged_at
 FROM public.cq_v4_student_submissions s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid AND c.parent_user_id=(SELECT auth.uid())
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=s.chapter_uuid AND a.student_user_id=s.child_user_id
 CROSS JOIN LATERAL public.cq_v4_objective_reread_score(s.chapter_uuid,s.child_user_id) g
 LEFT JOIN public.cq_v4_reread_ack ack ON ack.parent_user_id=c.parent_user_id AND ack.student_user_id=s.child_user_id AND ack.chapter_uuid=s.chapter_uuid
 WHERE s.feedback_released IS TRUE AND g.correct_mc*10<g.total_mc*7
 ORDER BY s.submitted_at DESC;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_reread_inbox() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_reread_inbox() TO authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_ack_reread_notice(p_notice uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE v_student uuid;v_chapter uuid;
BEGIN
 SELECT i.student_user_id,i.chapter_uuid INTO v_student,v_chapter
 FROM public.cq_v4_parent_reread_inbox() i WHERE i.notice_id=p_notice;
 IF v_student IS NULL THEN RETURN false; END IF;
 INSERT INTO public.cq_v4_reread_ack(parent_user_id,student_user_id,chapter_uuid)
 VALUES ((SELECT auth.uid()),v_student,v_chapter)
 ON CONFLICT (parent_user_id,student_user_id,chapter_uuid) DO NOTHING;
 RETURN true;
END;$$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_ack_reread_notice(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_ack_reread_notice(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_my_released_reread_suggestion(p_chapter uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 SELECT EXISTS(
  SELECT 1 FROM public.cq_v4_student_submissions s
  JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid
  JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
  JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=s.chapter_uuid AND a.student_user_id=s.child_user_id
  CROSS JOIN LATERAL public.cq_v4_objective_reread_score(s.chapter_uuid,s.child_user_id) g
  WHERE s.chapter_uuid=p_chapter AND s.child_user_id=(SELECT auth.uid())
    AND s.feedback_released IS TRUE AND g.correct_mc*10<g.total_mc*7
 );
$$;
REVOKE ALL ON FUNCTION public.cq_v4_my_released_reread_suggestion(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_my_released_reread_suggestion(uuid) TO authenticated;
COMMIT;
