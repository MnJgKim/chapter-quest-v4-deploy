CREATE OR REPLACE FUNCTION public.cq_v4_my_lesson_schedule()
 RETURNS TABLE(chapter_uuid uuid, chapter_title text, lesson_date date, is_released boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select s.chapter_id,c.title,s.lesson_date,s.released_at is not null
 from public.cq_v4_lesson_schedule s
 join public.cq_v4_pdf_chapters c on c.chapter_id=s.chapter_id and c.parent_user_id=s.parent_user_id
 join public.cq_v4_pdf_enrollments e on e.parent_user_id=s.parent_user_id and e.student_user_id=s.student_user_id
 join public.cq_v4_activities a on a.chapter_uuid=s.chapter_id and a.published_at is not null
 where s.student_user_id=(select auth.uid()) and c.pdf_ready is true
 order by s.lesson_date,s.chapter_id;
$function$
;
