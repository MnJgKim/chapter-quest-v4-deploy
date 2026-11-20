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
