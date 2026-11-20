-- Read-only production function snapshot, 2026-11-17 KST. Isolated tests only.
CREATE OR REPLACE FUNCTION public.cq_v4_is_released(p_chapter uuid, p_student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
SELECT EXISTS (
 SELECT 1 FROM public.cq_v4_lesson_schedule s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id AND c.pdf_ready IS TRUE
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=s.chapter_id AND a.student_user_id=s.student_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id
 JOIN public.cq_v4_activities act ON act.chapter_uuid=s.chapter_id AND act.published_at IS NOT NULL
 WHERE s.chapter_id=p_chapter AND s.student_user_id=p_student
 AND ((SELECT auth.uid())=p_student
      OR ((SELECT auth.uid())=s.parent_user_id AND public.cq_is_admin()))
 AND s.released_at IS NOT NULL
 AND (now() AT TIME ZONE COALESCE(NULLIF(s.timezone,''),'Asia/Seoul'))::date >= s.lesson_date
);
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_chapter_activities(p_chapter_uuid uuid)
 RETURNS TABLE(vocabulary jsonb, writing_prompt text, speaking_prompt text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select act.vocabulary,act.writing_prompt,act.speaking_prompt
 from public.cq_v4_activities act
 join public.cq_v4_pdf_chapters c on c.chapter_id=act.chapter_uuid
 join public.cq_v4_pdf_assignments a on a.chapter_id=c.chapter_id
 join public.cq_v4_pdf_enrollments e on e.parent_user_id=c.parent_user_id and e.student_user_id=a.student_user_id
 where act.chapter_uuid=p_chapter_uuid and a.student_user_id=(select auth.uid())
 and act.published_at is not null and c.pdf_ready is true
 and public.cq_v4_is_released(p_chapter_uuid,(select auth.uid()));
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_chapters()
 RETURNS TABLE(chapter_uuid uuid, chapter_title text, questions jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select c.chapter_id,c.title,act.questions
 from public.cq_v4_pdf_chapters c
 join public.cq_v4_pdf_assignments a on a.chapter_id=c.chapter_id
 join public.cq_v4_pdf_enrollments e on e.parent_user_id=c.parent_user_id and e.student_user_id=a.student_user_id
 join public.cq_v4_activities act on act.chapter_uuid=c.chapter_id and act.published_at is not null
 where a.student_user_id=(select auth.uid()) and c.pdf_ready is true
 and public.cq_v4_is_released(c.chapter_id,(select auth.uid()))
 order by c.created_at,c.chapter_id;
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_my_released_chapters()
 RETURNS TABLE(chapter_uuid uuid, chapter_title text, questions jsonb, lesson_date date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT c.chapter_id,c.title,act.questions,s.lesson_date
 FROM public.cq_v4_lesson_schedule s
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_id AND c.parent_user_id=s.parent_user_id
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=s.chapter_id AND a.student_user_id=s.student_user_id
 JOIN public.cq_v4_pdf_enrollments e ON e.parent_user_id=s.parent_user_id AND e.student_user_id=s.student_user_id
 JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id AND act.published_at IS NOT NULL
 WHERE s.student_user_id=(SELECT auth.uid()) AND c.pdf_ready IS TRUE
   AND public.cq_v4_is_released(s.chapter_id,(SELECT auth.uid()))
 ORDER BY s.lesson_date,s.chapter_id;
$function$;

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
end $function$;

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
end $function$;
