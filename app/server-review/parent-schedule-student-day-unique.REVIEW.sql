-- REVIEW ONLY: do not apply to production without explicit approval and backup.
-- Preserve all existing schedule rows, released_at timestamps, and lesson dates.
-- This unique index prevents two different chapters on the same student/date,
-- including concurrent parent scheduling requests (SQLSTATE 23505).
-- PRECONDITION: read-only duplicate audit must return zero rows.
-- On a duplicate, CREATE UNIQUE INDEX fails without deleting or updating data.
-- Run outside a transaction if changing to CONCURRENTLY for a production plan.
CREATE UNIQUE INDEX cq_v4_lesson_schedule_student_day_unique
  ON public.cq_v4_lesson_schedule (student_user_id, lesson_date);

-- REVIEW ROLLBACK (only after an approved migration, not executed here):
-- DROP INDEX public.cq_v4_lesson_schedule_student_day_unique;
