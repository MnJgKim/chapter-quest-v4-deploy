\set ON_ERROR_STOP on
-- Run only in the disposable CI database after the scheduler regression.
DO $$ BEGIN
 IF current_database() <> 'cq_v4_isolated' THEN RAISE EXCEPTION 'Wrong test database'; END IF;
END $$;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_id uuid;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS approval_hash text;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS vocabulary jsonb;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS writing_prompt text;
ALTER TABLE public.cq_v4_activities ADD COLUMN IF NOT EXISTS speaking_prompt text;
CREATE TABLE IF NOT EXISTS public.cq_v4_approval_requests(id uuid PRIMARY KEY,parent_user_id uuid,chapter_uuid uuid,answer_key jsonb,content_hash text,questions jsonb);
CREATE TABLE IF NOT EXISTS public.cq_v4_reread_progress(chapter_uuid uuid NOT NULL,child_user_id uuid NOT NULL,required boolean NOT NULL,completed_at timestamptz,PRIMARY KEY(chapter_uuid,child_user_id));
\ir ../../review/sql-candidates/cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/v4-integrated-optional-answers.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/v4-parent-frozen-result.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/v4-parent-material-preview.REVIEW-ONLY.sql
DO $$ BEGIN
 IF has_function_privilege('anon','public.cq_v4_parent_frozen_result(uuid,uuid)','EXECUTE') OR has_function_privilege('anon','public.cq_v4_parent_material_preview(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Anonymous access'; END IF;
 IF NOT has_function_privilege('authenticated','public.cq_v4_parent_material_preview(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Parent RPC unavailable'; END IF;
 IF has_function_privilege('authenticated','public.cq_v4_record_frozen_reread_internal(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Internal helper exposed'; END IF;
END $$;
\ir ../../review/sql-candidates/v4-integrated-optional-answers.rollback.REVIEW-ONLY.sql
\ir ../../review/sql-candidates/v4-integrated-optional-answers.REVIEW-ONLY.sql
\echo V4_INTEGRATED_INSTALL_ROLLBACK_ASSERTIONS_PASSED
