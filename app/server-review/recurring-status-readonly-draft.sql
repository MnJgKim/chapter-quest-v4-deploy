-- Stage 54: DEVELOPMENT-ONLY draft. DO NOT APPLY TO PRODUCTION WITHOUT APPROVAL.
-- This read-only compatibility RPC reports existing scheduled lessons only.
-- It intentionally does not pretend that a recurring queue or automatic publisher exists.
-- Parent authorization uses the same cq_is_admin/auth.uid() contract as the existing
-- cq_v4_parent_list_lesson_releases RPC. No data is written by this function.
CREATE OR REPLACE FUNCTION public.cq_v4_parent_recurring_status()
RETURNS TABLE (
  student_id uuid,
  weekdays integer[],
  enabled boolean,
  effective_from date,
  book_title text,
  current_title text,
  next_title text,
  chapter_title text,
  chapter_number integer,
  state text,
  pdf_ready boolean,
  published boolean,
  withdraw_chapter uuid
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT
    e.student_user_id AS student_id,
    ARRAY[]::integer[] AS weekdays,
    false AS enabled,
    NULL::date AS effective_from,
    NULL::text AS book_title,
    NULL::text AS current_title,
    NULL::text AS next_title,
    NULL::text AS chapter_title,
    NULL::integer AS chapter_number,
    'blocked'::text AS state,
    false AS pdf_ready,
    false AS published,
    NULL::uuid AS withdraw_chapter
  FROM public.cq_v4_pdf_enrollments e
  WHERE e.parent_user_id = (SELECT auth.uid())
    AND public.cq_is_admin()
  ORDER BY e.student_user_id;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_recurring_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_recurring_status() TO authenticated;

-- NOT a completed queue implementation. No recurring write RPCs are created here.
-- Production rollout must include a real queue schema, atomic enqueue/withdraw
-- procedures, ownership/RLS checks, and a Seoul-time automatic release executor.
