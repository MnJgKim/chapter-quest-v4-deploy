-- REVIEW ONLY: current published material, never used to grade past submissions.
BEGIN;
CREATE OR REPLACE FUNCTION public.cq_v4_parent_material_preview(p_chapter_uuid uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT pg_catalog.jsonb_build_object(
 'chapter_uuid',c.chapter_id,'title',c.title,'pdf_ready',c.pdf_ready,
 'published_at',a.published_at,'approval_valid',r.id IS NOT NULL,'content_hash',a.approval_hash,
 'questions',a.questions,'answer_key',r.answer_key,'vocabulary',a.vocabulary,
 'writing_prompt',a.writing_prompt,'speaking_prompt',a.speaking_prompt,
 'assignments',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('student_user_id',x.student_user_id,'lesson_date',s.lesson_date,'released_at',s.released_at))
 FROM public.cq_v4_pdf_assignments x JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id=x.student_user_id AND e.parent_user_id=c.parent_user_id
 LEFT JOIN public.cq_v4_lesson_schedule s ON s.chapter_id=x.chapter_id AND s.student_user_id=x.student_user_id AND s.parent_user_id=c.parent_user_id
 WHERE x.chapter_id=c.chapter_id),'[]'::jsonb))
 FROM public.cq_v4_pdf_chapters c
 LEFT JOIN public.cq_v4_activities a ON a.chapter_uuid=c.chapter_id AND a.published_at IS NOT NULL
 LEFT JOIN public.cq_v4_approval_requests r ON r.id=a.approval_id AND r.parent_user_id=c.parent_user_id AND r.chapter_uuid=c.chapter_id AND r.content_hash=a.approval_hash AND r.questions=a.questions
 WHERE c.chapter_id=p_chapter_uuid AND c.parent_user_id=(SELECT auth.uid())
$fn$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_material_preview(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_material_preview(uuid) TO authenticated;
COMMIT;
