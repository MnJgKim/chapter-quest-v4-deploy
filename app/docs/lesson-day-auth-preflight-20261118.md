# V4 lesson-day and session review — 2026-11-18

Status: DEVELOPMENT ONLY; no production schema/Worker changes or real student assignments.

## Verified read-only against production schema
- `cq_v4_my_lesson_schedule()` returns chapter UUID, title, date, release flag for the signed-in student; appropriate for future schedule preview.
- `cq_v4_my_released_chapters()` returns full questions only when `cq_v4_is_released` is true.
- `cq_v4_is_released()` currently permits dates **on or after** the lesson date, so it is not a same-day start authorization function.
- `cq_v4_submit_answers()` checks release and validates full answers/audio, but does not independently require the same Seoul calendar day.
- Storage speaking INSERT policy calls `cq_v4_is_released` and therefore also allows post-date upload. PDF-link authorization needs independent review.
- `cq_v4_parent_schedule_lesson()` is a parent-only rescheduling mechanism, but its current permission check does not represent an explicit, auditable make-up approval record.

## Implemented in development branch
- Student UI weekly preview requests `cq_v4_my_lesson_schedule`; only title/date is rendered for unreleased future lessons, not question JSON.
- Student start button requires both server-released chapter availability and matching Seoul date; client checks are defense in depth only.
- Parent email session restoration checks Supabase user identity and `cq_is_admin` after PIN unlock; project change/logout clears local refresh credentials.

## Blocking before production approval
1. Review-only trigger `app/sql/lesson-day-submit-guard.REVIEW-ONLY.sql` has not been applied or integration-tested. A before-INSERT trigger also runs on INSERT ... ON CONFLICT DO NOTHING; verify existing-submission idempotency behavior.
2. Enforce server-side **start/read** authorization separately from post-submission read-only access. Do not change `cq_v4_is_released` to equality unconditionally: it would break historical feedback and recording access.
3. Enforce same-day **speaking INSERT** in Storage policy and inspect the PDF-link Edge Function before claiming start protection. Preserve submitted-history read access.
4. Define auditable parent approval for make-up/retry, with an explicit revised date or exception; do not infer approval from a client flag.
5. Run isolated authorized/unauthorized integration tests with non-production fixtures, including Seoul 23:59/00:00 boundary, past submitted read, future schedule preview, cross-student access, token rotation, refresh failure, and logout.
6. Parent refresh tokens currently persist in localStorage (XSS/shared-device exposure). Review CSP, session revocation and device-specific logout; a local removal alone does not revoke a token at the Auth server.
7. Student persistent login exists, but the legacy resumed-anonymous account path intentionally does not auto-refresh; verify actual device behavior before changing it.

## Deployment and rollback
No production changes made. Before approval: snapshot RPC definitions, triggers, RLS and Storage policies; stage and test additive changes; verify parent/student account isolation. Roll back by restoring exact captured definitions and prior Worker version, never by deleting student submissions or PDFs.
