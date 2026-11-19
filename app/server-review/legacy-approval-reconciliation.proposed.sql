-- Development-only proposal. DO NOT apply to production without explicit deployment approval.
-- Repair a legacy publication only after the parent genuinely reapproves the EXACT published payload.
-- Requires an already registered approval request with an answer key and verified PDF binding.
-- A new approval is a NEW attestation, never presented as an historical approval.
CREATE OR REPLACE FUNCTION public.cq_v4_reconcile_legacy_approval(
  p_chapter uuid, p_approval uuid, p_expected_questions jsonb,
  p_expected_vocabulary jsonb, p_expected_writing text, p_expected_speaking text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
 v_uid uuid := auth.uid();
 v_c public.cq_v4_pdf_chapters%ROWTYPE;
 v_a public.cq_v4_activities%ROWTYPE;
 v_r public.cq_v4_approval_requests%ROWTYPE;
 v_expected_hash text;
BEGIN
 IF v_uid IS NULL OR NOT public.cq_is_admin() THEN
  RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501';
 END IF;
 IF p_chapter IS DISTINCT FROM 'cda5aa92-39e5-4286-9595-5d80ca779b8f'::uuid THEN
  RAISE EXCEPTION 'Legacy recovery is restricted to the reviewed chapter' USING ERRCODE='42501';
 END IF;
 SELECT * INTO STRICT v_c FROM public.cq_v4_pdf_chapters
 WHERE chapter_id=p_chapter AND parent_user_id=v_uid AND pdf_ready IS TRUE
 AND pdf_verified_at IS NOT NULL AND nullif(btrim(storage_path),'') IS NOT NULL;
 SELECT * INTO STRICT v_a FROM public.cq_v4_activities WHERE chapter_uuid=p_chapter FOR UPDATE;
 IF v_a.published_at IS NULL OR jsonb_array_length(v_a.questions)<>10 THEN
  RAISE EXCEPTION 'Expected legacy published chapter is missing' USING ERRCODE='23505';
 END IF;
 IF v_a.questions IS DISTINCT FROM p_expected_questions OR
    v_a.vocabulary IS DISTINCT FROM p_expected_vocabulary OR
    v_a.writing_prompt IS DISTINCT FROM p_expected_writing OR
    v_a.speaking_prompt IS DISTINCT FROM p_expected_speaking THEN
  RAISE EXCEPTION 'Published payload changed; reapproval is invalid' USING ERRCODE='23505';
 END IF;
 SELECT * INTO STRICT v_r FROM public.cq_v4_approval_requests
 WHERE id=p_approval AND parent_user_id=v_uid AND chapter_uuid=p_chapter FOR UPDATE;
 IF v_r.questions IS DISTINCT FROM v_a.questions OR
    v_r.vocabulary IS DISTINCT FROM v_a.vocabulary OR
    v_r.writing_prompt IS DISTINCT FROM v_a.writing_prompt OR
    v_r.speaking_prompt IS DISTINCT FROM v_a.speaking_prompt OR
    jsonb_typeof(v_r.answer_key)<>'array' OR
    jsonb_array_length(v_r.answer_key)<>10 OR
    EXISTS(SELECT 1 FROM jsonb_array_elements(v_r.answer_key) AS ans WHERE ans='null'::jsonb) THEN
  RAISE EXCEPTION 'Approval content or answer key does not match published chapter' USING ERRCODE='23505';
 END IF;
 v_expected_hash:=md5(jsonb_build_array(v_r.book_local_id,v_r.chapter_local_id,v_r.title,
    v_r.source_text,v_r.questions,v_r.answer_key,v_r.vocabulary,v_r.writing_prompt,v_r.speaking_prompt)::text);
 IF v_expected_hash IS DISTINCT FROM v_r.content_hash THEN
  RAISE EXCEPTION 'Approval content hash mismatch' USING ERRCODE='23505';
 END IF;
 IF v_a.approval_id IS NOT NULL OR v_a.approval_hash IS NOT NULL THEN
  IF v_a.approval_id=p_approval AND v_a.approval_hash=v_r.content_hash THEN RETURN p_chapter; END IF;
  RAISE EXCEPTION 'Already bound to a different approval' USING ERRCODE='23505';
 END IF;
 -- No questions, prompts, published_at, submissions, snapshots, assignments or schedule are changed.
 UPDATE public.cq_v4_activities
 SET approval_id=p_approval, approval_hash=v_r.content_hash
 WHERE chapter_uuid=p_chapter AND approval_id IS NULL AND approval_hash IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Concurrent binding detected' USING ERRCODE='40001'; END IF;
 RETURN p_chapter;
END $$;
REVOKE ALL ON FUNCTION public.cq_v4_reconcile_legacy_approval(uuid,uuid,jsonb,jsonb,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_reconcile_legacy_approval(uuid,uuid,jsonb,jsonb,text,text) TO authenticated;
