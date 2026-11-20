# Immutable reread grading snapshot — REVIEW ONLY (2026-11-18)

**Not deployed.** This is a proposed design and an explicit release blocker, not a verified production feature.

## Observed state

Connected Supabase active project `english-v3b-test` (not yet proven to be V4 production) exposes V4 tables with expected types and JSON structure. PostgreSQL catalog inspection showed RLS enabled for activities, approval requests, submissions, PDF chapters, assignments, and enrollments; zero direct policies for activities, approvals and submissions. Existing `cq_v4_*` RPCs are SECURITY DEFINER and grant EXECUTE to authenticated, not anon. New reread RPCs are not present. **Do not assume these facts prove end-to-end authorization or target project identity.**

## Critical flaw in current candidate

`cq_v4_parent_sync_reread_notice` reads `a.questions` and `r.answer_key` at **parent invocation time**, not at submission time. A post-submission republish, approval hash change, or modified key may change or block grading. Current isolated fixture even updates submitted answers for the 7/10 case, which does not model an immutable real submission. This must be resolved before any deployment.

## Proposed frozen-on-submission design

1. Add a private, append-only snapshot table (reviewed migration only) keyed by `(child_user_id,chapter_uuid)`, containing the immutable approved `approval_id`, `content_hash`, questions JSON, answer-key JSON, submitted answer array, submission timestamp, and optional canonical digest. **Never expose this table through the Data API**; revoke all direct grants, use RLS, and consider a private non-exposed schema.
2. In the existing authorized `cq_v4_submit_answers` transaction, after all reading/writing/speaking completion and assignment checks, copy the approved snapshot and validated submitted answers to the private table exactly once, atomically with submission creation. Never accept client-provided keys, hashes, scores or snapshot IDs. Do not copy a snapshot for rejected submissions.
3. Require the same immutable approval hash and chapter ownership at capture time. If an approved chapter is republished later, previously submitted snapshots remain unchanged. Define a migration strategy for preexisting submissions: fail closed or perform separately approved audited backfill, **never silently grade against today's approval**.
4. Parent grading RPC reads the frozen row only, verifies parent ownership and student enrollment, scores MC questions with zero-based numeric keys, and creates a unique `(student_user_id,chapter_uuid)` notice when correct/total is strictly below 70%. Short/inference answers do not affect the denominator. Idempotent duplicate calls return the same frozen result.
5. Parent inbox and acknowledgement RPCs reveal only the parent-owned notice; student RPC returns Boolean only when `feedback_released=true`. Student cannot read keys, scores, private snapshot or other students' data.
6. Migration must be additive and reversible without dropping existing submissions. If rollback removes new RPCs, both UIs fail closed and original feedback remains visible. Retain snapshots and notices for audit until an explicitly approved retention policy exists.

## Required isolated tests before approval

- Submit two distinct synthetic students/chapters with 6/10 and 7/10 results; **never UPDATE submitted answers** to simulate the boundary.
- After snapshot capture, mutate live activity questions, approval hash and approval key in an isolated transaction; frozen 6/10 result and one notice must remain stable.
- Concurrent parent RPC calls create one notice. Repeated calls after live approval changes return the same result.
- Cross-parent, other-student, anonymous and direct-table access denied; invalid keys/answer arrays fail closed.
- Failure midway through submission rolls back both submission and snapshot; duplicate submission cannot replace the frozen row.
- Legacy submission lacking a snapshot does not fall back to current answer key.
- Feedback-release Boolean and missing-RPC browser compatibility remain intact.

## Approval gate

No migration, production project identification, DB write, assignment, PR merge or deployment is authorized by this document. First implement and validate this design against isolated PostgreSQL; then compare with the *verified* production schema and get explicit approval for migration and rollback.
