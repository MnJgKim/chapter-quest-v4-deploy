CREATE OR REPLACE FUNCTION public.cq_v4_approve_child(p_child_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_invite_id uuid;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF p_child_user_id IS NULL OR p_child_user_id=v_uid THEN RETURN false; END IF;
 -- Serialize concurrent approval and revocation for this exact parent/child pair.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text || ':' || p_child_user_id::text, 927542));
 SELECT invite_id INTO v_invite_id FROM public.cq_v4_invites
 WHERE parent_user_id=v_uid AND claimed_by=p_child_user_id AND claimed_at IS NOT NULL
   AND revoked_at IS NULL AND approved_at IS NULL
 ORDER BY claimed_at DESC LIMIT 1 FOR UPDATE;
 IF v_invite_id IS NULL THEN RETURN false; END IF;
 INSERT INTO public.cq_v4_pdf_enrollments(parent_user_id,student_user_id)
 VALUES(v_uid,p_child_user_id) ON CONFLICT DO NOTHING;
 UPDATE public.cq_v4_invites SET approved_at=now(),revoked_at=NULL WHERE invite_id=v_invite_id;
 RETURN true;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_bind_verified_pdf(p_approval_id uuid, p_chapter_uuid uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_existing uuid;
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF p_approval_id IS NULL OR p_chapter_uuid IS NULL THEN RAISE EXCEPTION 'Missing identifier' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.cq_v4_pdf_chapters c WHERE c.chapter_id=p_chapter_uuid
     AND c.parent_user_id=v_uid AND c.pdf_ready IS TRUE AND c.pdf_verified_at IS NOT NULL
     AND NULLIF(pg_catalog.btrim(c.storage_path),'') IS NOT NULL)
 THEN RAISE EXCEPTION 'Verified owned PDF required' USING ERRCODE='42501'; END IF;
 SELECT chapter_uuid INTO v_existing FROM public.cq_v4_approval_requests
 WHERE id=p_approval_id AND parent_user_id=v_uid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Approval not owned' USING ERRCODE='42501'; END IF;
 IF v_existing IS NOT NULL AND v_existing<>p_chapter_uuid
 THEN RAISE EXCEPTION 'Approval already bound to another chapter' USING ERRCODE='23505'; END IF;
 IF EXISTS (SELECT 1 FROM public.cq_v4_approval_requests r WHERE r.chapter_uuid=p_chapter_uuid AND r.id<>p_approval_id)
 THEN RAISE EXCEPTION 'Chapter already bound to another approval' USING ERRCODE='23505'; END IF;
 UPDATE public.cq_v4_approval_requests SET chapter_uuid=p_chapter_uuid
 WHERE id=p_approval_id AND parent_user_id=v_uid;
 RETURN p_chapter_uuid;
