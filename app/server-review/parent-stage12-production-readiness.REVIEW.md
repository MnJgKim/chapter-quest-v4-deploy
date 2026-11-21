# Parent stage 12: production readiness and rollback (REVIEW ONLY)

**Status:** Not approved for production. Do not execute the draft SQL on the live project, deploy a Worker, or merge a PR without explicit authorization.

## Verified baseline
- GitHub Actions run 44848335476: 4/4 source-contract checks, 12/12 isolated PGlite assertions, 2/2 independent PostgreSQL connection assertions.
- Production read-only inspection: 15 scheduled lessons, 0 duplicate (student_user_id, lesson_date) pairs, 1 submission, 0 reread progress rows.
- Production does **not** yet contain the student/day unique index, the reread notice table, or the two notice RPCs.
- The existing schedule PK is (student_user_id, chapter_id); the proposed index is additional.
- All isolated tests used synthetic data, not production identities or live traffic.

## Mandatory preflight (read-only)
1. Confirm fresh production backup/restore evidence and current GitHub commit; do not assume prior backup still covers new writes.
2. Repeat duplicate audit immediately before migration:
   `SELECT student_user_id, lesson_date, count(*) FROM public.cq_v4_lesson_schedule GROUP BY 1,2 HAVING count(*) > 1;`
   Must return zero rows.
3. Inspect index, table and RPC existence, signatures, ownership, RLS and ACLs. Stop if any object exists with unexpected definition.
4. Verify `cq_is_admin()` trusts an authorization-controlled source and `auth.uid()` is evaluated for the invoking authenticated user. Do not grant table privileges to `anon` or `authenticated`.
5. Recheck parent/chapter/assignment/enrollment joins against actual production schema, including FK/PK constraints. Validate `SECURITY DEFINER` owner and `search_path=''` in a production-shaped isolated restore.
6. Confirm deployment order: database additions before parent UI calls; test both RPCs with real authenticated JWTs in a safe environment before production use.

## Schedule unique index: lock and rollback
- The current draft uses ordinary `CREATE UNIQUE INDEX`, which can block writes during index build. Prefer a separately reviewed `CREATE UNIQUE INDEX CONCURRENTLY` migration for a live system.
- Concurrent index creation must be run **outside an explicit transaction**. Set and verify appropriate `lock_timeout` and `statement_timeout`; the migration executor must support non-transactional statements.
- Concurrent builds can fail and leave an INVALID index. Inspect `pg_index.indisvalid` and `pg_index.indisready` before retrying; remove only the newly-created invalid index after authorization.
- If duplicate rows appear after the preflight audit, stop; never delete or rewrite student schedules automatically.
- Approved rollback (separate, outside transaction if concurrent): `DROP INDEX CONCURRENTLY IF EXISTS public.cq_v4_lesson_schedule_student_day_unique;`. Confirm the index is owned by this migration before dropping.
- Removing the index restores previous collision exposure. It does not roll back or alter student lesson rows.

## Reread notices: privileged-function and rollback review
- The proposed table references `cq_v4_reread_progress(chapter_uuid, child_user_id)` and stores acknowledgement only. No existing submissions, reread progress, or schedule rows should be updated.
- The inbox function is **not read-only**: it idempotently INSERTs eligible notices during a parent inbox read. Treat calls as writes for audit, latency, and concurrency review.
- `CREATE TABLE IF NOT EXISTS` does not verify an existing table's constraints. A name collision or unexpected schema must stop deployment.
- `SECURITY DEFINER` can bypass RLS. Verify exact function owner and all privileges, fully qualified object references, parent ownership predicates, cross-parent tests, and direct table access denial.
- The RPC intentionally returns NULL for MC scores: existing progress data has no trustworthy numerator/denominator. Never fabricate scores.
- Revoke PUBLIC/anon EXECUTE and grant only authenticated EXECUTE. Confirm default EXECUTE privileges and test actual `anon`, `authenticated`, unrelated-parent and outsider roles in a production-shaped isolated restore.
- Recommended safe rollback order, **only after approval and dependency inspection**: disable UI calls; revoke EXECUTE; drop only the two newly-created RPCs if they have no dependents. Preserve the notices table and acknowledgement data by default. Drop the table only with separate explicit data-loss authorization.
- The function names must be checked for preexisting signatures before `CREATE OR REPLACE` so existing functions cannot be silently overwritten.

## Stop conditions
- Unexpected existing object, nonzero duplicate audit, stale backup, failed restore rehearsal, missing parent authorization checks, unsupported migration transaction mode, production-shaped test failure, or changed first-lesson schedule.
- No production write, Worker deployment, PR merge or destructive rollback is authorized by this document.

## Remaining validation
- Restore current production-shaped schema to an isolated database and execute reviewed migration there; test JWT/role authorization, concurrent index creation/failure/retry, rollback, and exact row/timestamp preservation.
- Reconcile UI RPC response contracts and confirm first lessons remain unaffected.
