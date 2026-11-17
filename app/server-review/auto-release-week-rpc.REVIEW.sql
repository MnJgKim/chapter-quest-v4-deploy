-- REVIEW ONLY. Atomic opt-in auto-scheduling and date-gated pre-arming.
-- Requires policy, cancellation, arms, and base weekly RPC migrations.
-- Do not apply to production without backup, compatibility checks, and approval.
create or replace function public.cq_v4_parent_schedule_auto_week(
 p_student_user_id uuid,p_items jsonb
) returns integer language plpgsql security definer set search_path=''
as $fn$
declare
 v_parent uuid:=auth.uid();
 v_item jsonb;
 v_chapter uuid;
 v_date date;
 v_today date:=(now() at time zone 'Asia/Seoul')::date;
 v_count integer;
begin
 if v_parent is null or not public.cq_is_admin() then
  raise exception 'Parent authorization required' using errcode='42501';
 end if;
 if p_student_user_id is null or p_items is null
   or jsonb_typeof(p_items)<>'array'
   or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>31 then
  raise exception 'Invalid auto schedule batch' using errcode='22023';
 end if;
 -- Lock enrollment, serializing this writer with the base weekly RPC.
 perform 1 from public.cq_v4_pdf_enrollments
 where parent_user_id=v_parent and student_user_id=p_student_user_id for update;
 if not found then raise exception 'Student enrollment required' using errcode='42501';end if;
 if not exists(select 1 from public.cq_v4_auto_release_policies p
  where p.parent_user_id=v_parent and p.student_user_id=p_student_user_id
    and p.enabled=true) then
  raise exception 'Auto release opt-in required' using errcode='42501';
 end if;
 -- Preflight every item before inserting any row.
 for v_item in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(v_item)<>'object'
   or jsonb_typeof(v_item->'chapter_id')<>'string'
   or jsonb_typeof(v_item->'lesson_date')<>'string'
   or (v_item->>'chapter_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or (v_item->>'lesson_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  then raise exception 'Invalid auto schedule item' using errcode='22023';end if;
  v_chapter:=(v_item->>'chapter_id')::uuid;
  v_date:=(v_item->>'lesson_date')::date;
  if to_char(v_date,'YYYY-MM-DD')<>(v_item->>'lesson_date') or v_date<v_today then
   raise exception 'Invalid or past auto release date' using errcode='22023';
  end if;
  if not exists(select 1 from public.cq_v4_auto_release_policies p
    where p.parent_user_id=v_parent and p.student_user_id=p_student_user_id
      and p.enabled and extract(isodow from v_date)::smallint=any(p.weekdays))
  then raise exception 'Date outside opted-in weekdays' using errcode='42501';end if;
  if exists(select 1 from public.cq_v4_auto_release_cancellations c
    where c.parent_user_id=v_parent and c.student_user_id=p_student_user_id
      and c.chapter_id=v_chapter)
  then raise exception 'Auto release previously cancelled' using errcode='42501';end if;
 end loop;
 -- All inserts, arms, and release flags are one PostgreSQL transaction.
 v_count:=public.cq_v4_parent_schedule_week_atomic(p_student_user_id,p_items);
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_chapter:=(v_item->>'chapter_id')::uuid;
  insert into public.cq_v4_auto_release_arms(parent_user_id,student_user_id,chapter_id)
   values(v_parent,p_student_user_id,v_chapter);
  update public.cq_v4_lesson_schedule set released_at=now()
   where parent_user_id=v_parent and student_user_id=p_student_user_id
    and chapter_id=v_chapter;
 end loop;
 return v_count;
end $fn$;
revoke all on function public.cq_v4_parent_schedule_auto_week(uuid,jsonb) from public,anon;
grant execute on function public.cq_v4_parent_schedule_auto_week(uuid,jsonb) to authenticated;
