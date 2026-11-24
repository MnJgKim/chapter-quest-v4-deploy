-- REVIEW ONLY. Isolated PostgreSQL tests only. NOT integrated into submission RPC.
-- Call this helper INSIDE the same authorized submission transaction, immediately
-- after successful INSERT, never as an independent browser RPC.
CREATE TABLE IF NOT EXISTS public.cq_v4_immutable_grading_snapshots(
 student_user_id uuid NOT NULL,
 chapter_uuid uuid NOT NULL,
 parent_user_id uuid NOT NULL,
 approval_id uuid NOT NULL,
 content_hash text NOT NULL,
 questions jsonb NOT NULL,
 answer_key jsonb NOT NULL,
 submitted_answers jsonb NOT NULL,
 submitted_at timestamptz NOT NULL,
 captured_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(student_user_id,chapter_uuid),
 CHECK(jsonb_typeof(questions)='array' AND jsonb_typeof(answer_key)='array' AND jsonb_typeof(submitted_answers)='array'),
 CHECK(jsonb_array_length(questions)=jsonb_array_length(answer_key) AND jsonb_array_length(questions)=jsonb_array_length(submitted_answers))
);
ALTER TABLE public.cq_v4_immutable_grading_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_immutable_grading_snapshots FROM PUBLIC,anon,authenticated;
-- No grants on capture helper: intended to be invoked only by a reviewed
-- SECURITY DEFINER submit RPC. Its owner must be restricted before deployment.
CREATE OR REPLACE FUNCTION public.cq_v4_capture_grading_snapshot_internal(p_student uuid,p_chapter uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $fn$
DECLARE v_parent uuid;v_approval uuid;v_hash text;v_questions jsonb;v_key jsonb;v_answers jsonb;v_submitted timestamptz;
BEGIN
 IF p_student IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Student identity mismatch' USING ERRCODE='42501';
 END IF;
 SELECT c.parent_user_id,a.approval_id,r.content_hash,a.questions,r.answer_key,s.answers->'answers',s.submitted_at
 INTO v_parent,v_approval,v_hash,v_questions,v_key,v_answers,v_submitted
 FROM public.cq_v4_student_submissions s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid
 JOIN public.cq_v4_pdf_assignments d ON d.chapter_id=c.chapter_id AND d.student_user_id=s.child_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
 JOIN public.cq_v4_activities a ON a.chapter_uuid=c.chapter_id AND a.published_at IS NOT NULL
 JOIN public.cq_v4_approval_requests r ON r.id=a.approval_id AND r.chapter_uuid=c.chapter_id AND r.parent_user_id=c.parent_user_id
 WHERE s.child_user_id=p_student AND s.chapter_uuid=p_chapter
 AND a.approval_hash IS NOT NULL AND r.content_hash IS NOT NULL AND a.approval_hash=r.content_hash
 AND a.questions=r.questions
 FOR SHARE OF s,a,r;
 IF NOT FOUND THEN RAISE EXCEPTION 'Approved submission unavailable' USING ERRCODE='42501';END IF;
 IF v_approval IS NULL OR jsonb_typeof(v_questions)<>'array' OR jsonb_typeof(v_key)<>'array' OR jsonb_typeof(v_answers)<>'array'
 OR jsonb_array_length(v_questions)=0 OR jsonb_array_length(v_questions)<>jsonb_array_length(v_key)
 OR jsonb_array_length(v_questions)<>jsonb_array_length(v_answers)
 THEN RAISE EXCEPTION 'Invalid snapshot payload' USING ERRCODE='22023';END IF;
 INSERT INTO public.cq_v4_immutable_grading_snapshots(student_user_id,chapter_uuid,parent_user_id,approval_id,content_hash,questions,answer_key,submitted_answers,submitted_at)
 VALUES(p_student,p_chapter,v_parent,v_approval,v_hash,v_questions,v_key,v_answers,v_submitted)
 ON CONFLICT(student_user_id,chapter_uuid) DO NOTHING;
 RETURN FOUND;
END;$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_capture_grading_snapshot_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
-- Fail closed for direct writes: trigger also protects against privileged accidental UPDATE/DELETE.
CREATE OR REPLACE FUNCTION public.cq_v4_reject_snapshot_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $fn$
BEGIN RAISE EXCEPTION 'Immutable snapshot cannot be modified' USING ERRCODE='42501';END;$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_reject_snapshot_mutation() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS cq_v4_snapshot_immutable_guard ON public.cq_v4_immutable_grading_snapshots;
CREATE TRIGGER cq_v4_snapshot_immutable_guard BEFORE UPDATE OR DELETE ON public.cq_v4_immutable_grading_snapshots
FOR EACH ROW EXECUTE FUNCTION public.cq_v4_reject_snapshot_mutation();
