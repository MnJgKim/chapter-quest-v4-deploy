-- REVIEW ONLY. Never execute on production without schema/ownership review.
-- An explicit parent-approved ordinal prevents UUID/title sorting from choosing chapters.
-- This queue does NOT create assignments or publish materials.
CREATE TABLE IF NOT EXISTS public.cq_v4_approved_chapter_queue (
 parent_user_id uuid NOT NULL,
 student_user_id uuid NOT NULL,
 chapter_id uuid NOT NULL,
 ordinal integer NOT NULL CHECK (ordinal > 0),
 approved_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (student_user_id,chapter_id),
 UNIQUE (student_user_id,ordinal)
);
ALTER TABLE public.cq_v4_approved_chapter_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cq_v4_approved_chapter_queue FROM PUBLIC,anon,authenticated;
-- Read-only next-chapter candidate. Returns only explicitly queued AND already
-- assigned chapters, with approved PDF, published activity, and enrollment.
-- SECURITY DEFINER avoids client-side RLS bypass; auth.uid must match student.
CREATE OR REPLACE FUNCTION public.cq_v4_next_approved_chapter(p_student uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
 SELECT q.chapter_id
 FROM public.cq_v4_approved_chapter_queue q
 JOIN public.cq_v4_pdf_chapters c
   ON c.chapter_id=q.chapter_id AND c.parent_user_id=q.parent_user_id AND c.pdf_ready IS TRUE
 JOIN public.cq_v4_pdf_assignments a
   ON a.chapter_id=q.chapter_id AND a.student_user_id=q.student_user_id
 JOIN public.cq_v4_pdf_enrollments e
   ON e.parent_user_id=q.parent_user_id AND e.student_user_id=q.student_user_id
 JOIN public.cq_v4_activities act
   ON act.chapter_uuid=q.chapter_id AND act.published_at IS NOT NULL
 WHERE p_student=(SELECT auth.uid()) AND q.student_user_id=p_student
   AND NOT EXISTS (
     SELECT 1 FROM public.cq_v4_student_submissions done
     WHERE done.child_user_id=p_student AND done.chapter_uuid=q.chapter_id
   )
   -- Never skip an earlier approved but unready/unsubmitted chapter.
   AND NOT EXISTS (
     SELECT 1 FROM public.cq_v4_approved_chapter_queue prior
     WHERE prior.student_user_id=q.student_user_id AND prior.ordinal<q.ordinal
       AND NOT EXISTS (
         SELECT 1 FROM public.cq_v4_student_submissions done_prior
         WHERE done_prior.child_user_id=p_student AND done_prior.chapter_uuid=prior.chapter_id
       )
   )
 ORDER BY q.ordinal
 LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.cq_v4_next_approved_chapter(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.cq_v4_next_approved_chapter(uuid) TO authenticated;
-- BLOCKER: this function is a candidate lookup, NOT automatic release.
-- The existing schedule table, weekday policy and audited makeup overrides
-- need a separate transaction-safe coordinator and isolated security tests.
-- Parent approval writes require an authenticated, ownership-checked RPC.
