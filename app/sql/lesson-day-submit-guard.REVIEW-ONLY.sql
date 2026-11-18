-- REVIEW ONLY. Do not run against production without explicit approval.
-- Server-enforced Seoul lesson date on new submission rows.
-- Existing submitted records remain readable; this trigger never updates or deletes them.
-- Parent-approved make-up lessons require rescheduling through the existing parent RPC.
create or replace function public.cq_v4_guard_submission_lesson_day()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.child_user_id is distinct from (select auth.uid()) then
    raise exception 'Student identity mismatch' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.cq_v4_lesson_schedule s
    join public.cq_v4_pdf_assignments a
      on a.chapter_id = s.chapter_id and a.student_user_id = s.student_user_id
    join public.cq_v4_pdf_enrollments e
      on e.parent_user_id = s.parent_user_id and e.student_user_id = s.student_user_id
    join public.cq_v4_pdf_chapters c
      on c.chapter_id = s.chapter_id and c.parent_user_id = s.parent_user_id
    join public.cq_v4_activities act
      on act.chapter_uuid = s.chapter_id and act.published_at is not null
    where s.chapter_id = new.chapter_uuid
      and s.student_user_id = new.child_user_id
      and c.pdf_ready is true
      and s.released_at is not null
      and s.lesson_date = (now() at time zone 'Asia/Seoul')::date
  ) then
    raise exception 'New submissions are permitted only on the approved Seoul lesson date'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists cq_v4_guard_submission_lesson_day on public.cq_v4_student_submissions;
create trigger cq_v4_guard_submission_lesson_day
before insert on public.cq_v4_student_submissions
for each row execute function public.cq_v4_guard_submission_lesson_day();

-- Follow-up review required: submission RPC uses SECURITY DEFINER;
-- verify invoker auth.uid() remains the student and check recording upload
-- authorization separately. Do not consider this trigger a full start gate.
