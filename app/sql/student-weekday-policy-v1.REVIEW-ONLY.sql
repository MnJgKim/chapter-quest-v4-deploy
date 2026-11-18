-- REVIEW ONLY. No production writes. Apply to isolated PostgreSQL after schema review.
-- A weekday policy is separate from assignment: it NEVER selects or publishes a chapter.
-- ISO weekdays: Monday=1 ... Sunday=7.
CREATE TABLE IF NOT EXISTS public.cq_v4_student_weekday_policy (
 student_user_id uuid PRIMARY KEY,
 weekdays integer[] NOT NULL,
 effective_from date NOT NULL,
 enabled boolean NOT NULL DEFAULT true,
 CONSTRAINT cq_v4_weekdays_nonempty CHECK (cardinality(weekdays) BETWEEN 1 AND 7),
 CONSTRAINT cq_v4_weekdays_valid CHECK (weekdays <@ ARRAY[1,2,3,4,5,6,7]::integer[])
);
-- Duplicate weekday values are harmless to ANY() checks; normalization is a follow-up.
-- No direct client writes: future parent-only RPC must validate ownership.
-- This table alone does NOT authorize reading or starting a lesson.
ALTER TABLE public.cq_v4_student_weekday_policy ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_student_weekday_policy FROM PUBLIC,anon,authenticated;
-- Student IDs and initial schedules require owner-approved mapping before use.
