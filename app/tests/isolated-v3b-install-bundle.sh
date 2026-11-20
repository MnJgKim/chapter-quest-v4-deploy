#!/usr/bin/env bash
set -euo pipefail
# Disposable local PostgreSQL only. Never point PGHOST/PGDATABASE at Supabase.
db="cq_v4_v3b_bundle_$$"
psql -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE $db"
trap 'psql -v ON_ERROR_STOP=1 -d postgres -c "DROP DATABASE IF EXISTS '"$db"'" >/dev/null' EXIT
export PGDATABASE="$db"
# Roles are cluster-wide; the CI job already created anon/authenticated in its first bootstrap.
# Strip only these two role creation lines for this new disposable database.
sed -e '/^CREATE ROLE anon NOLOGIN;$/d' -e '/^CREATE ROLE authenticated NOLOGIN;$/d' app/tests/isolated-postgres-bootstrap.sql | psql -v ON_ERROR_STOP=1 >/dev/null
psql -v ON_ERROR_STOP=1 -f review/sql-candidates/cq_v4_v3b_reread_install_bundle.REVIEW-ONLY.sql >/dev/null
psql -v ON_ERROR_STOP=1 <<'SQL'
DO $verify$
BEGIN
 IF to_regclass('public.cq_v4_immutable_grading_snapshots') IS NULL
 OR to_regclass('public.cq_v4_reread_progress') IS NULL
 OR to_regprocedure('public.cq_v4_submit_answers(uuid,jsonb)') IS NULL
 OR to_regprocedure('public.cq_v4_complete_reread(uuid)') IS NULL
 OR to_regprocedure('public.cq_v4_release_feedback(uuid,uuid,text,boolean)') IS NULL
 THEN RAISE EXCEPTION 'Installation bundle missing required schema';END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='cq_v4_reread_after_submit' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'Legacy mutable scoring trigger installed';END IF;
 IF has_table_privilege('authenticated','public.cq_v4_immutable_grading_snapshots','SELECT')
 OR has_table_privilege('authenticated','public.cq_v4_reread_progress','UPDATE')
 OR has_function_privilege('authenticated','public.cq_v4_capture_grading_snapshot_internal(uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon','public.cq_v4_record_frozen_reread_internal(uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Answer-key or scoring privilege leaked';END IF;
END $verify$;
SQL
echo 'V3B_INSTALL_BUNDLE_POSTGRES_ASSERTIONS_PASSED'
