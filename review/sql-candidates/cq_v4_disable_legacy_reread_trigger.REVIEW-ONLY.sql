-- REVIEW ONLY. Run only in disposable PostgreSQL test databases.
-- Installation order: approval schema, reread progress table + completion RPC,
-- immutable snapshot schema, frozen reread helper, then submit RPC overlay.
-- Legacy AFTER INSERT scoring reads mutable approval requests and MUST NOT coexist.
DROP TRIGGER IF EXISTS cq_v4_reread_after_submit ON public.cq_v4_student_submissions;
DO $guard$
BEGIN
 IF EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='cq_v4_student_submissions'
    AND t.tgname='cq_v4_reread_after_submit' AND NOT t.tgisinternal
 ) THEN RAISE EXCEPTION 'Legacy mutable-key reread trigger still enabled'; END IF;
END $guard$;
-- Keep the legacy trigger function defined for rollback reference, but do not
-- re-enable it while cq_v4_submit_answers uses frozen snapshot grading.
