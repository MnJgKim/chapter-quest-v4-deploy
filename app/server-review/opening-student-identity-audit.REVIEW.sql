-- READ ONLY: reconcile approved student invitations with opening-week assignments.
-- Do not equate an unlabelled account with Seowoo; resolve in the authenticated parent UI.
with enrolled as (
 select e.parent_user_id,e.student_user_id,
 (select v.student_name from public.cq_v4_invites v
  where v.parent_user_id=e.parent_user_id and v.claimed_by=e.student_user_id
    and v.approved_at is not null and v.revoked_at is null
  order by v.approved_at desc limit 1) verified_invite_name
 from public.cq_v4_pdf_enrollments e
), weekdays as (
 select d::date lesson_date,extract(isodow from d)::integer iso_weekday
 from generate_series(date '2026-11-23',date '2026-11-27',interval '1 day') d
)
select coalesce(e.verified_invite_name,'UNVERIFIED ACCOUNT') student_label,
 e.student_user_id,w.lesson_date,w.iso_weekday,
 count(distinct a.chapter_id) total_assigned_chapters,
 count(distinct s.chapter_id) scheduled_on_day,
 count(distinct s.chapter_id) filter(where s.released_at is not null) prearmed_on_day
from enrolled e cross join weekdays w
left join public.cq_v4_pdf_assignments a
 on a.student_user_id=e.student_user_id
left join public.cq_v4_lesson_schedule s
 on s.student_user_id=e.student_user_id and s.lesson_date=w.lesson_date
group by e.verified_invite_name,e.student_user_id,w.lesson_date,w.iso_weekday
order by student_label,e.student_user_id,w.lesson_date;
