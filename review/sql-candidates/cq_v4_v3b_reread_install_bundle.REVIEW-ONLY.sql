-- REVIEW ONLY: single transaction V3B install candidate. DO NOT EXECUTE ON PRODUCTION WITHOUT APPROVAL.
-- Run only after live schema drift, permissions, restore-capable backup, and CI checks pass.
BEGIN;

-- ===== review/sql-candidates/cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql =====
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
DROP TRIGGER IF EXISTS cq_v4_snapshot_immutable_guard ON public.cq_v4_immutable_grading_snapshots;
CREATE TRIGGER cq_v4_snapshot_immutable_guard BEFORE UPDATE OR DELETE ON public.cq_v4_immutable_grading_snapshots
FOR EACH ROW EXECUTE FUNCTION public.cq_v4_reject_snapshot_mutation();


-- ===== review/sql-candidates/cq_v4_reread_parent_gate_v3b.REVIEW-ONLY.sql =====
-- REVIEW ONLY. V3B-safe parent gate and student completion/status.
-- Deliberately excludes legacy mutable-key trigger. Requires existing V3B submission schema.
-- Install as part of an approved transactional migration with immutable snapshot helper.
create table if not exists public.cq_v4_reread_progress (
  chapter_uuid uuid not null,
  child_user_id uuid not null,
  required boolean not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (chapter_uuid, child_user_id),
  constraint cq_v4_reread_submission_fk
    foreign key (chapter_uuid, child_user_id)
    references public.cq_v4_student_submissions(chapter_uuid, child_user_id)
    on delete restrict,
  constraint cq_v4_reread_completion_valid
    check (completed_at is null or required)
);
alter table public.cq_v4_reread_progress enable row level security;
revoke all on public.cq_v4_reread_progress from public, anon, authenticated;
-- No client direct INSERT/UPDATE/DELETE. Only the RPC below can mark completion.
create or replace function public.cq_v4_complete_reread(p_chapter_uuid uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Login required' using errcode='28000';
  end if;
  update public.cq_v4_reread_progress r
     set completed_at=coalesce(r.completed_at,now())
   where r.chapter_uuid=p_chapter_uuid
     and r.child_user_id=v_uid
     and r.required=true;
  if not found then
    raise exception 'No authorized pending reread' using errcode='42501';
  end if;
  return true;
end;
$function$;
revoke all on function public.cq_v4_complete_reread(uuid) from public, anon;
grant execute on function public.cq_v4_complete_reread(uuid) to authenticated;
create or replace function public.cq_v4_my_reread_status(p_chapter_uuid uuid)
returns table(required boolean, completed boolean)
language sql security definer set search_path = ''
as $function$
  select r.required, r.completed_at is not null
    from public.cq_v4_reread_progress r
   where r.chapter_uuid=p_chapter_uuid
     and r.child_user_id=auth.uid()
     and auth.uid() is not null
$function$;
revoke all on function public.cq_v4_my_reread_status(uuid) from public, anon;
grant execute on function public.cq_v4_my_reread_status(uuid) to authenticated;

-- Parent feedback gate. Existing historical submissions have no progress row and
-- remain unaffected. Preserve the original authorization and validation checks.
create or replace function public.cq_v4_release_feedback(
  p_child_user_id uuid, p_chapter_uuid uuid, p_feedback text, p_release boolean
) returns boolean
language plpgsql security definer set search_path=''
as $function$
declare v_count integer;
begin
 if not public.cq_is_admin() then
   raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if auth.uid() is null then
   raise exception 'Login required' using errcode='28000';
 end if;
 if p_feedback is null or pg_catalog.octet_length(p_feedback)>20000 then
   raise exception 'Invalid feedback' using errcode='22023';
 end if;
 if p_release is null or (p_release and pg_catalog.length(pg_catalog.btrim(p_feedback))=0) then
   raise exception 'Feedback required for release' using errcode='22023';
 end if;
 -- Parent feedback entry AND release must wait for required rereading.
 -- Historical submissions without a progress row retain their original behavior.
 if exists(
   select 1 from public.cq_v4_reread_progress r
    where r.chapter_uuid=p_chapter_uuid
      and r.child_user_id=p_child_user_id
      and r.required=true
      and r.completed_at is null
 ) then
   raise exception 'Reread must be completed before parent feedback' using errcode='23514';
 end if;
 update public.cq_v4_student_submissions s
    set feedback=p_feedback, feedback_released=p_release
   from public.cq_v4_pdf_chapters c
   join public.cq_v4_pdf_assignments a on a.chapter_id=c.chapter_id
   join public.cq_v4_pdf_enrollments e
     on e.parent_user_id=c.parent_user_id and e.student_user_id=a.student_user_id
  where s.chapter_uuid=p_chapter_uuid and s.child_user_id=p_child_user_id
    and c.chapter_id=s.chapter_uuid and c.parent_user_id=auth.uid()
    and a.student_user_id=s.child_user_id;
 get diagnostics v_count = row_count;
 if v_count<>1 then
   raise exception 'Submission not found or access denied' using errcode='42501';
 end if;
 return true;
end;
$function$;
-- No changes to existing function EXECUTE grants.
-- Review and test against the actual V3B schema before deployment.

-- Parent-only status (no answer keys or scores in the student-facing RPC).
create or replace function public.cq_v4_parent_reread_progress()
returns table(chapter_uuid uuid, student_user_id uuid, required boolean, completed_at timestamptz)
language plpgsql security definer set search_path=''
as $function$
begin
 if auth.uid() is null or not public.cq_is_admin() then
   raise exception 'Parent authorization required' using errcode='42501';
 end if;
 return query
 select r.chapter_uuid,r.child_user_id,r.required,r.completed_at
 from public.cq_v4_reread_progress r
 join public.cq_v4_pdf_chapters c on c.chapter_id=r.chapter_uuid
 join public.cq_v4_pdf_assignments a on a.chapter_id=c.chapter_id and a.student_user_id=r.child_user_id
 join public.cq_v4_pdf_enrollments e on e.parent_user_id=c.parent_user_id and e.student_user_id=r.child_user_id
 where c.parent_user_id=auth.uid()
 order by r.created_at desc;
end;
$function$;
revoke all on function public.cq_v4_parent_reread_progress() from public,anon;
grant execute on function public.cq_v4_parent_reread_progress() to authenticated;


-- ===== review/sql-candidates/cq_v4_frozen_reread_atomic.REVIEW-ONLY.sql =====
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


-- ===== review/sql-candidates/cq_v4_disable_legacy_reread_trigger.REVIEW-ONLY.sql =====
-- REVIEW ONLY. Run only in disposable PostgreSQL test databases.
-- Installation order: approval schema, reread progress table + completion RPC,
-- immutable snapshot schema, frozen reread helper, then submit RPC overlay.
-- Legacy AFTER INSERT scoring reads mutable approval requests and MUST NOT coexist.
DROP TRIGGER IF EXISTS cq_v4_reread_after_submit ON public.cq_v4_student_submissions;
DO $guard$
BEGIN
 IF EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='cq_v4_student_submissions'
    AND t.tgname='cq_v4_reread_after_submit' AND NOT t.tgisinternal
 ) THEN RAISE EXCEPTION 'Legacy mutable-key reread trigger still enabled'; END IF;
