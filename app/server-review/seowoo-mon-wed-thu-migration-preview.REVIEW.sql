-- REVIEW ONLY. Proposed Mon/Wed/Thu dates for the existing 10-lesson cohort.
-- No UPDATE/INSERT/DELETE. Do not execute a migration until student identity,
-- backup/restore proof, conflict checks, and explicit production approval.
-- Keep the chapter order; date changes are a proposal, NOT an approved migration.
with cohorts as (
 select s.parent_user_id,s.student_user_id,count(*) n
 from public.cq_v4_lesson_schedule s
 where s.lesson_date >= date '2026-11-23'
 group by 1,2
 having count(*)=10
), ranked_existing as (
 select s.parent_user_id,s.student_user_id,s.chapter_id,s.lesson_date old_date,
 row_number() over(partition by s.parent_user_id,s.student_user_id order by s.lesson_date,s.chapter_id) seq
 from public.cq_v4_lesson_schedule s
 join cohorts c on c.parent_user_id=s.parent_user_id and c.student_user_id=s.student_user_id
 where s.lesson_date >= date '2026-11-23'
), dates as (
 select d::date proposed_date,
 row_number() over(order by d) seq
 from generate_series(date '2026-11-23',date '2027-01-31',interval '1 day') d
 where extract(isodow from d)::int in (1,3,4)
), plan as (
 select e.*,d.proposed_date from ranked_existing e join dates d on d.seq=e.seq
)
select p.student_user_id,p.seq,p.old_date,p.proposed_date,
 (p.old_date<>p.proposed_date) requires_date_change,
 exists(
  select 1 from public.cq_v4_lesson_schedule other
  where other.student_user_id=p.student_user_id
    and other.lesson_date=p.proposed_date
    and other.chapter_id<>p.chapter_id
 ) proposed_date_occupied,
 exists(
  select 1 from public.cq_v4_student_submissions sub
  where sub.child_user_id=p.student_user_id and sub.chapter_uuid=p.chapter_id
 ) has_student_submission
from plan p
order by p.student_user_id,p.seq;
