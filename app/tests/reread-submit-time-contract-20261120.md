# Universal submit-time reread contract (development only)

## Product requirement (2026-11-20 clarification)
- Applies to **all existing and future PDF chapters**, including currently hidden Magic Tree House Book 2 chapters.
- **No full-server question/answer audit is a release prerequisite.** Do not pre-score hidden chapters.
- At the moment each student submits a lesson, score the student's MC answers against the **authoritative, matching, published question+answer version for that chapter**. Strictly below 70% requires rereading; 70% or more does not.
- Every later publication or approved edit must preserve this universal behavior automatically. Never bind the feature to a fixed chapter list, book, registration date, or manual parent toggle.
- Freeze the question/answer version and scoring outcome for a completed submission. Never silently rescore an existing immutable submission when a parent later edits content.
- If an answer key is missing/mismatched at submission time, expose an explicit scoring error and an actionable recovery path; never mark the student as passed. Preserve existing immutable submissions. Avoid silently accepting unscored submissions and avoid indefinitely blocking students solely because a hidden legacy chapter was never audited.
- Preserve student authorization and parent feedback gate. Existing Magic Tree House Book 2 Chapter 2 answer correction remains out of scope.

## Current development blockers (not resolved by this document)
1. Existing development trigger reads answer keys only from matching approval records; nine hidden legacy chapters have no linked approval record. This **must not** become a release-wide preflight requirement. Provide a chapter-local, versioned key resolution path at actual lesson publication/submission time.
2. Current development trigger raises an exception for missing keys, which would block an affected student submission; design a clear recoverable error state and ensure historical submissions remain untouched.
3. A robust versioned question/answer snapshot and score needs an isolated transaction test with the actual submit RPC and immutable snapshot implementation.
4. Verify newly edited questions use their own approved key, not a stale prior key; completed submissions retain original outcome.
5. Run authenticated browser end-to-end test of immediate warning and reread completion.

## Release gate
PostgreSQL 16 CI for generic existing/future chapters, new/edited versions, 60/70/80%, missing/mismatched keys, rollback, concurrent submissions and immutable snapshots; browser submission and reread verification; backup/restore rehearsal; separate production approval. Do not deploy this document or any development SQL to production.
