-- DEVELOPMENT REVIEW CANDIDATE ONLY. Never execute against production without separate approval.
-- Install app/sql/development-reread-publish-validation-not-for-production.sql first.
-- Based on app/server-review/fixtures/current-functions.sql; exact production function must be re-audited.
-- This candidate rejects answer-key mismatches and changed published payloads before any write.
CREATE OR REPLACE FUNCTION public.cq_v4_publish_approved(p_approval_id uuid, p_children uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_r public.cq_v4_approval_requests%ROWTYPE;
        v_chapter public.cq_v4_pdf_chapters%ROWTYPE; v_current public.cq_v4_activities%ROWTYPE; v_activity_found boolean:=false;
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF p_approval_id IS NULL OR p_children IS NULL OR pg_catalog.cardinality(p_children) NOT BETWEEN 1 AND 30
 OR EXISTS(SELECT 1 FROM pg_catalog.unnest(p_children) AS x(uid) WHERE x.uid IS NULL)
 OR (SELECT pg_catalog.count(DISTINCT uid) FROM pg_catalog.unnest(p_children) AS x(uid))<>pg_catalog.cardinality(p_children)
 THEN RAISE EXCEPTION 'Invalid child list' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_r FROM public.cq_v4_approval_requests
 WHERE id=p_approval_id AND parent_user_id=v_uid FOR UPDATE;
 IF NOT FOUND OR v_r.chapter_uuid IS NULL THEN RAISE EXCEPTION 'Approval and PDF binding required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_chapter FROM public.cq_v4_pdf_chapters
 WHERE chapter_id=v_r.chapter_uuid AND parent_user_id=v_uid AND pdf_ready IS TRUE
 AND pdf_verified_at IS NOT NULL AND NULLIF(pg_catalog.btrim(storage_path),'') IS NOT NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Verified PDF missing' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.unnest(p_children) AS x(uid) WHERE NOT EXISTS(
 SELECT 1 FROM public.cq_v4_pdf_enrollments e WHERE e.parent_user_id=v_uid AND e.student_user_id=x.uid))
 THEN RAISE EXCEPTION 'Student enrollment missing' USING ERRCODE='42501'; END IF;
 -- Enforce approved answer-key validity in the same publication transaction.
 PERFORM public.cq_v4_assert_reread_publishable(p_approval_id);
 SELECT * INTO v_current FROM public.cq_v4_activities WHERE chapter_uuid=v_r.chapter_uuid FOR UPDATE;
 v_activity_found:=FOUND;
 IF v_activity_found AND v_current.published_at IS NOT NULL AND
 (v_current.approval_id IS DISTINCT FROM p_approval_id OR v_current.approval_hash IS DISTINCT FROM v_r.content_hash
 OR v_current.questions IS DISTINCT FROM v_r.questions
 OR v_current.vocabulary IS DISTINCT FROM v_r.vocabulary
 OR v_current.writing_prompt IS DISTINCT FROM v_r.writing_prompt
 OR v_current.speaking_prompt IS DISTINCT FROM v_r.speaking_prompt)
 THEN RAISE EXCEPTION 'Published content is immutable' USING ERRCODE='23505'; END IF;
 IF EXISTS(SELECT 1 FROM public.cq_v4_student_submissions s WHERE s.chapter_uuid=v_r.chapter_uuid)
 AND (NOT v_activity_found OR v_current.approval_hash IS DISTINCT FROM v_r.content_hash)
 THEN RAISE EXCEPTION 'Cannot change content after submissions' USING ERRCODE='23505'; END IF;
 INSERT INTO public.cq_v4_activities(chapter_uuid,questions,vocabulary,writing_prompt,speaking_prompt,published_at,approval_id,approval_hash)
 VALUES(v_r.chapter_uuid,v_r.questions,v_r.vocabulary,v_r.writing_prompt,v_r.speaking_prompt,now(),p_approval_id,v_r.content_hash)
 ON CONFLICT(chapter_uuid) DO UPDATE SET
 questions=EXCLUDED.questions,vocabulary=EXCLUDED.vocabulary,
 writing_prompt=EXCLUDED.writing_prompt,speaking_prompt=EXCLUDED.speaking_prompt,
 published_at=COALESCE(public.cq_v4_activities.published_at,EXCLUDED.published_at),
 approval_id=EXCLUDED.approval_id,approval_hash=EXCLUDED.approval_hash;
 INSERT INTO public.cq_v4_pdf_assignments(chapter_id,student_user_id)
 SELECT v_r.chapter_uuid, x.uid FROM pg_catalog.unnest(p_children) AS x(uid)
 ON CONFLICT DO NOTHING;
 RETURN v_r.chapter_uuid;
END;
$function$;

