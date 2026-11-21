-- READ-ONLY operational audit. Do not alter existing schedules or first-lesson dates.
-- Run as a privileged reviewer; results may contain student identifiers.
select student_user_id,lesson_date,count(*) as chapter_count,
       array_agg(chapter_id order by chapter_id) as chapter_ids
from public.cq_v4_lesson_schedule
group by student_user_id,lesson_date
having count(*)>1
order by lesson_date,student_user_id;

-- Confirm whether the two optional parent notice RPCs are installed.
select required.proname, exists(
 select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname=required.proname
) as installed
from (values ('cq_v4_parent_reread_inbox'),
             ('cq_v4_parent_ack_reread_notice')) required(proname);
