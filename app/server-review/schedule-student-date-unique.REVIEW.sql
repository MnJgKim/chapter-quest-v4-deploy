-- REVIEW ONLY: do not apply to hosted production without backup,
-- student/date collision review, compatibility tests and user approval.
-- Guarantees at most one scheduled chapter per student per local lesson date,
-- regardless of whether the writer is the legacy manual RPC or new batch RPC.
-- Existing primary key (student_user_id,chapter_id) remains unchanged.
-- On collision, PostgreSQL raises unique_violation and rolls back the statement.
--
-- PRECHECK (read-only):
-- select student_user_id, lesson_date, count(*)
-- from public.cq_v4_lesson_schedule
-- group by student_user_id, lesson_date having count(*) > 1;
--
-- Do not proceed if the precheck returns any rows. Never delete duplicates
-- automatically: parent approval is required to reconcile existing schedules.
create unique index if not exists cq_v4_lesson_schedule_student_date_unique
on public.cq_v4_lesson_schedule(student_user_id,lesson_date);
