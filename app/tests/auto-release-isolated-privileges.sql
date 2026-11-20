-- Isolated PostgreSQL security checks; no production data writes.
DO $$
BEGIN
 IF has_table_privilege('authenticated','public.cq_v4_student_weekday_policy','INSERT')
 OR has_table_privilege('authenticated','public.cq_v4_student_weekday_policy','UPDATE')
 OR has_table_privilege('authenticated','public.cq_v4_approved_chapter_queue','INSERT')
 OR has_table_privilege('authenticated','public.cq_v4_approved_chapter_queue','DELETE')
 THEN RAISE EXCEPTION 'Direct authenticated write privilege granted'; END IF;
 IF has_function_privilege('anon','public.cq_v4_parent_set_weekdays(uuid,integer[],date,boolean)','EXECUTE')
 OR has_function_privilege('anon','public.cq_v4_parent_queue_approved_chapter(uuid,uuid,integer)','EXECUTE')
 OR has_function_privilege('anon','public.cq_v4_ensure_today_approved_lesson()','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous RPC privilege granted'; END IF;
 IF has_function_privilege('authenticated','public.cq_v4_ensure_approved_lesson_at(timestamptz)','EXECUTE')
 THEN RAISE EXCEPTION 'Internal clock override exposed'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.cq_v4_student_weekday_policy'::regclass)
 OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.cq_v4_approved_chapter_queue'::regclass)
 THEN RAISE EXCEPTION 'RLS disabled'; END IF;
 RAISE NOTICE 'AUTO_RELEASE_PRIVILEGE_ASSERTIONS_PASSED';
END $$;
