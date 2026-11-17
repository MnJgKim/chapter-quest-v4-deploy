-- READ ONLY. For manual authenticated review of the EXISTING hosted project.
-- No DDL, no DML, no secret values, no student rows.
-- Results may contain function names and policy definitions: treat as internal configuration.
SELECT 'table' AS kind, table_schema AS namespace, table_name AS object_name
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name LIKE 'cq_v4_%'
UNION ALL
SELECT 'function', n.nspname, p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND (p.proname LIKE 'cq_v4_%' OR p.proname = 'cq_is_admin')
ORDER BY kind, namespace, object_name;

SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename LIKE 'cq_v4_%'
ORDER BY tablename;

SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE (schemaname='public' AND tablename LIKE 'cq_v4_%')
   OR (schemaname='storage' AND tablename='objects')
ORDER BY schemaname, tablename, policyname;

SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id IN ('cq-v4-originals','cq-v4-speaking')
ORDER BY id;

-- Not a proof of permission correctness. No mutation is authorized by this file.
