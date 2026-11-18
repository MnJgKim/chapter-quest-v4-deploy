-- REVIEW ONLY: read-only bridge between explicit approved order and weekday policy.
-- No schedule writes, assignments, releases or production data changes.
-- Must load AFTER student-weekday-policy-v1 and approved-chapter-queue-v1.
CREATE OR REPLACE FUNCTION public.cq_v4_weekday_approved_candidate(
 p_student uuid, p_as_of date DEFAULT (now() AT TIME ZONE 'Asia/Seoul')::date
) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 SELECT public.cq_v4_next_approved_chapter(p_student)
 WHERE p_student=(SELECT auth.uid())
   AND p_as_of IS NOT NULL
   AND EXISTS (
     SELECT 1 FROM public.cq_v4_student_weekday_policy pol
     JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id=pol.student_user_id
     WHERE pol.student_user_id=p_student AND pol.enabled IS TRUE
       AND pol.effective_from<=p_as_of
       AND EXTRACT(ISODOW FROM p_as_of)::integer=ANY(pol.weekdays)
       AND EXISTS (
         SELECT 1 FROM public.cq_v4_approved_chapter_queue q
         WHERE q.student_user_id=p_student AND q.parent_user_id=e.parent_user_id
       )
   );
$$;
REVOKE ALL ON FUNCTION public.cq_v4_weekday_approved_candidate(uuid,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_weekday_approved_candidate(uuid,date) TO authenticated;
-- SECURITY: p_as_of is a testing/planning input, NOT a permission to start work.
-- NEVER use this function alone as a release gate. Production can_start must
-- use trusted Seoul server time, audited makeup overrides and exactly one
-- atomic approved lesson slot. Existing historical reads must remain intact.
