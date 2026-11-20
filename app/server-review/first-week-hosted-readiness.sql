-- READ ONLY: zero writes; returns no student UUID, email or token.
-- Run before final approval; do not treat this as a recoverable backup.
with approved as (
 select i.parent_user_id,i.claimed_by,i.student_name
 from public.cq_v4_invites i
 where i.approved_at is not null and i.revoked_at is null and i.claimed_by is not null
), audit as (
 select s.lesson_date,coalesce(a.student_name,'UNVERIFIED STUDENT') as student_label,
 (a.claimed_by is not null) as identity_verified,
 (e.student_user_id is not null) as enrolled,
 (p.chapter_id is not null) as assigned,
 c.pdf_ready,
 (c.pdf_verified_at is not null) as pdf_verified,
 (act.published_at is not null) as activity_published,
 (s.released_at is not null) as release_flag,
 s.timezone
 from public.cq_v4_lesson_schedule s
 left join approved a on a.parent_user_id=s.parent_user_id and a.claimed_by=s.student_user_id
 left join public.cq_v4_pdf_enrollments e on e.parent_user_id=s.parent_user_id and e.student_user_id=s.student_user_id
 left join public.cq_v4_pdf_assignments p on p.chapter_id=s.chapter_id and p.student_user_id=s.student_user_id
 left join public.cq_v4_pdf_chapters c on c.chapter_id=s.chapter_id and c.parent_user_id=s.parent_user_id
 left join public.cq_v4_activities act on act.chapter_uuid=s.chapter_id
 where s.lesson_date between date '2026-11-23' and date '2026-11-27'
)
select lesson_date,student_label,identity_verified,enrolled,assigned,pdf_ready,pdf_verified,activity_published,release_flag,timezone
from audit order by lesson_date,student_label;
