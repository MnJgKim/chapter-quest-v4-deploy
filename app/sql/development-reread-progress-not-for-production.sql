-- DEVELOPMENT ONLY. Do not apply to production without separate approval.
-- Stores reread completion separately from immutable submissions/snapshots.
-- Server scoring and threshold integration are intentionally not enabled by this migration.
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
   where act.chapter_uuid=new.chapter_uuid
     and act.published_at is not null;
  -- Fail closed on inconsistent approval data: do not claim a pass.
  if jsonb_typeof(v_questions) is distinct from 'array'
     or jsonb_typeof(v_key) is distinct from 'array'
     or jsonb_typeof(v_answers) is distinct from 'array'
     or jsonb_array_length(v_questions)<>jsonb_array_length(v_key)
     or jsonb_array_length(v_questions)<>jsonb_array_length(v_answers) then
    raise exception 'Approved answer key unavailable for scoring' using errcode='22023';
  end if;
  for v_i in 0..jsonb_array_length(v_questions)-1 loop
    v_q:=v_questions->v_i;
    if v_q->>'kind' <> 'mc' then continue; end if;
    v_expected:=v_key->v_i;
    v_actual:=v_answers->>v_i;
    if jsonb_typeof(v_expected)<>'number'
       or (v_expected #>> '{}') !~ '^(0|[1-9][0-9]*)$'
       or jsonb_typeof(v_q->'options')<>'array'
       or (v_expected #>> '{}')::integer >= jsonb_array_length(v_q->'options')
       or v_actual !~ '^(0|[1-9][0-9]*)$' then
      raise exception 'Invalid approved multiple-choice answer key' using errcode='22023';
    end if;
    v_total:=v_total+1;
    if v_actual=(v_expected #>> '{}') then v_correct:=v_correct+1; end if;
  end loop;
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
-- IMPORTANT: the feedback-release RPC must separately enforce:
-- IF EXISTS (SELECT 1 FROM cq_v4_reread_progress WHERE required
-- AND completed_at IS NULL AND chapter_uuid=p_chapter_uuid
-- AND child_user_id=p_child_user_id) AND p_release THEN RAISE EXCEPTION ...;
-- Do not apply this file until that guard, parent inbox, and UI are tested.
