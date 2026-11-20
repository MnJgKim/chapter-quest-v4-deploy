# Chapter 2: Leaving Again — approval-key repair assessment (2026-11-20)

Read-only production inspection (no data changed):
- Chapter UUID: 8fe27ea2-b1ce-4404-a5bf-75b5a049a38a
- Approved question count: 6 (all multiple-choice)
- Published question count: 10 (7 MC, 2 short, 1 inference)
- Published questions 1–6 exactly match the approved questions 1–6.
- Approved answer_key: [1,3,0,1,1,0].
- Published question 7 asks: "What color was the silk bookmark in the Pennsylvania book?"
  Options: Blue / Red / Green / Yellow.
- Teacher-written synopsis (NOT a transcription of the source book) states that the Pennsylvania book has a red bookmark. Candidate seventh answer: 1 (zero-based).
- The stored approval content_hash matches activities.approval_hash, **but the
  published questions differ from the approved questions**. Matching stored
  hashes alone therefore does not establish that all 10 published questions
  were approved.

## Safety decision
Do not silently append an answer to the existing approval row. Doing so would
change approved material and may invalidate content-hash and snapshot
invariants. Obtain parent approval for the published seventh MC question and
verify against the original book before any production change.

Repair should create a new, fully validated approval artifact covering the
published 10-question structure (including the 7 MC answers), then use the
existing approval-and-publish workflow to atomically link its approval ID and
hash. Preserve historical submissions and immutable snapshots. Do not edit
existing submitted answers or historical grading.

Before deployment, confirm the reread scorer accepts answer_key length 7 for
10 mixed-kind questions and maps MC keys by MC position (or uses an explicit
question-index mapping). The current draft scorer indexes keys by question
position; for this chapter the first seven positions are MC so this is
compatible, but the draft scorer must NOT require one answer key per
non-MC question. Check other published mixed-kind chapters as well.

No production write authorized or performed.
