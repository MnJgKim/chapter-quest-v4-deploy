-- REVIEW ONLY. Never apply to production without separate approval and isolated DB tests.
-- Parent notice state is additive; do not modify submissions, reread progress, or schedules.
CREATE TABLE IF NOT EXISTS public.cq_v4_parent_reread_notices (
  notice_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chapter_uuid uuid NOT NULL,
  student_user_id uuid NOT NULL,
  acknowledged_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cq_v4_parent_reread_notice_once UNIQUE(chapter_uuid,student_user_id),
  CONSTRAINT cq_v4_parent_reread_notice_progress_fkey
    FOREIGN KEY (chapter_uuid,student_user_id)
    REFERENCES public.cq_v4_reread_progress(chapter_uuid,child_user_id)
);
ALTER TABLE public.cq_v4_parent_reread_notices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_parent_reread_notices FROM PUBLIC, anon, authenticated;
-- Only SECURITY DEFINER RPCs below may read/write notices.
CREATE OR REPLACE FUNCTION public.cq_v4_parent_reread_inbox()
RETURNS TABLE(notice_id uuid, student_user_id uuid, chapter_uuid uuid,
  correct_mc integer, total_mc integer, submitted_at timestamptz,
  acknowledged_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
BEGIN
 IF auth.uid() IS NULL OR NOT public.cq_is_admin()
 THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 -- Backfill eligible rereads idempotently on parent read. This does not modify student data.
 INSERT INTO public.cq_v4_parent_reread_notices(chapter_uuid,student_user_id)
 SELECT r.chapter_uuid,r.child_user_id
 FROM public.cq_v4_reread_progress r
 JOIN public.cq_v4_student_submissions s
   ON s.chapter_uuid=r.chapter_uuid AND s.child_user_id=r.child_user_id
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=r.chapter_uuid
 JOIN public.cq_v4_pdf_assignments a
   ON a.chapter_id=r.chapter_uuid AND a.student_user_id=r.child_user_id
 JOIN public.cq_v4_pdf_enrollments e
   ON e.parent_user_id=c.parent_user_id AND e.student_user_id=r.child_user_id
 WHERE c.parent_user_id=auth.uid() AND r.required IS TRUE
 ON CONFLICT(chapter_uuid,student_user_id) DO NOTHING;
 RETURN QUERY
 SELECT n.notice_id,n.student_user_id,n.chapter_uuid,
        0::integer AS correct_mc, 1::integer AS total_mc,
        s.submitted_at,n.acknowledged_at
 FROM public.cq_v4_parent_reread_notices n
 JOIN public.cq_v4_reread_progress r
   ON r.chapter_uuid=n.chapter_uuid AND r.child_user_id=n.student_user_id AND r.required
 JOIN public.cq_v4_student_submissions s
   ON s.chapter_uuid=n.chapter_uuid AND s.child_user_id=n.student_user_id
 JOIN public.cq_v4_pdf_chapters c ON c.chapter_id=n.chapter_uuid
 JOIN public.cq_v4_pdf_assignments a
   ON a.chapter_id=c.chapter_id AND a.student_user_id=n.student_user_id
 JOIN public.cq_v4_pdf_enrollments e
   ON e.parent_user_id=c.parent_user_id AND e.student_user_id=n.student_user_id
 WHERE c.parent_user_id=auth.uid()
 ORDER BY s.submitted_at DESC;
END $function$;
CREATE OR REPLACE FUNCTION public.cq_v4_parent_ack_reread_notice(p_notice uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE v_updated boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT public.cq_is_admin()
 THEN RAISE EXCEPTION 'Parent authorization required' USING ERRCODE='42501'; END IF;
 UPDATE public.cq_v4_parent_reread_notices n
 SET acknowledged_at=COALESCE(n.acknowledged_at,now())
 WHERE n.notice_id=p_notice AND EXISTS (
   SELECT 1 FROM public.cq_v4_pdf_chapters c
   JOIN public.cq_v4_pdf_assignments a ON a.chapter_id=c.chapter_id
   JOIN public.cq_v4_pdf_enrollments e
     ON e.parent_user_id=c.parent_user_id AND e.student_user_id=a.student_user_id
   WHERE c.chapter_id=n.chapter_uuid AND a.student_user_id=n.student_user_id
     AND c.parent_user_id=auth.uid()
 );
 GET DIAGNOSTICS v_updated = ROW_COUNT;
 RETURN v_updated;
END $function$;
REVOKE ALL ON FUNCTION public.cq_v4_parent_reread_inbox() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cq_v4_parent_ack_reread_notice(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_reread_inbox() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cq_v4_parent_ack_reread_notice(uuid) TO authenticated;
