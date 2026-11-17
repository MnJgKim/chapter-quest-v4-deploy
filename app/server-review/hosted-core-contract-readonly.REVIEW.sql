-- READ ONLY: existing hosted Chapter Quest V4 contract. No DDL, no writes, no credentials.
-- Run only through an authorized read-only connection. Missing names are reported, not created.
WITH expected(kind,name) AS (VALUES
 ('table','cq_v4_pdf_chapters'),('table','cq_v4_pdf_assignments'),
 ('table','cq_v4_student_submissions'),('table','cq_v4_lesson_schedule'),
 ('rpc','cq_is_admin'),('rpc','cq_v4_is_released'),('rpc','cq_v4_parent_schedule_lesson'),
 ('private_bucket','cq-v4-originals'),('private_bucket','cq-v4-speaking')
), observed AS (
 SELECT 'table'::text AS kind,table_name::text AS name
 FROM information_schema.tables WHERE table_schema='public'
 UNION ALL
 SELECT 'rpc',p.proname::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public'
 UNION ALL
 SELECT 'private_bucket',id::text FROM storage.buckets WHERE public=false
)
SELECT e.kind,e.name,EXISTS(SELECT 1 FROM observed o WHERE o.kind=e.kind AND o.name=e.name) AS present
FROM expected e ORDER BY e.kind,e.name;
