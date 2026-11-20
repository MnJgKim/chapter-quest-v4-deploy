# V3B non-destructive rollback and approval gate (REVIEW ONLY)

## Absolute preconditions
- Do not apply the install bundle or any rollback without explicit separate approval.
- Obtain and verify a **restorable** consistent database backup (including auth and storage metadata) and preserve the actual Storage files and current Cloudflare release. A read-only SQL inventory is not a backup.
- In a restricted backup location, export `pg_get_functiondef`, `pg_get_triggerdef`, function ownership, EXECUTE ACL, RLS policies and schema counts immediately before the change. Never commit child answers, student data or answer keys.
- Verify production schema drift against the baseline; abort if signatures, owners or grants differ.

## Installation
- Run the reviewed bundle once in a controlled transaction, then inspect table/function ownership, RLS and grants. Its internal BEGIN/COMMIT means the client must not add a nested transaction or split statements.
- Do not deploy Cloudflare until DB smoke checks succeed and parent approval is obtained.
- Preserve existing release schedule, chapters, hidden chapters, PDF files, assignments, student submissions, feedback and recordings.

## Rollback after a new student submits
1. **Do not delete** `cq_v4_immutable_grading_snapshots`, `cq_v4_reread_progress`, or any newly created student submissions. These may contain the only frozen approval and scoring evidence for a new submission.
2. Stop new submissions temporarily at the application boundary during the controlled rollback window; preserve existing submission records. Record a private, timestamped inventory.
3. In one transaction, restore the **captured pre-deploy** `cq_v4_submit_answers(uuid,jsonb)` and `cq_v4_release_feedback(uuid,uuid,text,boolean)` definitions and original function EXECUTE grants. Do not restore guessed SQL from the repository or a stale backup.
4. Retain new snapshot/progress tables and their restrictive RLS/grants. Retain new helper functions with PUBLIC/anon/authenticated EXECUTE revoked until they can be safely retired in a separate reviewed migration.
5. Verify old submission flow, assignment/release checks, parent feedback and historical student records, then resume the application only after approval. Restore the previous Cloudflare deployment separately if it was changed.
6. If the prior RPC is incompatible with a new student's record, stop and use the verified restore-capable backup and a forward-fix plan; do not drop tables or rewrite student answers.

## Blocking issues
- Backup availability and a test restore have not been verified through the available connector. **Production deployment blocked.**
- A successful disposable PostgreSQL install test does not prove that the production DB has a restorable backup, that Cloudflare rollback works, or that the application can display the new feedback states.
- Capture a production pre-deploy inventory immediately before any approved change and compare post-change counts. Never treat historical counts as fixed invariants.
