-- REVIEW ONLY. Prerequisite for student-auto-release-existing-schedule.REVIEW-ONLY.sql.
-- Apply in one approved transaction with that file, never to production without approval.
BEGIN;
CREATE TABLE IF NOT EXISTS public.cq_v4_student_weekday_policy (
 student_user_id uuid PRIMARY KEY,
 parent_user_id uuid NOT NULL,
 weekdays integer[] NOT NULL,
 enabled boolean NOT NULL DEFAULT true,
 effective_from date NOT NULL,
 CONSTRAINT cq_v4_weekdays_valid CHECK (
  cardinality(weekdays) BETWEEN 1 AND 7
  AND weekdays <@ ARRAY[1,2,3,4,5,6,7]::integer[]
  AND array_position(weekdays,NULL) IS NULL
 )
);
CREATE TABLE IF NOT EXISTS public.cq_v4_approved_chapter_queue (
 student_user_id uuid NOT NULL,
 parent_user_id uuid NOT NULL,
 chapter_id uuid NOT NULL,
 queue_position integer NOT NULL CHECK (queue_position > 0),
 approved_at timestamptz NOT NULL,
 PRIMARY KEY(student_user_id,chapter_id),
 UNIQUE(student_user_id,queue_position)
);
CREATE INDEX IF NOT EXISTS cq_v4_queue_order_idx
 ON public.cq_v4_approved_chapter_queue(student_user_id,queue_position);
ALTER TABLE public.cq_v4_student_weekday_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cq_v4_approved_chapter_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_student_weekday_policy, public.cq_v4_approved_chapter_queue FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.cq_v4_student_weekday_policy,public.cq_v4_approved_chapter_queue TO authenticated;
DROP POLICY IF EXISTS cq_v4_policy_owner_read ON public.cq_v4_student_weekday_policy;
CREATE POLICY cq_v4_policy_owner_read ON public.cq_v4_student_weekday_policy
 FOR SELECT TO authenticated USING (
 student_user_id=(SELECT auth.uid()) OR
 (parent_user_id=(SELECT auth.uid()) AND (SELECT public.cq_is_admin()))
 );
DROP POLICY IF EXISTS cq_v4_queue_owner_read ON public.cq_v4_approved_chapter_queue;
CREATE POLICY cq_v4_queue_owner_read ON public.cq_v4_approved_chapter_queue
 FOR SELECT TO authenticated USING (
 student_user_id=(SELECT auth.uid()) OR
 (parent_user_id=(SELECT auth.uid()) AND (SELECT public.cq_is_admin()))
 );
-- Parent writes are exclusively via audited SECURITY DEFINER RPCs.
CREATE OR REPLACE FUNCTION public.cq_v4_parent_set_weekdays(
 p_student uuid,p_weekdays integer[],p_effective_from date,p_enabled boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE v_parent uuid := (SELECT auth.uid());
BEGIN
 IF v_parent IS NULL OR NOT public.cq_is_admin() OR p_student IS NULL
 OR NOT EXISTS (SELECT 1 FROM public.cq_v4_pdf_enrollments e
 WHERE e.parent_user_id=v_parent AND e.student_user_id=p_student)
 THEN RAISE EXCEPTION 'Parent and enrolled student required' USING ERRCODE='42501'; END IF;
 IF p_weekdays IS NULL OR cardinality(p_weekdays) NOT BETWEEN 1 AND 7
 OR NOT p_weekdays <@ ARRAY[1,2,3,4,5,6,7]::integer[]
 OR array_position(p_weekdays,NULL) IS NOT NULL OR p_effective_from IS NULL
 THEN RAISE EXCEPTION 'Invalid weekday policy' USING ERRCODE='22023'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_student::text,731640));
 INSERT INTO public.cq_v4_student_weekday_policy(student_user_id,parent_user_id,weekdays,effective_from,enabled)
 VALUES(p_student,v_parent,p_weekdays,p_effective_from,coalesce(p_enabled,false))
 ON CONFLICT(student_user_id) DO UPDATE SET
 weekdays=excluded.weekdays,effective_from=excluded.effective_from,
 enabled=excluded.enabled WHERE public.cq_v4_student_weekday_policy.parent_user_id=v_parent;
 IF NOT FOUND THEN RAISE EXCEPTION 'Policy owner mismatch' USING ERRCODE='42501'; END IF;
