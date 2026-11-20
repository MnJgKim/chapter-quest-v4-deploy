# Chapter Quest V4 — live integration readiness (NO EXECUTION)

This is a preparation checklist, not evidence that live checks passed. Do not run against production without explicit approval and a verified rollback/backup.

## Preconditions
- Confirm exact Supabase project ref, expected auth issuer, Storage buckets, Edge Function versions, deployed Worker URL, and read-only parent/student test accounts. Never commit tokens, refresh tokens, secrets, or student answers.
- Record schema migrations and RLS policies, inspect review-only SQL diffs, and get explicit approval before **any** DB change or assignment. Do not create paid projects.
- Prefer isolated test environment. Live checks must not mutate production student records, uploads, enrollments, schedules, or releases.

## Read-only probes (authorized test identities only)
1. Auth: password login and refresh with the *same* test student's UID; confirm invalid JWT returns 401. Avoid logging bearer tokens.
2. Student RPC: read weekly schedule and approved chapters; verify Seoul date, weekday policy, order, max one new lesson/day, and unapproved lesson not released.
3. PDF: request cq-v4-pdf-link for authorized chapter; verify same project origin, exact `cq-v4-originals/{parent}/{chapter}.pdf` signed path, token, 120-second expiry, and PDF signature. Verify another student's chapter denied and submitted history remains readable.
4. Speaking: **do not upload** to production for a probe. Confirm Storage RLS policy and signed recovery contract from review; upload and replay only in approved isolated environment.
5. Submit: **do not submit** to production for a probe. Verify immutable post-submit RPC/storage policy with isolated PostgreSQL tests; check that new audio writes after submit are rejected.
6. Tablet: in an approved test environment, login -> view PDF -> record -> submit -> sign out -> reload; confirm cached JWT, PDF object URL, microphone, and recordings are not accessible after logout or account switch.
7. Parent: verify parent-only lesson context and answer key RLS; check objective MC score advisory with 60%, 70%, malformed key, and zero MC. This is **not** a delivered notification.

## Failure evidence and rollback
- Capture only redacted HTTP status, endpoint name, schema version, timestamp, and test-case ID; never record student PII, signed URLs, or auth tokens.
- Stop on 401/403 mismatch, leaked chapter, unexpected Storage write, or inconsistent submitted history.
- Roll back only the reviewed development branch commit or isolated test fixture; production rollback requires separate approval.
