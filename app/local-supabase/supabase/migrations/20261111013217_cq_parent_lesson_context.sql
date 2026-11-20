-- Candidate read-only API. Apply to production only after explicit approval.
-- No existing table, policy, account, submission or storage object is changed.
CREATE FUNCTION public.cq_v4_parent_lesson(p_chapter_uuid uuid)
RETURNS TABLE(questions jsonb, answer_key jsonb, vocabulary jsonb, writing_prompt text, speaking_prompt text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT a.questions,COALESCE(r.answer_key,'[]'::jsonb),a.vocabulary,a.writing_prompt,a.speaking_prompt
 FROM public.cq_v4_pdf_chapters c
 JOIN public.cq_v4_activities a ON a.chapter_uuid=c.chapter_id AND a.published_at IS NOT NULL
 LEFT JOIN public.cq_v4_approval_requests r ON r.id=a.approval_id AND r.chapter_uuid=c.chapter_id AND r.parent_user_id=v_uid
 WHERE c.chapter_id=p_chapter_uuid AND c.parent_user_id=v_uid;
END;
$function$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_lesson(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_lesson(uuid) TO authenticated;
COMMENT ON FUNCTION public.cq_v4_parent_lesson(uuid) IS 'Parent-only published lesson context; requires admin role and exact chapter ownership.';
