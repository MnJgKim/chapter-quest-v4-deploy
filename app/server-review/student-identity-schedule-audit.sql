-- Chapter Quest V4 / READ ONLY. No student UUIDs, tokens or PII exported.
-- Inspect student identity/schedule consistency before any production changes.
with approved_invites as (
 select i.parent_user_id,i.claimed_by as student_user_id,i.student_name
 from public.cq_v4_invites i
 where i.claimed_by is not null and i.approved_at is not null and i.revoked_at is null
), schedule_summary as (
 select s.parent_user_id,s.student_user_id,count(*) as lessons,
 min(s.lesson_date) as first_date,max(s.lesson_date) as last_date,
 count(*) filter(where extract(isodow from s.lesson_date)=3) as wednesday_count
 from public.cq_v4_lesson_schedule s
 group by s.parent_user_id,s.student_user_id
)
select coalesce(a.student_name,'UNMATCHED APPROVED INVITE') as student_label,
 coalesce(s.lessons,0) as lessons,s.first_date,s.last_date,
 coalesce(s.wednesday_count,0) as wednesday_count,
 (a.student_user_id is not null) as approved_invite_matched
from schedule_summary s
left join approved_invites a on a.parent_user_id=s.parent_user_id and a.student_user_id=s.student_user_id
union all
select a.student_name,0,null::date,null::date,0,true
from approved_invites a
where not exists(select 1 from schedule_summary s where s.parent_user_id=a.parent_user_id and s.student_user_id=a.student_user_id)
order by student_label,first_date;
