# Student reread release preflight — 2026-11-20

Development-only release gate. **No production changes authorized.**

## Verified evidence
- GitHub Actions run 44681493302 on commit c4ef9350a201ba2a3efd01b278c7b43f4411ca7d: all jobs passed, including PostgreSQL 16 reread submission and parent lesson fixtures.
- Read-only production schema: public.cq_v4_submit_answers(uuid,jsonb) checks release/assignment, complete answers and recording, then inserts into cq_v4_student_submissions with ON CONFLICT DO NOTHING.
- Production has no non-internal trigger on cq_v4_student_submissions.
- 17 published activities: 9 without approval_id, 1 published/approved question mismatch. The approval_requests table contains answer_key; activities has no answer_key column.
- No authenticated end-to-end student browser run yet.

## Release blockers
1. Ensure an authoritative answer key is atomically bound to the exact published question set at approval/publication. A missing key is an error, never a passing grade; do not invent or infer answers. Preserve all legacy activities and approvals.
2. Validate real submission RPC + immutable snapshot transaction with the reread AFTER INSERT trigger; the current fixture only models the submission table, not full production triggers and recording.
3. Verify student UI after submit and lost-response recovery; 60% must warn, exactly 70% must not, 80% must not; error state must not masquerade as a pass.
4. Verify auth and RLS for status and completion; verify parent feedback gate and rollback behavior.
5. Verify full backup of schema/function definitions and existing student submissions, approval records, published activities and snapshots. Do not store student data in repository.
6. Prepare and rehearse rollback in isolated PostgreSQL. Rollback must remove only newly introduced reread trigger/functions/table after dependency and data preservation review. Never delete submitted student data or restore old activity rows blindly.
7. Review Worker deployment diff and restore previous known-good Worker version if deployment fails. Production changes require separate user approval.

## Proposed deployment order (not executed)
A. Approve and publish atomic question+answer-key storage for new chapters.
B. Repair legacy key provenance with evidence, excluding Magic Tree House Book 2 Chapter 2 from this change.
C. Back up production and capture rollback artifacts.
D. Apply reviewed SQL in an approved maintenance window.
E. Deploy reviewed Worker/frontend only after SQL smoke tests.
F. Test authorized student submission and parent review; monitor and roll back on failure.

**Status: NOT READY TO DEPLOY.**
