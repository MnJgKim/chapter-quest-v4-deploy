# Seowoo Chapter 1 — legacy approval recovery preflight (READ ONLY)

Target: `cda5aa92-39e5-4286-9595-5d80ca779b8f`, **Chapter 1 : The Dark Woods**.

## Verified on production (2026-11-20)
- Published activity has 10 questions, but `approval_id` and `approval_hash` are NULL.
- Exact matching approval request count is **0**; an older submission from a *different student account* exists and must be preserved.
- Existing `cq_v4_publish_approved` explicitly rejects changing a published activity whose approval differs.
- Published `cq_v4_activities` has **no answer key column**. A hash cannot be safely reconstructed from this table alone.
- Parent cloud snapshot's books list is empty. Do not restore it over the user's current local books.

## Safe resolution (requires real parent attestation)
1. Back up the *exact* published activity, its existing student submissions, relevant snapshots, PDF Storage metadata, and the release schedule; verify restore capability.
2. Retrieve the original parent-approved local chapter payload/approval receipt and answer key from the original device or an authentic backup. Verify source PDF association, all 10 questions and choices, vocabulary, writing and speaking prompts match the immutable server activity.
3. If the original receipt is unrecoverable, ask the parent to explicitly **reapprove the exact existing published questions** and independently supply/verify the answer key. Record the new attestation as a **new** approval, not as a fictitious historical approval.
4. Implement a narrowly scoped, separately authorized, auditable legacy reconciliation transaction. Require `auth.uid()` to equal the PDF owner, `cq_is_admin()`, the exact chapter UUID, PDF verified, published 10 questions, unchanged payload hash, and an existing *genuine* parent attestation whose content matches the immutable activity. Lock the activity and the attestation row; never modify questions, vocabulary, prompts, published_at, student submissions or snapshots. Abort if any guard fails.
5. Test rollback, cross-parent denial, repeated call idempotence, wrong hash, changed questions, and historic-submission preservation in isolated PostgreSQL. Deploy only after explicit production approval and a verified backup.
6. Re-read `approval_id` and `approval_hash` after the authorized reconciliation; verify grading and feedback on a **test account** without changing actual student data.

**Do not** run `cq_v4_publish_approved` on the legacy chapter to force a re-publish. **Do not** invent an ID, guess an answer key, backfill a hash without a genuine approval, or delete the old submission.

## Read-only production check
```sql
SELECT c.chapter_id,c.title,c.pdf_ready,
       jsonb_array_length(a.questions) AS question_count,
       a.approval_id,a.approval_hash,
       (SELECT count(*) FROM public.cq_v4_approval_requests r
         WHERE r.parent_user_id=c.parent_user_id
           AND r.questions=a.questions
           AND r.vocabulary=a.vocabulary
           AND r.writing_prompt IS NOT DISTINCT FROM a.writing_prompt
           AND r.speaking_prompt IS NOT DISTINCT FROM a.speaking_prompt) AS matching_approval_count,
       (SELECT count(*) FROM public.cq_v4_student_submissions s
         WHERE s.chapter_uuid=c.chapter_id) AS preserved_submissions
FROM public.cq_v4_pdf_chapters c
JOIN public.cq_v4_activities a ON a.chapter_uuid=c.chapter_id
WHERE c.chapter_id='cda5aa92-39e5-4286-9595-5d80ca779b8f';
```
