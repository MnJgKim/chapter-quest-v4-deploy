# Reread warning — minimum viable production release plan (2026-11-20)

## Decision
Release the narrow reread workflow once deterministic data-integrity and authorization checks pass. Do not block release on observations that require a real lesson (layout preference, tablet ergonomics, timing, student behavior). Do not combine this release with AI question generation, Chapter 2 editing, or admin redesign.

## Confirmed baseline
- Isolated PostgreSQL 16 Actions #44691392438 succeeded for commit 1910799e2ff0dc3dcad83e936935fbbb5dbd35b9.
- Reviewed submission RPC now inserts submission, captures immutable grading snapshot, and records a reread decision within one transaction.
- Student reread warning is independent of parent feedback release. Parent feedback remains hidden until explicitly released.
- These are development/isolated results, NOT proof that production has the new RPCs.

## Exact installation order in a disposable environment first
1. Preserve and compare existing schema and function signatures. Take a consistent database backup, function definitions, Storage references, and current deployed Worker artifact. Never overwrite Zack Files, Magic Tree House #2 hidden chapters, approvals, or historical submissions.
2. Ensure approval metadata matches the published activity and immutable answer key; if a specific chapter fails, quarantine only that chapter from new submissions rather than rewriting historical records.
3. Install reread progress table, status/completion RPC and parent feedback gate from the development SQL **without installing its legacy mutable-key AFTER INSERT trigger**. Review this file and split out that trigger at deployment packaging time.
4. Install immutable snapshot candidate, then frozen reread helper, then run cq_v4_disable_legacy_reread_trigger.REVIEW-ONLY.sql, then install cq_v4_submit_with_frozen_snapshot.REVIEW-ONLY.sql. No new client grants on internal helpers.
5. Validate 6/10 requires reread, 7/10 does not; missing/invalid answer key and 0 MC fail closed; existing submissions are not regraded; concurrent submission yields exactly one immutable snapshot and one reread decision; failed grading rolls back submission.
6. Validate student can only read their own reread status and complete it; parent cannot input or release feedback until completion when required; answers and feedback are not exposed to students before release.
7. Build and deploy only the matching student/parent UI after explicit production approval; perform a non-destructive smoke test using a dedicated authorized test account/chapter, never real student records.

## Two-stage activation and observation
- Stage A: isolated database + deployable release package, full server security tests and rollback artifacts.
- Stage B: after explicit production approval, backup and install server RPCs, then matching Worker UI; verify test account flow. Enable for first real class, monitor error reports, correct usability issues after real lessons.
- If a real lesson reveals layout, PDF reread navigation, or device-specific issues, fix in a separate frontend patch without touching immutable submissions.

## Stop conditions (not optional)
- Inability to prove backup/restore path, failed authorization/answer-key secrecy tests, missing snapshot or inconsistent transaction rollback, incompatible production schema, or a failed migration transaction.
- Do not treat untested real-class usability as a stop condition.

## Rollback
- Restore previous Worker version and previous RPC definitions from exact backups. Revert newly added functions/triggers only after checking dependencies and whether new submissions were created; do not drop immutable snapshot/progress rows or overwrite new student submissions. If new data exists, prefer forward-compatible corrective migration over destructive rollback.
- Record migration IDs, function checksums, Actions ID, and post-deploy smoke results before activating real lessons.

## Explicit exclusions
No PR merge, no production SQL, no Cloudflare deployment, no PDF or student-data mutation without separate user authorization. This plan does not itself authorize those operations.
