-- REVIEW ONLY. Install after immutable snapshot schema. No historical backfill.
BEGIN;
CREATE OR REPLACE FUNCTION public.cq_v4_parent_frozen_result(p_chapter_uuid uuid,p_student_uuid uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT pg_catalog.jsonb_build_object('questions',s.questions,'answer_key',s.answer_key,'submitted_answers',s.submitted_answers,'submitted_at',s.submitted_at,'content_hash',s.content_hash)
 FROM public.cq_v4_immutable_grading_snapshots s
 JOIN public.cq_v4_student_submissions d ON d.chapter_uuid=s.chapter_uuid AND d.child_user_id=s.student_user_id AND d.submitted_at=s.submitted_at
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid AND c.parent_user_id=s.parent_user_id
 WHERE s.chapter_uuid=p_chapter_uuid AND s.student_user_id=p_student_uuid
 AND s.parent_user_id=(SELECT auth.uid())
 AND EXISTS (SELECT 1 FROM public.cq_v4_pdf_enrollments e WHERE e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id)
$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_frozen_result(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_frozen_result(uuid,uuid) TO authenticated;
COMMIT;
