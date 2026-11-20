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
-- A subsequent migration must populate required using immutable server-side
-- answer keys and a parent-approved threshold. Never expose answer keys/scores.
-- A subsequent migration must guard feedback release for NEW submissions only.
