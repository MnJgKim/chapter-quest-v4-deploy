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

## Production read-only recheck — 2026-11-21 (no writes)
- Confirmed 15 schedule rows, 0 student/date duplicates, 1 submission and 0 reread progress rows.
- Confirmed `cq_v4_lesson_schedule.student_user_id` is UUID NOT NULL and `lesson_date` is DATE NOT NULL; the current PK is (student_user_id, chapter_id). The proposed student/date index is absent.
- Confirmed `cq_v4_reread_progress` PK is (chapter_uuid, child_user_id), compatible with the proposed notice FK. Notice table and both proposed notice RPCs are absent.
- Confirmed `cq_is_admin()` is owned by postgres, SECURITY DEFINER, with empty search path, and checks `public.cq_admins` against `auth.uid()`. The existing `cq_v4_parent_reread_progress()` is likewise owned by postgres and filters chapter ownership, assignments and enrollments.
- Confirmed RLS enabled for schedule, progress, submissions, chapters, assignments and enrollments. Authenticated has no direct SELECT privilege on schedule, reread progress or submissions; anon has no direct SELECT privilege on these six tables. The RPC needs definer privileges but must enforce its own parent checks.
- These are metadata and count checks only, **not** a full restored production-schema migration rehearsal. Do not mark the latter complete.
- Prior Actions run 44881474807 passed 30/30 tests in synthetic isolated environments, not a production schema restore.

## Isolated SQL rehearsal evidence — Actions #44884531686
- Both CI jobs succeeded: 4 static, 12 PGlite, 2 independent-connection, 5 concurrent-index, 7 real-role RPC, and 5 production-shaped installation/rollback assertions (35 total).
- The last five checks used a **synthetic** PostgreSQL 17 database matching selected observed production columns and keys, NOT a restore of the production backup. They covered draft SQL installation, admin inbox/acknowledgement, preservation of synthetic schedule/submission/reread rows, RPC rollback with notice acknowledgement retained, and concurrent index rollback with lesson timestamps intact.
- Historical isolated restore evidence (PostgreSQL 17 restore_check_v3, exit code 0; 61 tables, 50 RLS-enabled tables, 65 functions) was reported separately; the actual dump bytes, backup timestamp, restore logs and access to that restored database have NOT been independently retrieved in this stage. It must not be counted as the required full production-backup migration rehearsal.

### Required production-backup rehearsal before approval
1. Locate the actual backup artifact in the authorized Codespaces or backup storage, verify size, SHA-256, creation time, and safe custody. Do not upload the dump to public GitHub or CI artifacts; it may contain real student data.
2. Restore into an access-controlled, network-isolated PostgreSQL 17 database with no production credentials or outbound production connections; capture pg_restore exit code and object counts, and compare schema, grants, policies, triggers, and function definitions. Stop if extensions/roles are missing or restore reports unreviewed errors.
3. Verify duplicate student/date audit is empty; inspect actual object collisions and index state; capture row counts and immutable digests of schedules, submissions, and reread progress.
4. On that restored database only, install the notice draft and create the schedule index CONCURRENTLY outside a transaction; verify the role/JWT access matrix and data preservation, then rehearse the reviewed rollback in dependency-safe order.
5. Compare pre/post digests and original lesson_date/released_at/submitted_at values. Record sanitized test evidence, never student records or credentials.
6. Recheck the **live** read-only preflight immediately before any separately authorized deployment; a historical backup cannot establish current live state.

**Current gate:** production-backup artifact inaccessible/unverified in this review session; restore-based migration rehearsal is NOT complete. No production migration, Worker deployment or PR merge is approved.
