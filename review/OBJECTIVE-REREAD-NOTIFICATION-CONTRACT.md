# Chapter Quest V4 — server-owned reread notification contract (REVIEW ONLY)

**Not deployed, not an operational notification service.** Parent UI currently computes a parent-only advisory from authenticated parent lesson context; no push/email/student notice is sent.

## Source-of-truth and grading boundary
- Only a server-side, authenticated parent-owned **published approval snapshot** may provide objective answer keys. Do not accept keys or score claims from student JSON, browser local storage, or a parent-submitted client score.
- Join an immutable submission to its chapter, exact student, owning parent, and immutable approval snapshot. Reject missing/ambiguous snapshot, mismatched question/answer lengths, malformed MC options/keys, or invalid MC answers. No score if there are zero MC questions.
- Numerator: correct multiple-choice answers; denominator: multiple-choice questions only. Do not grade inference, comprehension free-text, writing, or speaking. Use integer comparison `correct * 10 < mc_total * 7`; never round before threshold.
- Freeze the score source to the snapshot version used for submission; subsequent edits to parent materials must not change historical scores.

## Proposed persisted model (requires separate schema review)
- `cq_v4_reread_notices`: `id uuid`, `parent_user_id uuid`, `student_user_id uuid`, `chapter_uuid uuid`, `submitted_at timestamptz`, `approval_snapshot_id uuid`, `correct_mc integer`, `total_mc integer`, `created_at timestamptz`, `acknowledged_at timestamptz nullable`.
- Unique constraint `(student_user_id, chapter_uuid)` (submissions immutable). Idempotent server insert with `ON CONFLICT DO NOTHING`, inside the same trusted transaction or an idempotent parent-only server sync. Concurrent attempts must yield one notice.
- Enable RLS and explicitly REVOKE default table access. Parent SELECT/acknowledge only after matching authenticated parent ownership via enrollments **and** chapter ownership. No student SELECT of answer keys or notice rows by default; no client INSERT/UPDATE/DELETE of score fields. Service-role/SECURITY DEFINER writes only with fixed search_path, ownership checks and least-privilege EXECUTE.
- An acknowledged notice remains in history; no automatic resubmission or reopening of submitted answers/audio. Reading the original PDF remains permitted.

## Publication and delivery
- **Parent inbox**: show persisted notices only to owning parent; never claim email/push delivery without an actual transport and delivery receipt.
- **Student**: after parent explicitly releases feedback, an optional non-scoring reread suggestion may appear. Do not reveal correct answers, answer keys, or parent-private comments. No student warning before feedback release.
- Do not block the next authorized weekday or assign extra chapters based on the notice. Seoul weekday, one chapter/day and approved order remain authoritative.

## Required isolated tests before considering rollout
1. 6/10 creates one notice, 7/10 creates none, zero MC creates none, mixed MC/subjective excludes subjective.
2. Missing/malformed answer key, stale approval snapshot, or inconsistent submission returns no notice and no partial writes.
3. Repeated calls and two parallel transactions create exactly one notice; no updates to immutable submissions.
4. Parent A cannot view/acknowledge Parent B notices, even when chapter UUID is guessed; student/anon cannot read answer keys or parent inbox.
5. Parent acknowledgement cannot mutate scores, original PDF, recorded audio, schedule or student submission.
6. Feedback release gates any student-facing suggestion; no cross-student leak after logout or token refresh.
7. Use only isolated PostgreSQL 16 fixtures and synthetic users. Production migration, alerts and assignments require explicit approval.

## Rollback
- Before any approved deployment, snapshot schema, grants, RLS, and function definitions. Rollback only new notice tables/functions and parent UI integration after verifying no notice history is required for audit; do not touch student submissions, audio, PDF or lesson schedules.
