# Chapter 2 correction decision — preserve all 10 published questions

Target UUID: `8fe27ea2-b1ce-4404-a5bf-75b5a049a38a`.
Parent clarification: questions 7–10 MUST NOT disappear.

## Verified read-only production state
- Approved: 6 MC questions with keys `[1,3,0,1,1,0]`.
- Published: the same first 6 MC, plus #7 MC, #8–9 short, #10 inference.
- #7 asks the Pennsylvania silk bookmark color; choices [Blue, Red, Green, Yellow], expected index **1** (Red), subject to final source confirmation.
- Proposed aligned keys for 10 published questions: `[1,3,0,1,1,0,1,null,null,null]`.
- Student assignments: 2; submissions: 0; approvals: 1; activities: 1 (read-only check).
- Approval hash currently matches published approval ID but the published question array does not match approved array.

## Required behavior
- Preserve the exact 10 published questions unless parent separately approves a wording correction.
- Do not run `development-chapter2-restore-approved-questions-not-for-production.sql`: that restores only 6 questions and drops 7–10.
- Create a NEW, immutable parent-approved approval request for the 10-question payload, with aligned 10-entry answer_key, and bind to the SAME chapter via a tested in-place replacement RPC.
- Preserve previous approval row, PDF, chapter UUID, two assignments, and all historical submissions/snapshots.
- Verify approval hash recomputation matches the production registration algorithm (not assumed md5 algorithm), ensure reread scoring uses 7 MC only, and ensure parent/student feedback contract.
- Existing replacement RPC and serialized submit RPC remain development-only. Must run actual PostgreSQL isolation/concurrency tests, including both transaction orderings, and UI tests before production authorization.
- No production Supabase/Worker changes or PR merge without separate approval.

## Backup and rollback
Before any authorized production operation, export existing chapter, activity, approval, assignment and submission/snapshot counts; rehearse rollback in isolated DB. If a new submission occurs after publication, do not overwrite in place again.
