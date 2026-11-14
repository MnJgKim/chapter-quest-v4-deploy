-- Local-only CI parity with existing operating lesson-release contract.
create table public.cq_v4_lesson_schedule (
 parent_user_id uuid not null,
 student_user_id uuid not null,
 chapter_id uuid not null,
 lesson_date date not null,
 released_at timestamptz,
 primary key (student_user_id,chapter_id)
);
alter table public.cq_v4_lesson_schedule enable row level security;
revoke all on public.cq_v4_lesson_schedule from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_my_released_chapters()
 RETURNS TABLE(chapter_uuid uuid, chapter_title text, questions jsonb, lesson_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select c.chapter_id,c.title,act.questions,s.lesson_date
 from public.cq_v4_lesson_schedule s
 join public.cq_v4_pdf_chapters c on c.chapter_id=s.chapter_id and c.parent_user_id=s.parent_user_id
 join public.cq_v4_pdf_assignments a on a.chapter_id=s.chapter_id and a.student_user_id=s.student_user_id
 join public.cq_v4_pdf_enrollments e on e.parent_user_id=s.parent_user_id and e.student_user_id=s.student_user_id
 join public.cq_v4_activities act on act.chapter_uuid=s.chapter_id and act.published_at is not null
 where s.student_user_id=(select auth.uid()) and c.pdf_ready is true and s.released_at is not null
 order by s.lesson_date,s.chapter_id;
$function$
;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_list_lesson_releases()
 RETURNS TABLE(student_user_id uuid, chapter_id uuid, lesson_date date, released_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select s.student_user_id,s.chapter_id,s.lesson_date,s.released_at
 from public.cq_v4_lesson_schedule s
 where s.parent_user_id=(select auth.uid()) and public.cq_is_admin()
 order by s.lesson_date,s.chapter_id;
$function$
;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_schedule_lesson(p_student_user_id uuid, p_chapter_id uuid, p_lesson_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_parent uuid:=auth.uid();
begin
 if v_parent is null or not public.cq_is_admin() then raise exception 'Parent authorization required' using errcode='42501';end if;
 if p_lesson_date is null then raise exception 'Lesson date required' using errcode='22023';end if;
 if not exists (
  select 1 from public.cq_v4_pdf_enrollments e
  join public.cq_v4_pdf_chapters c on c.parent_user_id=e.parent_user_id
  join public.cq_v4_activities act on act.chapter_uuid=c.chapter_id and act.published_at is not null
  where e.parent_user_id=v_parent and e.student_user_id=p_student_user_id
    and c.chapter_id=p_chapter_id and c.pdf_ready=true
 ) then raise exception 'Approved PDF and enrolled student required' using errcode='42501';end if;
 insert into public.cq_v4_lesson_schedule(parent_user_id,student_user_id,chapter_id,lesson_date)
 values(v_parent,p_student_user_id,p_chapter_id,p_lesson_date)
 on conflict(student_user_id,chapter_id) do update
 set lesson_date=excluded.lesson_date
 where public.cq_v4_lesson_schedule.parent_user_id=v_parent;
 if not found then raise exception 'Schedule update not authorized' using errcode='42501';end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_set_lesson_release(p_student_user_id uuid, p_chapter_id uuid, p_release boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_parent uuid:=auth.uid();
begin
 if v_parent is null or not public.cq_is_admin() then raise exception 'Parent authorization required' using errcode='42501';end if;
 if not exists(select 1 from public.cq_v4_lesson_schedule s where s.parent_user_id=v_parent and s.student_user_id=p_student_user_id and s.chapter_id=p_chapter_id) then
  raise exception 'Owned scheduled lesson required' using errcode='42501';
 end if;
 if p_release and not exists (
  select 1 from public.cq_v4_pdf_chapters c
  join public.cq_v4_activities a on a.chapter_uuid=c.chapter_id and a.published_at is not null
  where c.chapter_id=p_chapter_id and c.parent_user_id=v_parent and c.pdf_ready=true
 ) then raise exception 'Published and verified lesson required' using errcode='42501';end if;
 update public.cq_v4_lesson_schedule
 set released_at=case when p_release then coalesce(released_at,now()) else null end
 where parent_user_id=v_parent and student_user_id=p_student_user_id and chapter_id=p_chapter_id;
end $function$
;

revoke all on function public.cq_v4_parent_schedule_lesson(uuid,uuid,date) from public,anon;
revoke all on function public.cq_v4_parent_set_lesson_release(uuid,uuid,boolean) from public,anon;
revoke all on function public.cq_v4_parent_list_lesson_releases() from public,anon;
revoke all on function public.cq_v4_my_released_chapters() from public,anon;
grant execute on function public.cq_v4_parent_schedule_lesson(uuid,uuid,date),public.cq_v4_parent_set_lesson_release(uuid,uuid,boolean),public.cq_v4_parent_list_lesson_releases(),public.cq_v4_my_released_chapters() to authenticated;
