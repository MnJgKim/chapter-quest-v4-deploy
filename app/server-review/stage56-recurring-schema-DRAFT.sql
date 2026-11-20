-- STAGE 56 DEVELOPMENT DRAFT. DO NOT RUN AGAINST PRODUCTION.
-- PostgreSQL schema foundation only. Scheduler/RPC contracts remain unimplemented.
-- Fail-closed until transactional scheduler, queue RPCs and integration tests exist.
BEGIN;
CREATE TABLE IF NOT EXISTS public.cq_v4_recurring_config (
  parent_user_id uuid NOT NULL,
  student_user_id uuid NOT NULL,
  weekdays integer[] NOT NULL,
  enabled boolean NOT NULL DEFAULT false,
  effective_from date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(parent_user_id,student_user_id),
  CONSTRAINT cq_v4_weekdays_valid CHECK (
    cardinality(weekdays) BETWEEN 1 AND 7
    AND weekdays <@ ARRAY[1,2,3,4,5,6,7]::integer[]
  )
);
CREATE TABLE IF NOT EXISTS public.cq_v4_recurring_queue (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  parent_user_id uuid NOT NULL,
  student_user_id uuid NOT NULL,
  book_title text NOT NULL CHECK(length(trim(book_title))>0),
  chapter_number integer NOT NULL CHECK(chapter_number>0),
  chapter_uuid uuid NOT NULL REFERENCES public.cq_v4_pdf_chapters(chapter_id),
  approval_id uuid REFERENCES public.cq_v4_approval_requests(id),
  ends_book boolean NOT NULL DEFAULT false,
  state text NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','released','withdrawn')),
  queued_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  CONSTRAINT cq_v4_recurring_queue_unique UNIQUE(parent_user_id,student_user_id,book_title,chapter_number),
  CONSTRAINT cq_v4_recurring_release_consistency CHECK ((state='released')=(released_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS cq_v4_recurring_next_idx
 ON public.cq_v4_recurring_queue(parent_user_id,student_user_id,state,chapter_number);
ALTER TABLE public.cq_v4_recurring_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cq_v4_recurring_queue ENABLE ROW LEVEL SECURITY;
-- No direct writes from browser. Even parent must go through audited RPC after review.
REVOKE ALL ON public.cq_v4_recurring_config FROM PUBLIC,anon,authenticated;
REVOKE ALL ON public.cq_v4_recurring_queue FROM PUBLIC,anon,authenticated;
-- Explicit parent-only SELECT for authenticated parent; RLS is defense-in-depth.
GRANT SELECT ON public.cq_v4_recurring_config TO authenticated;
GRANT SELECT ON public.cq_v4_recurring_queue TO authenticated;
CREATE POLICY cq_v4_recurring_config_parent_read
 ON public.cq_v4_recurring_config FOR SELECT TO authenticated
 USING (parent_user_id=(select auth.uid()) AND public.cq_is_admin());
CREATE POLICY cq_v4_recurring_queue_parent_read
 ON public.cq_v4_recurring_queue FOR SELECT TO authenticated
 USING (parent_user_id=(select auth.uid()) AND public.cq_is_admin());
COMMIT;
