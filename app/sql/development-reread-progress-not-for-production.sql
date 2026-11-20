-- DEVELOPMENT ONLY. Do not apply to production without separate approval.
-- Stores reread completion separately from immutable submissions/snapshots.
-- Draft includes scoring and feedback gating; NOT approved for production deployment.
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
-- Only newly inserted submissions are scored; historical submissions are untouched.
-- Use the approved, matching answer key and the server-published questions.
-- Threshold: below 70% correct MC answers means reread required.
create or replace function public.cq_v4_reread_on_submission()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare
  v_questions jsonb;
  v_key jsonb;
  v_answers jsonb := new.answers->'answers';
  v_total integer := 0;
  v_correct integer := 0;
  v_i integer;
  v_q jsonb;
  v_expected jsonb;
  v_actual text;
  v_required boolean := false;
begin
  select act.questions, req.answer_key
    into v_questions, v_key
    from public.cq_v4_activities act
    join public.cq_v4_approval_requests req
      on req.id=act.approval_id
     and req.chapter_uuid=act.chapter_uuid
     and req.content_hash=act.approval_hash
     and req.questions=act.questions
   where act.chapter_uuid=new.chapter_uuid
     and act.published_at is not null;
  -- Fail atomically: never accept a submission without an authoritative score.
  -- Deployment requires repairing legacy answer-key provenance first.
  if jsonb_typeof(v_questions) is distinct from 'array'
     or jsonb_typeof(v_key) is distinct from 'array'
     or jsonb_typeof(v_answers) is distinct from 'array' then
    raise exception 'Reread scoring data unavailable' using errcode='22023';
  end if;
  if jsonb_array_length(v_questions)<>jsonb_array_length(v_answers)
     or jsonb_array_length(v_questions)<>jsonb_array_length(v_key) then
    raise exception 'Reread scoring question/key count mismatch' using errcode='22023';
  end if;
  -- Non-MC answer keys may legitimately be absent. Validate each MC key below.
  -- Empty arrays have no MC denominator; avoid 0..-1 subscripts.
  if jsonb_array_length(v_questions)>0 then
    for v_i in 0..jsonb_array_length(v_questions)-1 loop
      v_q:=v_questions->v_i;
      if v_q->>'kind' <> 'mc' then continue; end if;
      v_expected:=v_key->v_i;
      v_actual:=v_answers->>v_i;
      if jsonb_typeof(v_q->'options') is distinct from 'array'
         or jsonb_array_length(v_q->'options') < 2 then
        raise exception 'Invalid multiple-choice options at index %',v_i using errcode='22023';
      end if;
      if jsonb_typeof(v_answers->v_i) is distinct from 'string'
         or v_actual !~ '^(0|[1-9][0-9]*)$'
         or pg_catalog.length(v_actual)>9
         or v_actual::integer >= jsonb_array_length(v_q->'options') then
        raise exception 'Missing or invalid multiple-choice response at index %',v_i using errcode='22023';
      end if;
      if jsonb_typeof(v_expected) is distinct from 'number'
         or (v_expected #>> '{}') !~ '^(0|[1-9][0-9]*)$'
         or pg_catalog.length(v_expected #>> '{}')>9
         or (v_expected #>> '{}')::integer >= jsonb_array_length(v_q->'options') then
        raise exception 'Invalid reread answer key at index %',v_i using errcode='22023';
      end if;
      v_total:=v_total+1;
      if v_actual=(v_expected #>> '{}') then v_correct:=v_correct+1; end if;
    end loop;
  end if;
  -- No MC questions: do not require reread; no denominator exists.
  if v_total>0 then v_required:=(v_correct*10<v_total*7); end if;
  insert into public.cq_v4_reread_progress(chapter_uuid,child_user_id,required)
  values(new.chapter_uuid,new.child_user_id,v_required)
  on conflict do nothing;
  return new;
end;
$function$;
revoke all on function public.cq_v4_reread_on_submission() from public,anon,authenticated;
drop trigger if exists cq_v4_reread_after_submit on public.cq_v4_student_submissions;
create trigger cq_v4_reread_after_submit
after insert on public.cq_v4_student_submissions
for each row execute function public.cq_v4_reread_on_submission();
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
 -- Restrict only newly scored submissions that require rereading.
 if p_release and exists(
   select 1 from public.cq_v4_reread_progress r
    where r.chapter_uuid=p_chapter_uuid
      and r.child_user_id=p_child_user_id
      and r.required=true
      and r.completed_at is null
 ) then
   raise exception 'Reread must be completed before feedback release' using errcode='23514';
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
-- DO NOT DEPLOY until isolated integration tests cover:
-- approved key validity, 70% threshold, completion, parent feedback gate,
-- historical submissions, recording uploads and submission atomicity.

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