END $guard$;
-- Keep the legacy trigger function defined for rollback reference, but do not
-- re-enable it while cq_v4_submit_answers uses frozen snapshot grading.


-- ===== review/sql-candidates/cq_v4_submit_v3b_minimal_reread.REVIEW-ONLY.sql =====
-- REVIEW ONLY: derived from live V3B function; no production changes authorized.
-- Preserves production release/assignment/audio/validation checks and idempotency.
-- Requires immutable snapshot, reread progress and frozen grading helper.
CREATE OR REPLACE FUNCTION public.cq_v4_submit_answers(p_chapter_uuid uuid, p_answers jsonb)
 RETURNS TABLE(chapter_uuid uuid, submitted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_uid uuid := auth.uid(); v_questions jsonb; v_question jsonb; v_answer jsonb; v_index integer; v_value text; v_number numeric; v_snapshot_ready boolean := false; v_inserted integer := 0;
BEGIN
 IF v_uid IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='28000'; END IF;
 IF NOT public.cq_v4_is_released(p_chapter_uuid,v_uid) THEN RAISE EXCEPTION 'Lesson not released by parent' USING ERRCODE='42501'; END IF;
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
 -- Only matched approved answer keys are eligible for automatic grading.
 SELECT EXISTS (
  SELECT 1 FROM public.cq_v4_activities act
  JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=act.chapter_uuid
  JOIN public.cq_v4_approval_requests req
    ON req.id=act.approval_id AND req.chapter_uuid=act.chapter_uuid
   AND req.parent_user_id=c.parent_user_id
   AND req.content_hash=act.approval_hash AND req.questions=act.questions
  WHERE act.chapter_uuid=p_chapter_uuid AND act.published_at IS NOT NULL
    AND act.approval_hash IS NOT NULL AND jsonb_typeof(req.answer_key)='array'
    AND jsonb_array_length(req.answer_key)=jsonb_array_length(act.questions)
 ) INTO v_snapshot_ready;
 INSERT INTO public.cq_v4_student_submissions(chapter_uuid,child_user_id,answers)
 VALUES(p_chapter_uuid,v_uid,p_answers)
 ON CONFLICT DO NOTHING;
 GET DIAGNOSTICS v_inserted = ROW_COUNT;
 IF v_inserted=1 AND v_snapshot_ready THEN
   IF NOT public.cq_v4_capture_grading_snapshot_internal(v_uid,p_chapter_uuid) THEN
     RAISE EXCEPTION 'Immutable grading snapshot capture failed' USING ERRCODE='22023';
   END IF;
   IF NOT public.cq_v4_record_frozen_reread_internal(v_uid,p_chapter_uuid) THEN
     RAISE EXCEPTION 'Frozen reread decision failed' USING ERRCODE='22023';
   END IF;
 END IF;
 -- Existing submission is immutable. The caller can fetch the authoritative record.
 RETURN QUERY SELECT s.chapter_uuid,s.submitted_at FROM public.cq_v4_student_submissions s
 WHERE s.chapter_uuid=p_chapter_uuid AND s.child_user_id=v_uid;
END; $function$



-- Do not expose immutable answer keys or private scoring helpers.
REVOKE ALL ON public.cq_v4_immutable_grading_snapshots FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.cq_v4_reread_progress FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.cq_v4_capture_grading_snapshot_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.cq_v4_record_frozen_reread_internal(uuid,uuid) FROM PUBLIC,anon,authenticated;
COMMIT;
