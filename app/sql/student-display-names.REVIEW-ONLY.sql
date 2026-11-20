-- Review only. Names belong to the existing enrollment, independently of Auth and invites.
BEGIN;
ALTER TABLE public.cq_v4_pdf_enrollments
  ADD COLUMN IF NOT EXISTS display_name text;

CREATE OR REPLACE FUNCTION public.cq_v4_enrolled_display_name(p_parent uuid,p_student uuid)
RETURNS text LANGUAGE sql STABLE SET search_path TO ''
AS $$
 SELECT coalesce(NULLIF(btrim(e.display_name),''),i.student_name)
 FROM public.cq_v4_pdf_enrollments e
 LEFT JOIN LATERAL (
   SELECT NULLIF(btrim(x.student_name),'') AS student_name
   FROM public.cq_v4_invites x
   WHERE x.parent_user_id=e.parent_user_id AND x.claimed_by=e.student_user_id
     AND x.approved_at IS NOT NULL AND x.revoked_at IS NULL
     AND NULLIF(btrim(x.student_name),'') IS NOT NULL
   ORDER BY x.approved_at DESC,x.created_at DESC,x.invite_id
   LIMIT 1
 ) i ON true
 WHERE e.parent_user_id=p_parent AND e.student_user_id=p_student;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_enrolled_display_name(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_my_display_name()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 SELECT CASE WHEN count(DISTINCT resolved.name)=1 THEN min(resolved.name) END
 FROM public.cq_v4_pdf_enrollments e
 CROSS JOIN LATERAL (SELECT public.cq_v4_enrolled_display_name(e.parent_user_id,e.student_user_id) AS name) resolved
 WHERE e.student_user_id=(SELECT auth.uid());
$$;
REVOKE ALL ON FUNCTION public.cq_v4_my_display_name() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_my_display_name() TO authenticated;

CREATE OR REPLACE FUNCTION public.cq_v4_list_child_access()
 RETURNS TABLE(child_user_id uuid, student_name text, active boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 WITH linked AS (
   SELECT e.student_user_id AS uid
   FROM public.cq_v4_pdf_enrollments e
   WHERE e.parent_user_id=(SELECT auth.uid())
 ), pending AS (
   SELECT DISTINCT ON (i.claimed_by) i.claimed_by AS uid, i.student_name
   FROM public.cq_v4_invites i
   WHERE i.parent_user_id=(SELECT auth.uid()) AND i.claimed_by IS NOT NULL
     AND i.revoked_at IS NULL AND i.approved_at IS NULL
   ORDER BY i.claimed_by,i.claimed_at DESC NULLS LAST,i.created_at DESC
 ), names AS (
   SELECT DISTINCT ON (i.claimed_by) i.claimed_by AS uid, i.student_name
   FROM public.cq_v4_invites i
   WHERE i.parent_user_id=(SELECT auth.uid()) AND i.claimed_by IS NOT NULL
     AND i.student_name IS NOT NULL
   ORDER BY i.claimed_by,
     (i.approved_at IS NOT NULL) DESC,
     i.claimed_at DESC NULLS LAST,i.created_at DESC
 )
 SELECT ids.uid AS child_user_id,
        COALESCE(public.cq_v4_enrolled_display_name((SELECT auth.uid()),ids.uid), NULLIF(btrim(n.student_name),''), '계정 '||right(ids.uid::text,8))::text AS student_name,
        (l.uid IS NOT NULL) AS active
 FROM (SELECT uid FROM pending UNION SELECT uid FROM linked) ids
 LEFT JOIN names n ON n.uid=ids.uid
 LEFT JOIN linked l ON l.uid=ids.uid
 WHERE public.cq_is_admin();
$function$;

CREATE OR REPLACE FUNCTION public.cq_v4_parent_submissions()
 RETURNS TABLE(child_user_id uuid, chapter_uuid uuid, student_name text, chapter_title text, submitted_at timestamp with time zone, answers jsonb, feedback text, feedback_released boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT s.child_user_id, s.chapter_uuid,
         COALESCE(public.cq_v4_enrolled_display_name(c.parent_user_id,s.child_user_id), '계정 '||right(s.child_user_id::text,8))::text AS student_name,
         c.title AS chapter_title,
         s.submitted_at, s.answers, s.feedback, s.feedback_released
  FROM public.cq_v4_student_submissions s
  JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=s.chapter_uuid
  JOIN public.cq_v4_pdf_assignments a
    ON a.chapter_id=s.chapter_uuid AND a.student_user_id=s.child_user_id
  JOIN public.cq_v4_pdf_enrollments e
    ON e.parent_user_id=c.parent_user_id AND e.student_user_id=s.child_user_id
  WHERE c.parent_user_id=(SELECT auth.uid()) AND public.cq_is_admin()
  ORDER BY s.submitted_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.cq_v4_list_child_access(),public.cq_v4_parent_submissions() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_list_child_access(),public.cq_v4_parent_submissions() TO authenticated;
COMMIT;
