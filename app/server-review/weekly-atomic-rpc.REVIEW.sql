-- REVIEW ONLY. DO NOT APPLY TO PRODUCTION without backup and explicit approval.
-- Atomic batch scheduling: caller is authenticated parent admin.
-- Existing schedule rows are NEVER updated; released_at remains NULL.
create or replace function public.cq_v4_parent_schedule_week_atomic(
  p_student_user_id uuid, p_items jsonb
) returns integer
language plpgsql security definer set search_path = ''
as $$
declare
 v_parent uuid := auth.uid();
 v_item jsonb;
 v_chapter uuid;
 v_date date;
 v_count integer := 0;
begin
 if v_parent is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_student_user_id is null or p_items is null or jsonb_typeof(p_items)<>'array'
    or jsonb_array_length(p_items)>31 then
  raise exception 'Invalid schedule batch' using errcode='22023';
 end if;
 -- Serializes requests for this enrolled student, including concurrent batch calls.
 perform 1 from public.cq_v4_pdf_enrollments e
 where e.parent_user_id=v_parent and e.student_user_id=p_student_user_id
 for update;
 if not found then raise exception 'Student enrollment required' using errcode='42501'; end if;
 for v_item in select value from jsonb_array_elements(p_items)
 loop
  if jsonb_typeof(v_item)<>'object'
    or jsonb_typeof(v_item->'chapter_id')<>'string'
    or jsonb_typeof(v_item->'lesson_date')<>'string'
    or (v_item->>'chapter_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or (v_item->>'lesson_date') !~ '^\d{4}-\d{2}-\d{2}$'
  then raise exception 'Invalid batch item' using errcode='22023'; end if;
  v_chapter := (v_item->>'chapter_id')::uuid;
  v_date := (v_item->>'lesson_date')::date;
  if to_char(v_date,'YYYY-MM-DD')<>(v_item->>'lesson_date') then
   raise exception 'Invalid lesson date' using errcode='22023';
  end if;
  -- No silent overwrite of manual dates, previous chapters, or published schedules.
  if exists(select 1 from public.cq_v4_lesson_schedule s
            where s.student_user_id=p_student_user_id
              and (s.chapter_id=v_chapter or s.lesson_date=v_date)) then
   raise exception 'Schedule collision' using errcode='23505';
  end if;
  -- Approval evidence is checked against real DB records, never client booleans.
  if not exists (
   select 1 from public.cq_v4_pdf_chapters c
   join public.cq_v4_pdf_assignments pa on pa.chapter_id=c.chapter_id
     and pa.student_user_id=p_student_user_id
   join public.cq_v4_activities act on act.chapter_uuid=c.chapter_id
   join public.cq_v4_approval_requests ar on ar.id=act.approval_id
      and ar.parent_user_id=v_parent and ar.chapter_uuid=c.chapter_id
      and ar.content_hash=act.approval_hash
   where c.chapter_id=v_chapter and c.parent_user_id=v_parent
     and c.pdf_ready=true and c.pdf_verified_at is not null
     and act.published_at is not null
     and act.approval_hash ~ '^[0-9a-f]{64}$'
  ) then raise exception 'Unapproved or unassigned chapter' using errcode='42501'; end if;
  insert into public.cq_v4_lesson_schedule
    (student_user_id,chapter_id,lesson_date,timezone)
  values(p_student_user_id,v_chapter,v_date,'Asia/Seoul');
  v_count := v_count+1;
 end loop;
 return v_count;
end $$;
revoke all on function public.cq_v4_parent_schedule_week_atomic(uuid,jsonb) from public,anon;
grant execute on function public.cq_v4_parent_schedule_week_atomic(uuid,jsonb) to authenticated;
