-- Run only after approval with the verified full student and parent UUIDs.
-- Supply display_previous_is_null=true for installation, false for rollback.
\set ON_ERROR_STOP on
BEGIN;
WITH changed AS (
  UPDATE public.cq_v4_pdf_enrollments
  SET display_name=CASE WHEN :'display_previous_is_null'::boolean THEN '서우' ELSE NULL END
  WHERE student_user_id=:'display_student'::uuid AND parent_user_id=:'display_parent'::uuid
    AND display_name IS NOT DISTINCT FROM
        CASE WHEN :'display_previous_is_null'::boolean THEN NULL ELSE '서우' END
  RETURNING 1
)
-- Both directions must match exactly one expected row, or roll back.
SELECT 1 / (count(*) = 1)::integer AS exactly_one_expected_row FROM changed;
COMMIT;
