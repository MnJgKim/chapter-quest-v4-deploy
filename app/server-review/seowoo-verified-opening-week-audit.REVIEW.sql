-- READ ONLY. Verify Seowoo's identity, ten existing lessons and target weekdays.
-- Never execute a schedule change from this audit.
with paired as (
 select distinct d.auth_user_id student_user_id
 from public.cq_students st
 join public.cq_student_devices d on d.student_id=st.id
 where st.name='이서우' and d.revoked_at is null
), identity_check as (
 select count(*) active_accounts from paired
), existing as (
 select s.student_user_id,s.chapter_id,s.lesson_date,s.released_at,
        row_number() over(order by s.lesson_date,s.chapter_id) rn
 from public.cq_v4_lesson_schedule s join paired p using(student_user_id)
 where s.lesson_date>=date '2026-11-23'
), target as (
 select d::date new_date,row_number() over(order by d) rn
 from generate_series(date '2026-11-23',date '2027-01-31',interval '1 day') d
 where extract(isodow from d)::int in (1,3,4)
), plan as (
 select e.*,t.new_date from existing e join target t using(rn)
)
select p.rn,p.lesson_date original_date,p.new_date proposed_date,
 to_char(p.new_date,'Dy') proposed_weekday,
 p.released_at is not null prearmed,
 (select active_accounts=1 from identity_check) identity_unambiguous,
 (select count(*)=10 from existing) exactly_ten_future_lessons,
 not exists(select 1 from public.cq_v4_student_submissions sub
  where sub.child_user_id=p.student_user_id and sub.chapter_uuid=p.chapter_id) no_existing_submission,
 not exists(select 1 from public.cq_v4_lesson_schedule other
  where other.student_user_id=p.student_user_id and other.lesson_date=p.new_date
  and other.chapter_id not in (select chapter_id from existing)) no_external_date_conflict
from plan p order by p.rn;
