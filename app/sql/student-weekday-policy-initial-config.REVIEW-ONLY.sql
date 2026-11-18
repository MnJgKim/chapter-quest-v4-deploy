-- REVIEW ONLY. Use verified full account IDs and an approved Seoul effective date.
-- psql variables: seowoo_student, seowoo_parent, seojin_student, seojin_parent,
-- weekday_effective_from. Run only in an isolated fixture or after rollout approval.
-- This statement writes only policy rows. A missing enrollment or a reused student
-- ID makes the entire statement fail. Existing policy rows are preserved.
\set ON_ERROR_STOP on
WITH requested(student_id, parent_id, weekdays) AS (
  VALUES
    (:'seowoo_student'::uuid, :'seowoo_parent'::uuid, ARRAY[1,3,4]),
    (:'seojin_student'::uuid, :'seojin_parent'::uuid, ARRAY[2,3,5])
)
INSERT INTO public.cq_v4_student_weekday_policy (student_user_id, weekdays, effective_from)
SELECT CASE WHEN
    (SELECT count(DISTINCT r.student_id) FROM requested r) = 2
    AND NOT EXISTS (
      SELECT 1 FROM requested r
      WHERE NOT EXISTS (
        SELECT 1 FROM public.cq_v4_pdf_enrollments e
        WHERE e.student_user_id = r.student_id AND e.parent_user_id = r.parent_id
      )
    )
  THEN requested.student_id END,
  requested.weekdays,
  :'weekday_effective_from'::date
FROM requested
ON CONFLICT (student_user_id) DO NOTHING
RETURNING student_user_id, weekdays, effective_from, enabled;