END; $$;
CREATE OR REPLACE FUNCTION public.cq_v4_parent_queue_approved_chapter(
 p_student uuid,p_chapter uuid,p_position integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE v_parent uuid := (SELECT auth.uid());
BEGIN
 IF v_parent IS NULL OR NOT public.cq_is_admin() OR p_position IS NULL OR p_position<1
 OR NOT EXISTS (
 SELECT 1 FROM public.cq_v4_pdf_enrollments e
 JOIN public.cq_v4_pdf_chapters c ON c.parent_user_id=e.parent_user_id
 JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id AND a.student_user_id=e.student_user_id
 JOIN public.cq_v4_activities act ON act.chapter_uuid=c.chapter_id
 WHERE e.parent_user_id=v_parent AND e.student_user_id=p_student
 AND c.chapter_id=p_chapter AND c.pdf_ready IS TRUE AND act.published_at IS NOT NULL
 ) THEN RAISE EXCEPTION 'Approved assigned chapter and parent required' USING ERRCODE='42501'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_student::text,731640));
 IF EXISTS(SELECT 1 FROM public.cq_v4_approved_chapter_queue q
 WHERE q.student_user_id=p_student AND q.chapter_id=p_chapter AND q.parent_user_id<>v_parent)
 THEN RAISE EXCEPTION 'Queue owner mismatch' USING ERRCODE='42501'; END IF;
 INSERT INTO public.cq_v4_approved_chapter_queue(student_user_id,parent_user_id,chapter_id,queue_position,approved_at)
 VALUES(p_student,v_parent,p_chapter,p_position,pg_catalog.statement_timestamp())
 ON CONFLICT(student_user_id,chapter_id) DO UPDATE
 SET queue_position=excluded.queue_position
 WHERE public.cq_v4_approved_chapter_queue.parent_user_id=v_parent;
 IF NOT FOUND THEN RAISE EXCEPTION 'Queue owner mismatch' USING ERRCODE='42501'; END IF;
END; $$;
-- The student may inspect only their own next approved, not-yet-scheduled chapter.
CREATE OR REPLACE FUNCTION public.cq_v4_next_approved_chapter(p_student uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 SELECT q.chapter_id FROM public.cq_v4_approved_chapter_queue q
 JOIN public.cq_v4_pdf_enrollments e ON e.student_user_id=q.student_user_id
  AND e.parent_user_id=q.parent_user_id
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=q.chapter_id
  AND c.parent_user_id=q.parent_user_id AND c.pdf_ready IS TRUE
 JOIN public.cq_v4_pdf_assignments a ON a.student_user_id=q.student_user_id
  AND a.chapter_id=q.chapter_id
 JOIN public.cq_v4_activities act ON act.chapter_uuid=q.chapter_id
  AND act.published_at IS NOT NULL
 WHERE q.student_user_id=p_student AND p_student=(SELECT auth.uid())
 AND q.approved_at<=pg_catalog.statement_timestamp()
 AND NOT EXISTS (SELECT 1 FROM public.cq_v4_student_submissions sub
  WHERE sub.child_user_id=p_student AND sub.chapter_uuid=q.chapter_id)
 AND NOT EXISTS (SELECT 1 FROM public.cq_v4_lesson_schedule s
  WHERE s.student_user_id=p_student AND s.chapter_id=q.chapter_id)
 ORDER BY q.queue_position,q.chapter_id LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_set_weekdays(uuid,integer[],date,boolean),
 public.cq_v4_parent_queue_approved_chapter(uuid,uuid,integer),
 public.cq_v4_next_approved_chapter(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_set_weekdays(uuid,integer[],date,boolean),
 public.cq_v4_parent_queue_approved_chapter(uuid,uuid,integer),
 public.cq_v4_next_approved_chapter(uuid) TO authenticated;
COMMIT;