END $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_can_read_assignment(p_chapter uuid, p_student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_student = (select auth.uid()) and exists (
    select 1 from public.cq_v4_pdf_chapters c
    join public.cq_v4_pdf_enrollments e
      on e.parent_user_id = c.parent_user_id
     and e.student_user_id = p_student
    where c.chapter_id = p_chapter and c.pdf_ready = true
  );
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_claim_invite(p_token text, p_student_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_rows integer;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF public.cq_is_admin() THEN RAISE EXCEPTION 'Parent accounts cannot claim invitations' USING ERRCODE='42501'; END IF;
 -- Bearer-token invitation: student role is NOT inferred from cq_is_student(student_id), which uses legacy student IDs.
 -- The requesting Auth user is not enrolled until the parent explicitly approves.
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{48}$' OR
    p_student_name IS NULL OR length(pg_catalog.btrim(p_student_name)) NOT BETWEEN 1 AND 80
 THEN RAISE EXCEPTION 'Invalid invitation or name' USING ERRCODE='22023'; END IF;
 -- Serialize concurrent claims for this user and avoid racing on the partial unique index.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 927543));
 -- An enrolled child must be revoked before they can claim a fresh invitation.
 -- Avoid a unique-index error if this child already has a pending claim.
 IF EXISTS (
   SELECT 1 FROM public.cq_v4_invites i
   JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=i.parent_user_id
   WHERE i.token_hash=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token,'UTF8')),'hex')
     AND e.student_user_id=v_uid
 ) OR EXISTS (
   SELECT 1 FROM public.cq_v4_invites i
   JOIN public.cq_v4_invites pending ON pending.parent_user_id=i.parent_user_id
   WHERE i.token_hash=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token,'UTF8')),'hex')
     AND pending.claimed_by=v_uid AND pending.approved_at IS NULL AND pending.revoked_at IS NULL
 ) THEN RETURN false; END IF;
 -- Concurrent claims for different tokens can race on the one-pending-child unique index.
 -- Catch only unique_violation locally so the RPC returns false rather than a raw DB error.
 BEGIN
   UPDATE public.cq_v4_invites SET claimed_by=v_uid,student_name=pg_catalog.btrim(p_student_name),claimed_at=now()
   WHERE token_hash=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_token,'UTF8')),'hex')
     AND claimed_by IS NULL AND revoked_at IS NULL AND expires_at>now()
     AND parent_user_id<>v_uid;
   GET DIAGNOSTICS v_rows=ROW_COUNT;
 EXCEPTION WHEN unique_violation THEN
   RETURN false;
 END;
 RETURN v_rows=1;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_issue_invite()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_token text;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 -- Serialize concurrent issuance by this parent so the active-invitation cap is atomic.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 927541));
 IF (SELECT count(*) FROM public.cq_v4_invites
     WHERE parent_user_id=v_uid AND claimed_by IS NULL AND revoked_at IS NULL AND expires_at>now()) >= 5
 THEN RAISE EXCEPTION 'Too many active invitations' USING ERRCODE='22023'; END IF;
 v_token:=pg_catalog.encode(extensions.gen_random_bytes(24),'hex');
 INSERT INTO public.cq_v4_invites(parent_user_id,token_hash,expires_at)
 VALUES(v_uid,pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_token,'UTF8')),'hex'),now()+interval '15 minutes');
 RETURN v_token;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_list_child_access()
 RETURNS TABLE(child_user_id uuid, student_name text, active boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 WITH linked AS (
   SELECT e.student_user_id AS uid
   FROM public.cq_v4_pdf_enrollments e
   WHERE e.parent_user_id=(SELECT auth.uid())
 ), pending AS (
   SELECT DISTINCT ON (i.claimed_by) i.claimed_by AS uid, i.student_name
   FROM public.cq_v4_invites i
   WHERE i.parent_user_id=(SELECT auth.uid()) AND i.claimed_by IS NOT NULL
     AND i.revoked_at IS NULL AND i.approved_at IS NULL
   ORDER BY i.claimed_by,i.claimed_at DESC NULLS LAST,i.created_at DESC
 ), names AS (
   SELECT DISTINCT ON (i.claimed_by) i.claimed_by AS uid, i.student_name
   FROM public.cq_v4_invites i
   WHERE i.parent_user_id=(SELECT auth.uid()) AND i.claimed_by IS NOT NULL
     AND i.student_name IS NOT NULL
   ORDER BY i.claimed_by,
     (i.approved_at IS NOT NULL) DESC,
     i.claimed_at DESC NULLS LAST,i.created_at DESC
 )
 SELECT ids.uid AS child_user_id,
        COALESCE(n.student_name,'연결된 학생')::text AS student_name,
        (l.uid IS NOT NULL) AS active
 FROM (SELECT uid FROM pending UNION SELECT uid FROM linked) ids
 LEFT JOIN names n ON n.uid=ids.uid
 LEFT JOIN linked l ON l.uid=ids.uid
 WHERE public.cq_is_admin();
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_chapter_activities(p_chapter_uuid uuid)
 RETURNS TABLE(vocabulary jsonb, writing_prompt text, speaking_prompt text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT act.vocabulary,act.writing_prompt,act.speaking_prompt
 FROM public.cq_v4_activities act
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=act.chapter_uuid
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
 WHERE act.chapter_uuid=p_chapter_uuid AND a.student_user_id=(SELECT auth.uid())
   AND act.published_at IS NOT NULL AND c.pdf_ready IS TRUE;
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_chapters()
 RETURNS TABLE(chapter_uuid uuid, chapter_title text, questions jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT c.chapter_id, c.title, act.questions
 FROM public.cq_v4_pdf_chapters c
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
 JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
 WHERE a.student_user_id=(SELECT auth.uid()) AND c.pdf_ready IS TRUE
 ORDER BY c.created_at,c.chapter_id;
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_submission(p_chapter_uuid uuid)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone, feedback text, feedback_released boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT s.chapter_uuid,s.submitted_at,
   CASE WHEN s.feedback_released THEN s.feedback ELSE NULL END,
   s.feedback_released
 FROM public.cq_v4_student_submissions s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id AND a.student_user_id=s.child_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=(SELECT auth.uid());
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_submissions()
 RETURNS TABLE(child_user_id uuid, chapter_uuid uuid, student_name text, chapter_title text, submitted_at timestamp with time zone, answers jsonb, feedback text, feedback_released boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT s.child_user_id, s.chapter_uuid,
         COALESCE(child_name.student_name, '연결된 학생')::text AS student_name,
         c.title AS chapter_title,
         s.submitted_at, s.answers, s.feedback, s.feedback_released
  FROM public.cq_v4_student_submissions s
  JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid
  JOIN public.cq_v4_pdf_assignments a
    ON a.chapter_id=s.chapter_uuid AND a.student_user_id=s.child_user_id
  JOIN public.cq_v4_pdf_enrollments e
    ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
  LEFT JOIN LATERAL (
    SELECT i.student_name
    FROM public.cq_v4_invites i
    WHERE i.parent_user_id=c.parent_user_id
      AND i.claimed_by=s.child_user_id
      AND i.approved_at IS NOT NULL
      AND i.revoked_at IS NULL
      AND i.student_name IS NOT NULL
    ORDER BY i.approved_at DESC, i.created_at DESC
    LIMIT 1
  ) child_name ON true
  WHERE c.parent_user_id=(SELECT auth.uid()) AND public.cq_is_admin()
  ORDER BY s.submitted_at DESC;
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_publication_status(p_approval_id uuid, p_children uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_chapter uuid; v_match boolean:=false; v_missing uuid[];
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF p_approval_id IS NULL OR p_children IS NULL OR pg_catalog.cardinality(p_children) NOT BETWEEN 1 AND 30
 OR EXISTS(SELECT 1 FROM pg_catalog.unnest(p_children) AS x(uid) WHERE x.uid IS NULL)
 OR (SELECT pg_catalog.count(DISTINCT uid) FROM pg_catalog.unnest(p_children) AS x(uid))<>pg_catalog.cardinality(p_children)
 THEN RAISE EXCEPTION 'Invalid child list' USING ERRCODE='22023'; END IF;
 SELECT r.chapter_uuid INTO v_chapter FROM public.cq_v4_approval_requests r
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=r.chapter_uuid
 JOIN public.cq_v4_activities a ON a.chapter_uuid=c.chapter_id
 WHERE r.id=p_approval_id AND r.parent_user_id=v_uid AND c.parent_user_id=v_uid
 AND c.pdf_ready IS TRUE AND c.pdf_verified_at IS NOT NULL
 AND a.published_at IS NOT NULL AND a.approval_id=r.id AND a.approval_hash=r.content_hash
 AND a.questions=r.questions AND a.vocabulary=r.vocabulary
 AND a.writing_prompt=r.writing_prompt AND a.speaking_prompt=r.speaking_prompt;
 v_match:=FOUND;
 SELECT pg_catalog.array_agg(x.uid ORDER BY x.uid) INTO v_missing
 FROM pg_catalog.unnest(p_children) AS x(uid)
 WHERE NOT v_match OR NOT EXISTS (
 SELECT 1 FROM public.cq_v4_pdf_assignments a
 JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id=a.student_user_id
 WHERE a.chapter_id=v_chapter AND a.student_user_id=x.uid AND e.parent_user_id=v_uid);
 RETURN pg_catalog.jsonb_build_object('content_matches',v_match,'all_assigned',v_missing IS NULL,
 'missing_children',COALESCE(pg_catalog.to_jsonb(v_missing),'[]'::jsonb),'chapter_uuid',v_chapter);
END $function$;

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
 SELECT * INTO v_current FROM public.cq_v4_activities WHERE chapter_uuid=v_r.chapter_uuid FOR UPDATE;
 v_activity_found:=FOUND;
 IF v_activity_found AND v_current.published_at IS NOT NULL AND
 (v_current.approval_id IS DISTINCT FROM p_approval_id OR v_current.approval_hash IS DISTINCT FROM v_r.content_hash)
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
END $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_register_approval_once(p_request_key uuid, p_book_id text, p_chapter_id text, p_title text, p_source text, p_questions jsonb, p_answer_key jsonb, p_vocabulary jsonb, p_writing_prompt text, p_speaking_prompt text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_hash text; v_id uuid; v_saved_hash text;
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='28000'; END IF;
 IF p_request_key IS NULL OR pg_catalog.length(pg_catalog.btrim(coalesce(p_title,'')))=0
 OR pg_catalog.length(p_title)>200 OR pg_catalog.length(pg_catalog.btrim(coalesce(p_source,'')))=0
 OR p_questions IS NULL OR jsonb_typeof(p_questions)<>'array' OR jsonb_array_length(p_questions)=0
 OR p_answer_key IS NULL OR jsonb_typeof(p_answer_key)<>'array'
 OR jsonb_array_length(p_questions)<>jsonb_array_length(p_answer_key)
 OR p_vocabulary IS NULL OR jsonb_typeof(p_vocabulary)<>'array'
 OR p_book_id IS NULL OR p_chapter_id IS NULL
 OR pg_catalog.octet_length(p_source)>1048576 THEN
 RAISE EXCEPTION 'Invalid publication payload' USING ERRCODE='22023'; END IF;
 v_hash:=pg_catalog.md5(pg_catalog.jsonb_build_array(p_book_id,p_chapter_id,p_title,p_source,p_questions,p_answer_key,p_vocabulary,p_writing_prompt,p_speaking_prompt)::text);
 INSERT INTO public.cq_v4_approval_requests(parent_user_id,request_key,book_local_id,chapter_local_id,title,source_text,questions,answer_key,vocabulary,writing_prompt,speaking_prompt,content_hash)
 VALUES(v_uid,p_request_key,p_book_id,p_chapter_id,p_title,p_source,p_questions,p_answer_key,p_vocabulary,coalesce(p_writing_prompt,''),coalesce(p_speaking_prompt,''),v_hash)
 ON CONFLICT(parent_user_id,request_key) DO NOTHING;
 SELECT id,content_hash INTO v_id,v_saved_hash FROM public.cq_v4_approval_requests
 WHERE parent_user_id=v_uid AND request_key=p_request_key;
 IF v_saved_hash IS DISTINCT FROM v_hash THEN
 RAISE EXCEPTION 'Approval request key reused for different content' USING ERRCODE='23505'; END IF;
 RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_release_feedback(p_child_user_id uuid, p_chapter_uuid uuid, p_feedback text, p_release boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_count integer;
BEGIN
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF auth.uid() IS NULL THEN
   RAISE EXCEPTION 'Login required' USING ERRCODE='28000';
 END IF;
 IF p_feedback IS NULL OR pg_catalog.octet_length(p_feedback)>20000 THEN
   RAISE EXCEPTION 'Invalid feedback' USING ERRCODE='22023';
 END IF;
 IF p_release IS NULL OR (p_release AND pg_catalog.length(pg_catalog.btrim(p_feedback))=0) THEN
   RAISE EXCEPTION 'Feedback required for release' USING ERRCODE='22023';
 END IF;
 UPDATE public.cq_v4_student_submissions s
 SET feedback=p_feedback, feedback_released=p_release
 FROM public.cq_v4_pdf_chapters c
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
 JOIN public.cq_v4_pdf_enrollments e
   ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=p_child_user_id
   AND c.chapter_id=s.chapter_uuid AND c.parent_user_id=auth.uid()
   AND a.student_user_id=s.child_user_id;
 GET DIAGNOSTICS v_count = ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'Submission not found or access denied' USING ERRCODE='42501'; END IF;
 RETURN true;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_revoke_child(p_child_user_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid:=auth.uid(); v_count integer;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='28000'; END IF;
 IF NOT public.cq_is_admin() THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 IF p_child_user_id IS NULL OR p_child_user_id=v_uid THEN RETURN false; END IF;
 -- Serialize concurrent approval and revocation for this exact parent/child pair.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text || ':' || p_child_user_id::text, 927542));
 -- Confirmed FK audit: enrollment references auth.users; no dependent FK targets enrollment.
 -- Revocation intentionally preserves student submissions and other learning records.
 DELETE FROM public.cq_v4_pdf_enrollments
 WHERE parent_user_id=v_uid AND student_user_id=p_child_user_id;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 UPDATE public.cq_v4_invites SET revoked_at=now()
 WHERE parent_user_id=v_uid AND claimed_by=p_child_user_id AND revoked_at IS NULL;
 RETURN v_count>0;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_questions jsonb; v_question jsonb; v_answer jsonb; v_index integer; v_value text; v_number numeric;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='28000'; END IF;
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
 -- Existing submission is immutable. The caller can fetch the authoritative record.
 RETURN QUERY SELECT s.chapter_uuid,s.submitted_at FROM public.cq_v4_student_submissions s
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=v_uid;
END; $function$;

CREATE OR REPLACE FUNCTION public.cq_v4_sync_legacy_device()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old_parent uuid;
begin
  if TG_OP = 'DELETE' then
    delete from public.cq_v4_pdf_enrollments
    where student_user_id = OLD.auth_user_id;
    return OLD;
  end if;
  -- Revoke old mapping whenever the device's identity, approval or status changes.
  delete from public.cq_v4_pdf_enrollments
  where student_user_id = NEW.auth_user_id;
  if TG_OP = 'UPDATE' and OLD.auth_user_id is distinct from NEW.auth_user_id then
    delete from public.cq_v4_pdf_enrollments
    where student_user_id = OLD.auth_user_id;
  end if;
  if NEW.revoked_at is null and exists (
    select 1 from public.cq_admins a where a.user_id = NEW.approved_by
  ) and NEW.approved_by <> NEW.auth_user_id then
    insert into public.cq_v4_pdf_enrollments(parent_user_id, student_user_id)
    values (NEW.approved_by, NEW.auth_user_id)
    on conflict (parent_user_id, student_user_id) do nothing;
  end if;
  return NEW;
end;
$function$;