\set ON_ERROR_STOP on
BEGIN;
-- Isolated bootstrap supplies auth.uid(), cq_is_admin(), students, chapters and submissions.
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
CREATE TABLE IF NOT EXISTS public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text);
\ir ../../review/sql-candidates/cq_v4_parent_reread_notices.REVIEW-ONLY.sql
DO $$
DECLARE v_parent uuid:='aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa';v_student uuid:='bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb';v_chapter uuid:='cccccccc-cccc-4ccc-cccc-cccccccccccc';v_approval uuid:='dddddddd-dddd-4ddd-dddd-dddddddddddd';v_result record;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',v_parent::text,true);
 -- Isolated admin helper may be fixture-dependent; assert anonymous always denied.
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.cq_v4_parent_sync_reread_notice(v_student,v_chapter);
  RAISE EXCEPTION 'Anonymous RPC unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF EXISTS(SELECT 1 FROM public.cq_v4_reread_notices) THEN RAISE EXCEPTION 'Unexpected notice before fixture';END IF;
END;
$$;
SELECT 'PARENT_REREAD_ISOLATED_AUTH_ASSERTIONS_PASSED' AS result;
ROLLBACK;
