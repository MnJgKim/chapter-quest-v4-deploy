-- REVIEW ONLY / NOT AUTHORIZED FOR PRODUCTION EXECUTION.
-- Controlled one-time remap of existing scheduled lessons to Mon/Wed/Thu.
-- Requires an explicitly verified student UUID, backups, restore drill and final approval.
-- Preserves chapter IDs, release timestamps, ownership, and all student submissions.
-- The function is deliberately NOT created here: this is a transaction template.
-- Before any authorized execution, replace the placeholder via a reviewed migration.
begin;
do $$
declare
  v_student uuid := null; -- MUST supply verified Seowoo student UUID in approved migration
  v_count integer;
begin
  if v_student is null then raise exception 'STOP: verified student identity required'; end if;
  -- Lock target rows to prevent concurrent edits; no changes to other students.
  perform 1 from public.cq_v4_lesson_schedule
   where student_user_id=v_student for update;
  select count(*) into v_count
    from public.cq_v4_lesson_schedule
    where student_user_id=v_student and lesson_date>=date '2026-11-23';
  if v_count<>10 then raise exception 'STOP: expected 10 future lessons, found %',v_count; end if;
  if (select count(distinct parent_user_id) from public.cq_v4_lesson_schedule
      where student_user_id=v_student and lesson_date>=date '2026-11-23')<>1 then
    raise exception 'STOP: inconsistent parent ownership';
  end if;
  if exists(select 1 from public.cq_v4_student_submissions sub
    join public.cq_v4_lesson_schedule s
      on s.student_user_id=sub.child_user_id and s.chapter_id=sub.chapter_uuid
    where s.student_user_id=v_student and s.lesson_date>=date '2026-11-23') then
    raise exception 'STOP: existing student submission';
  end if;
  create temporary table cq_remap on commit drop as
  with lessons as (
    select chapter_id,lesson_date old_date,
      row_number() over(order by lesson_date,chapter_id) rn
    from public.cq_v4_lesson_schedule
    where student_user_id=v_student and lesson_date>=date '2026-11-23'
  ), dates as (
    select d::date new_date,row_number() over(order by d) rn
    from generate_series(date '2026-11-23',date '2027-01-31',interval '1 day') d
    where extract(isodow from d)::int in (1,3,4)
  )
  select l.chapter_id,l.old_date,d.new_date from lessons l join dates d using(rn);
  if (select count(*) from cq_remap)<>10 then raise exception 'STOP: incomplete plan'; end if;
  -- Ensure target dates are not occupied by lessons outside this batch.
  if exists(select 1 from public.cq_v4_lesson_schedule s
     where s.student_user_id=v_student
       and s.lesson_date in (select new_date from cq_remap)
       and s.chapter_id not in (select chapter_id from cq_remap)) then
    raise exception 'STOP: external date conflict';
  end if;
  -- The current production PK permits direct date changes, but the proposed
  -- schedule-student-date-unique.REVIEW.sql adds a UNIQUE(student,date) index.
  -- Use two phases so the migration remains compatible after that index lands.
  -- All moves happen inside this single transaction and roll back together.
  if exists(select 1 from public.cq_v4_lesson_schedule s
    where s.student_user_id=v_student
      and s.lesson_date between date '2099-01-01' and date '2099-01-10') then
    raise exception 'STOP: temporary dates occupied';
  end if;
  update public.cq_v4_lesson_schedule s
  set lesson_date=date '2099-01-01'+(m.seq-1)
  from (select chapter_id,row_number() over(order by old_date,chapter_id) seq from cq_remap) m
  where s.student_user_id=v_student and s.chapter_id=m.chapter_id;
  update public.cq_v4_lesson_schedule s set lesson_date=m.new_date
  from cq_remap m
  where s.student_user_id=v_student and s.chapter_id=m.chapter_id;
  if (select count(*) from public.cq_v4_lesson_schedule s join cq_remap m
      on s.student_user_id=v_student and s.chapter_id=m.chapter_id
      and s.lesson_date=m.new_date)<>10 then
    raise exception 'STOP: readback mismatch';
  end if;
end $$;
-- ROLLBACK BY DEFAULT. Replace with COMMIT only in separately approved,
-- backed-up and rehearsed migration after verifying every guard.
rollback;
