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

-- Separate planned-hosted objects from the existing launch contract.
-- These are NOT automatically installed, and a missing item must not be reported as a broken existing feature.
WITH planned(kind,name) AS (VALUES
 ('table','cq_v4_books'),('table','cq_v4_book_chapters'),
 ('table','cq_v4_auto_release_policies'),('table','cq_v4_auto_release_arms'),
 ('table','cq_v4_auto_release_cancellations'),
 ('rpc','cq_v4_parent_schedule_auto_week'),
 ('rpc','cq_v4_parent_list_auto_release_policies')
)
SELECT p.kind,p.name,
 CASE WHEN p.kind='table' THEN EXISTS(
   SELECT 1 FROM information_schema.tables t WHERE t.table_schema='public' AND t.table_name=p.name
 ) ELSE EXISTS(
   SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace
   WHERE n.nspname='public' AND f.proname=p.name
 ) END AS installed,
 'PLANNED_ONLY_REQUIRES_SEPARATE_APPROVAL'::text AS deployment_gate
FROM planned p ORDER BY p.kind,p.name;
