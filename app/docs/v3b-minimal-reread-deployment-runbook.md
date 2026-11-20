# V3B minimal reread deployment — operator runbook (review only)

Target: Supabase project ftffxetmqditfqdvzjdd (english-v3b-test). No automatic production mutations.

## Baseline before approval
- Read-only inventory: activity 17, verified approval provenance 7, 10 not fully matched, submissions 1 (as of 2026-11-20). Re-query immediately before deployment; these counts are not migration assertions.
- Preserve all Zack Files / Magic Tree House #2 chapters, Storage PDFs, hidden chapters, assignments, historical submissions and feedback.
- Export **actual current** function definitions for cq_v4_submit_answers(uuid,jsonb), cq_v4_release_feedback, cq_v4_is_released, all affected triggers, policies and grants. Record pg_get_functiondef, pg_get_triggerdef, pg_get_expr, pg_get_userbyid, and schema hashes. Store in access-controlled backup, not public repository.
- Obtain an independent consistent DB backup with verified restore capability and preserve deployed Cloudflare artifact/version; no destructive rollback.

## Reviewed installation sequence, single controlled maintenance window
1. Verify live RPC signature, current definition and privileges match the captured V3B baseline; abort on drift.
2. In one transaction, create immutable snapshot schema and its write-denial guard from cq_v4_immutable_grading_snapshot.REVIEW-ONLY.sql.
3. Install the reread progress table, authenticated status/completion RPCs and parent feedback gate **extracted and reviewed** from development-reread-progress-not-for-production.sql. Do not install the old mutable-answer AFTER INSERT trigger.
4. Install cq_v4_frozen_reread_atomic.REVIEW-ONLY.sql, then cq_v4_disable_legacy_reread_trigger.REVIEW-ONLY.sql. Verify no other trigger on submissions grades mutable answers.
5. Install cq_v4_submit_v3b_minimal_reread.REVIEW-ONLY.sql. It retains live V3B cq_v4_is_released, assignment, recording and answer validation, and grades only new verified approvals. Do not replace with cq_v4_submit_with_frozen_snapshot.REVIEW-ONLY.sql (different scheduling gate).
6. Validate owner, SECURITY DEFINER search_path, EXECUTE grants and RLS; snapshot tables and internal grading functions must not be readable or executable by authenticated/anon. Verify parent feedback cannot be entered or released before reread completion.
7. Commit only after all SQL checks pass; use a test student/chapter authorized for this purpose to smoke test, not existing student submissions.
8. Deploy matching student/parent UI after explicit approval; observe real-class usability after release.

## Safety gates
- Any failed restore rehearsal, unexpected live function drift, unauthorized access to answer keys, invalid grading atomicity or missing parent gate blocks deployment.
- Missing approval provenance for the 10 legacy chapters is **not** a blocker for their existing submission path; do not synthesize scores or retroactively grade.
- A verified-approval chapter with zero scorable MC or invalid frozen answer key fails closed; reconcile that specific chapter before student use, never bypass answer-key checks globally.

## Rollback / forward fix
- Restore previous Cloudflare artifact first if UI causes a regression.
- Restore prior function definitions/permissions only after checking whether new snapshots or submissions were written. Never delete new student records or snapshot rows to make old schema fit. Prefer a forward-compatible SQL fix when new data exists.
- Keep the frozen snapshots/progress tables intact; use a transactional corrective migration, not wholesale database restore, for live data.

## Explicit non-goals
- No PR merge, production SQL execution, Cloudflare deployment or modification of existing PDF/student data before separate user approval.
- Mobile/tablet ergonomics and first-lesson behavior are post-deploy observation tasks, not pre-deploy safety blockers.
