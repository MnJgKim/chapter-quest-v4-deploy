# Magic Tree House Book 2 Chapter 2 — replacement preflight (development only)

Existing chapter UUID: `8fe27ea2-b1ce-4404-a5bf-75b5a049a38a`.
Verified read-only 2026-11-20: 2 assignments, 0 submissions, 1 approval, 1 activity, 0 schedules.

Source: user-provided `2-2.pdf` (7 PDF pages, printed pp. 10–16).
Prepared parent-review import JSON separately in conversation artifacts:
`mth_book2_ch2_final_parent_review.json`. It has 10 questions,
7 MC, 2 short, 1 inference, 8 vocabulary items and page evidence.

## Blocking constraints verified from actual production RPC definitions

- `cq_v4_bind_verified_pdf` refuses binding another approval to a chapter
  that already has any different approval.
- `cq_v4_publish_approved` rejects replacing a published activity with a
  different approval ID/hash ('Published content is immutable').
- Do NOT delete the old approval or chapter to work around these guards.
- Student submissions currently 0, but recheck under a row lock immediately
  before the eventual replacement, because students may submit meanwhile.

## Proposed safe replacement design — NOT IMPLEMENTED OR APPROVED

1. Back up current chapter, approval, activity, assignments and storage metadata.
2. Validate the new approved questions/answers and exact verified PDF linkage.
3. Under a single server transaction and parent authorization, lock the
   chapter/activity, recheck no submissions, validate that the expected old
   approval ID/hash matches, then bind a new approval record and atomically
   replace the activity, keeping chapter UUID and existing assignments.
4. Preserve old approval as an audit record. The new approval must have a
   distinct request key and valid content hash.
5. Ensure existing read-only snapshot/assignment references remain valid.
6. Confirm a single chapter is visible to each assigned student, and that
   newly published questions/keys match before permitting submissions.
7. If any condition fails, rollback the entire replacement.

No production SQL, Worker deploy, or PR merge performed.
