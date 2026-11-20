-- READ ONLY: export these results to a private, access-controlled backup location.
-- Never commit exported student records, answer keys, JWTs or credentials.
-- Run before any approved V3B migration and again after it.
SELECT current_database() AS database_name, current_setting('server_version') AS postgres_version, now() AS captured_at;
SELECT p.oid::regprocedure::text AS signature, pg_get_functiondef(p.oid) AS original_ddl,
 pg_get_userbyid(p.proowner) AS owner,
 p.prosecdef AS security_definer, p.proacl::text AS execution_acl
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('cq_v4_submit_answers','cq_v4_release_feedback','cq_v4_is_released',
  'cq_v4_complete_reread','cq_v4_my_reread_status','cq_v4_parent_reread_progress',
  'cq_v4_capture_grading_snapshot_internal','cq_v4_record_frozen_reread_internal')
ORDER BY signature;
SELECT c.oid::regclass::text AS table_name,t.tgname,pg_get_triggerdef(t.oid) AS trigger_ddl
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
WHERE c.oid IN ('public.cq_v4_student_submissions'::regclass,'public.cq_v4_activities'::regclass)
 AND NOT t.tgisinternal ORDER BY 1,2;
SELECT schemaname,tablename,policyname,roles,cmd,qual,with_check
FROM pg_policies WHERE schemaname IN ('public','storage')
 AND (tablename LIKE 'cq_v4_%' OR (schemaname='storage' AND tablename='objects'))
ORDER BY schemaname,tablename,policyname;
SELECT (SELECT count(*) FROM public.cq_v4_student_submissions) AS submissions,
 (SELECT count(*) FROM public.cq_v4_pdf_chapters) AS pdf_chapters,
 (SELECT count(*) FROM public.cq_v4_activities) AS activities,
 (SELECT count(*) FROM public.cq_v4_pdf_assignments) AS assignments;
-- This audit is NOT a physical backup. A separate verified restorable database
-- backup plus private Storage inventory and Cloudflare artifact are mandatory.
